'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState, useTransition } from 'react';
import {
  holdSeatsAction,
  issueCompsAction,
  releaseSeatsAction,
  revokeCompAction,
  saveAssignmentsAction,
  type SeatRes,
  type SeatRule,
} from '../organizer/actions';
import type { Layout } from '../lib/seat-layout';
import { DEFAULT_SEAT_COLORS, SeatMapView } from './SeatMapView';

export interface SeatRow {
  seatKey: string;
  status: string;
  ticketTypeId: string | null;
  holdLabel: string | null;
}
export interface Counts {
  available: number;
  held: number;
  guest: number;
  sold: number;
  comp: number;
}
export interface GuestRow {
  id: string;
  guestName: string | null;
  phone: string | null;
  seatLabel: string | null;
  seatLabelMy: string | null;
  label: string | null;
  status: string;
  checkedIn: boolean;
}
export interface TypeRow {
  id: string;
  name: string;
  nameMy: string | null;
}

type Target = { sectionKey: string; rowLabel?: string };

const fill = (s: string, n: number) => s.replace('{n}', String(n));

/** Rules after setting (or clearing, with null) the ticket type of a whole section or one row. */
export function applyRule(rules: SeatRule[], layout: Layout, target: Target, typeId: string | null): SeatRule[] {
  const { sectionKey, rowLabel } = target;
  if (rowLabel == null) {
    const next = rules.filter((r) => r.sectionKey !== sectionKey);
    if (typeId) next.push({ sectionKey, ticketTypeId: typeId });
    return next;
  }
  const sectionRule = rules.find((r) => r.sectionKey === sectionKey && r.rowLabel == null);
  let next = rules.filter((r) => !(r.sectionKey === sectionKey && r.rowLabel === rowLabel));
  if (typeId) {
    next.push({ sectionKey, rowLabel, ticketTypeId: typeId });
  } else if (sectionRule) {
    // A row cannot be carved out of a section rule, so spell the section out row by row without this one
    next = next.filter((r) => !(r.sectionKey === sectionKey && r.rowLabel == null));
    for (const row of layout.sections.find((s) => s.key === sectionKey)?.rows ?? []) {
      if (row.label !== rowLabel && !next.some((r) => r.sectionKey === sectionKey && r.rowLabel === row.label)) {
        next.push({ sectionKey, rowLabel: row.label, ticketTypeId: sectionRule.ticketTypeId });
      }
    }
  }
  return next;
}

export function SeatsManager({
  orgId,
  eventId,
  lang,
  labels: L,
  layout,
  types,
  rules: initialRules,
  seats,
  counts,
  colors,
  guests,
  canEdit,
}: {
  orgId: string;
  eventId: string;
  lang: 'en' | 'my';
  labels: Record<string, string>;
  layout: Layout;
  types: TypeRow[];
  rules: SeatRule[];
  seats: SeatRow[];
  counts: Record<string, Counts>;
  /** Ticket type id -> map colour, as the API gives the buyer apps (GET seating `colors`). */
  colors: Record<string, string>;
  guests: GuestRow[];
  canEdit: boolean;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [mode, setMode] = useState<'assign' | 'guests'>('assign');
  const [areaMode, setAreaMode] = useState(false);
  const [target, setTarget] = useState<Target | null>(null);
  const [standing, setStanding] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [msg, setMsg] = useState<{ kind: 'error' | 'ok'; text: string } | null>(null);
  const [holdLabel, setHoldLabel] = useState('');
  const [guestName, setGuestName] = useState('');
  const [phone, setPhone] = useState('');
  const [compLabel, setCompLabel] = useState('');
  const [picked, setPicked] = useState<Set<string>>(new Set());

  const rules = useMemo(() => initialRules.map((r) => ({ ...r, rowLabel: r.rowLabel ?? undefined })), [initialRules]);
  const tName = (t: TypeRow) => (lang === 'my' && t.nameMy) || t.name;
  const typeIdx = useMemo(() => new Map(types.map((t, i) => [t.id, i])), [types]);
  const typeColors = useMemo(() => types.map((t, i) => colors[t.id] ?? DEFAULT_SEAT_COLORS[i % DEFAULT_SEAT_COLORS.length]), [types, colors]);
  const bySeat = useMemo(() => new Map(seats.map((s) => [s.seatKey, s])), [seats]);

  const { seatTypes, status, held } = useMemo(() => {
    const seatTypes: Record<string, number> = {};
    const status: Record<string, string> = {};
    const held = new Set<string>();
    for (const s of seats) {
      if (s.ticketTypeId && typeIdx.has(s.ticketTypeId)) seatTypes[s.seatKey] = typeIdx.get(s.ticketTypeId)!;
      if (s.status === 'SOLD' || s.status === 'CHECKOUT_HOLD') status[s.seatKey] = 'SOLD';
      if (s.status === 'GUEST_HOLD') held.add(s.seatKey);
    }
    return { seatTypes, status, held };
  }, [seats, typeIdx]);

  const legend = useMemo(() => {
    const n = new Map<string, number>();
    let none = 0;
    for (const s of seats) {
      if (s.ticketTypeId) n.set(s.ticketTypeId, (n.get(s.ticketTypeId) ?? 0) + 1);
      else none++;
    }
    return { n, none, guest: held.size, taken: Object.keys(status).length };
  }, [seats, held, status]);

  const run = (f: () => Promise<SeatRes<unknown>>, ok: string, after?: () => void) => {
    setMsg(null);
    start(async () => {
      const r = await f();
      if (r.ok) {
        setMsg({ kind: 'ok', text: ok });
        after?.();
        router.refresh();
      } else {
        setMsg({ kind: 'error', text: r.error });
      }
    });
  };

  // ── assign mode
  const openTarget = (t: Target) => {
    const sec = layout.sections.find((s) => s.key === t.sectionKey);
    setMsg(null);
    if (!sec || sec.kind !== 'SEATED') {
      setTarget(null);
      setStanding(true);
      return;
    }
    setStanding(false);
    setTarget(t);
  };
  const assign = (typeId: string | null) => {
    if (!target) return;
    run(() => saveAssignmentsAction(orgId, eventId, applyRule(rules, layout, target, typeId)), L.stAssigned, () => setTarget(null));
  };
  const currentTypeOf = (t: Target) =>
    rules.find((r) => r.sectionKey === t.sectionKey && r.rowLabel === t.rowLabel)?.ticketTypeId ??
    (t.rowLabel != null ? rules.find((r) => r.sectionKey === t.sectionKey && r.rowLabel == null)?.ticketTypeId : undefined);
  const dropsOverrides = (t: Target) => t.rowLabel == null && rules.some((r) => r.sectionKey === t.sectionKey && r.rowLabel != null);
  const targetName = (t: Target) => {
    const sec = layout.sections.find((s) => s.key === t.sectionKey);
    const secName = (lang === 'my' && sec?.nameMy) || sec?.name || t.sectionKey;
    return t.rowLabel != null ? `${secName} · ${L.stRowWord} ${t.rowLabel}` : `${secName} (${L.stSectionWord})`;
  };

  // ── guests mode
  const toggle = (key: string) => {
    setMsg(null);
    setSelected((cur) => {
      const n = new Set(cur);
      if (n.has(key)) n.delete(key);
      else n.add(key);
      return n;
    });
  };
  const selectMany = (keys: string[], add: boolean) => {
    setMsg(null);
    setSelected((cur) => new Set(add ? [...cur, ...keys] : keys));
  };
  const sel = useMemo(() => {
    let available = 0;
    let heldN = 0;
    let other = 0;
    const heldLabels = new Set<string>();
    for (const k of selected) {
      const s = bySeat.get(k);
      if (s?.status === 'AVAILABLE') available++;
      else if (s?.status === 'GUEST_HOLD') {
        heldN++;
        if (s.holdLabel) heldLabels.add(s.holdLabel);
      } else other++;
    }
    return { available, heldN, other, heldLabels: [...heldLabels] };
  }, [selected, bySeat]);
  const keys = [...selected];
  const canHold = canEdit && !pending && keys.length > 0 && sel.available === keys.length && holdLabel.trim() !== '';
  const canRelease = canEdit && !pending && keys.length > 0 && sel.heldN === keys.length;
  const canIssue = canRelease && guestName.trim() !== '' && phone.trim() !== '';

  const changeMode = (m: 'assign' | 'guests') => {
    setMode(m);
    setMsg(null);
    setTarget(null);
    setStanding(false);
  };

  const printBase = `/organizer/${orgId}/events/${eventId}`;
  const live = guests.filter((g) => g.status === 'VALID');
  const liveIds = new Set(live.map((g) => g.id));
  const pickedLive = [...picked].filter((x) => liveIds.has(x));
  const ids = pickedLive.join(',');
  const printHref = `${printBase}/seats/print${ids ? `?ids=${ids}` : ''}`;
  const pdfHref = `${printBase}/comps.pdf${ids ? `?ids=${ids}` : ''}`;

  return (
    <>
      <div className="row" role="tablist" style={{ marginBottom: 12 }}>
        {(['assign', 'guests'] as const).map((m) => (
          <button key={m} type="button" role="tab" aria-selected={mode === m} className={mode === m ? undefined : 'secondary'} onClick={() => changeMode(m)}>
            {m === 'assign' ? L.stModeAssign : L.stModeGuests}
          </button>
        ))}
      </div>

      {msg && <div className={msg.kind === 'error' ? 'error' : 'ok'} role="status">{msg.text}</div>}

      <div className="seats-grid">
        <div className="seats-map">
          {mode === 'guests' && (
            <label className="check">
              <input type="checkbox" checked={areaMode} onChange={(e) => setAreaMode(e.target.checked)} />
              <span>{L.stSelectArea}</span>
            </label>
          )}
          <SeatMapView
            layout={layout}
            seatTypes={seatTypes}
            status={status}
            colors={typeColors}
            held={held}
            selected={mode === 'guests' ? selected : undefined}
            onToggle={mode === 'guests' ? toggle : undefined}
            onSelectMany={mode === 'guests' ? selectMany : undefined}
            boxSelect={mode === 'guests' ? (areaMode ? 'always' : 'shift') : 'off'}
            onSectionClick={mode === 'assign' && canEdit ? (k) => openTarget({ sectionKey: k }) : undefined}
            onRowClick={mode === 'assign' && canEdit ? (k, r) => openTarget({ sectionKey: k, rowLabel: r }) : undefined}
            showRowLabels
            lang={lang}
            ariaLabel={L.smSeatMap}
            stageLabel={L.smStage}
          />
        </div>

        <div className="seats-side">
          <div className="card">
            <strong>{L.stLegend}</strong>
            <ul className="legend">
              {types.map((t, i) => (
                <li key={t.id}>
                  <span className="sw" style={{ background: typeColors[i] }} />
                  <span>{tName(t)}</span>
                  <span className="muted">{legend.n.get(t.id) ?? 0} {L.stSeatsWord}</span>
                </li>
              ))}
              <li><span className="sw" style={{ background: '#e5e3ee' }} /><span>{L.stUnassigned}</span><span className="muted">{legend.none} {L.stSeatsWord}</span></li>
              <li><span className="sw hatched" /><span>{L.stLegGuest}</span><span className="muted">{legend.guest}</span></li>
              <li><span className="sw" style={{ background: '#c9c7d1' }} /><span>{L.stLegTaken}</span><span className="muted">{legend.taken}</span></li>
            </ul>
          </div>

          {mode === 'assign' && (
            <div className="card">
              <p className="muted" style={{ marginTop: 0 }}>{L.stAssignHint}</p>
              {standing && <p className="muted">{L.stStandingNote}</p>}
              {target && (
                <div role="dialog" aria-label={`${L.stPickFor} ${targetName(target)}`}>
                  <strong>{L.stPickFor} {targetName(target)}</strong>
                  {dropsOverrides(target) && <p className="muted" style={{ margin: '6px 0 0' }}>{L.stOverrideHint}</p>}
                  <div className="type-picker">
                    {types.map((t, i) => (
                      <button
                        key={t.id}
                        type="button"
                        className={currentTypeOf(target) === t.id ? undefined : 'secondary'}
                        disabled={pending}
                        onClick={() => assign(t.id)}
                      >
                        <span className="sw" style={{ background: typeColors[i] }} /> {tName(t)}
                      </button>
                    ))}
                    <button type="button" className="secondary" disabled={pending} onClick={() => assign(null)}>{L.stUnassign}</button>
                    <button type="button" className="link" onClick={() => setTarget(null)}>{L.stClose}</button>
                  </div>
                </div>
              )}
            </div>
          )}

          {mode === 'guests' && (
            <div className="card">
              <p className="muted" style={{ marginTop: 0 }}>{L.stHint}</p>
              <p>
                <strong>{L.stSelected}: {keys.length}</strong>
                {keys.length > 0 && (
                  <span className="muted">
                    {' '}({sel.available} {L.stSelAvailable}, {sel.heldN} {L.stSelHeld}{sel.other ? `, ${sel.other} ${L.stSelOther}` : ''})
                  </span>
                )}{' '}
                {keys.length > 0 && <button type="button" className="link" onClick={() => setSelected(new Set())}>{L.stClear}</button>}
              </p>
              <div className="field">
                <label htmlFor="hold-label">{L.stHoldLabel}</label>
                <input id="hold-label" value={holdLabel} maxLength={100} onChange={(e) => setHoldLabel(e.target.value)} />
              </div>
              <div className="row">
                <button type="button" disabled={!canHold} onClick={() => run(() => holdSeatsAction(orgId, eventId, keys, holdLabel.trim()), fill(L.stHeldOk, keys.length), () => setSelected(new Set()))}>
                  {L.stHold}
                </button>
                <button type="button" className="secondary" disabled={!canRelease} onClick={() => run(() => releaseSeatsAction(orgId, eventId, keys), fill(L.stReleasedOk, keys.length), () => setSelected(new Set()))}>
                  {L.stRelease}
                </button>
              </div>

              <h3 style={{ marginBottom: 6 }}>{L.stIssueTitle}</h3>
              <p className="muted" style={{ marginTop: 0 }}>{L.stIssueHint}</p>
              <div className="field"><label htmlFor="g-name">{L.stGuestName}</label><input id="g-name" value={guestName} maxLength={200} onChange={(e) => setGuestName(e.target.value)} /></div>
              <div className="field"><label htmlFor="g-phone">{L.phone}</label><input id="g-phone" inputMode="tel" placeholder="09xxxxxxxxx" value={phone} maxLength={30} onChange={(e) => setPhone(e.target.value)} /></div>
              <div className="field">
                <label htmlFor="g-label">{L.stCompLabel}</label>
                <input id="g-label" value={compLabel} placeholder={sel.heldLabels.join(', ')} maxLength={100} onChange={(e) => setCompLabel(e.target.value)} />
              </div>
              <button
                type="button"
                className="btn-gold"
                disabled={!canIssue}
                onClick={() =>
                  run(
                    () => issueCompsAction(orgId, eventId, { seats: keys, guestName: guestName.trim(), phone: phone.trim(), label: compLabel.trim() || undefined }),
                    fill(L.stIssuedOk, keys.length),
                    () => {
                      setSelected(new Set());
                      setGuestName('');
                      setPhone('');
                      setCompLabel('');
                    },
                  )
                }
              >
                {L.stIssue}
              </button>
            </div>
          )}
        </div>
      </div>

      <h2>{L.stCounts}</h2>
      <div className="table-card">
        <table>
          <thead>
            <tr><th>{L.name}</th><th>{L.stAvailable}</th><th>{L.stCheckout}</th><th>{L.stGuestHeld}</th><th>{L.stSold}</th><th>{L.stComps}</th></tr>
          </thead>
          <tbody>
            {types.map((t, i) => {
              const c = counts[t.id];
              return (
                <tr key={t.id}>
                  <td><span className="sw" style={{ background: typeColors[i] }} /> {tName(t)}</td>
                  <td>{c?.available ?? 0}</td><td>{c?.held ?? 0}</td><td>{c?.guest ?? 0}</td><td>{c?.sold ?? 0}</td><td>{c?.comp ?? 0}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <h2>{L.stGuestList}</h2>
      <div className="table-card">
        {guests.length === 0 ? (
          <p className="muted">{L.stNoGuests}</p>
        ) : (
          <>
            <div className="card-pad row">
              <a className="btn" href={printHref} target="_blank" rel="noreferrer">
                {pickedLive.length ? fill(L.stPrintSel, pickedLive.length) : L.stPrint}
              </a>
              <a className="btn secondary" href={pdfHref}>{pickedLive.length ? fill(L.stPdfSel, pickedLive.length) : L.stPdfAll}</a>
              <span className="muted small">{L.stPdfNote}</span>
            </div>
            <table>
              <thead>
                <tr>
                  <th>
                    <input type="checkbox" aria-label={L.stSelectAll} checked={live.length > 0 && pickedLive.length === live.length} onChange={(e) => setPicked(e.target.checked ? new Set(live.map((g) => g.id)) : new Set())} />
                  </th>
                  <th>{L.stGuestName}</th><th>{L.phone}</th><th>{L.stSeat}</th><th>{L.stCompLabel}</th><th>{L.status}</th><th />
                </tr>
              </thead>
              <tbody>
                {guests.map((g) => (
                  <tr key={g.id} className={g.status === 'VALID' || g.status === 'CHECKED_IN' ? undefined : 'dim'}>
                    <td>
                      {g.status === 'VALID' && (
                        <input
                          type="checkbox"
                          aria-label={g.guestName ?? g.id}
                          checked={picked.has(g.id)}
                          onChange={(e) => setPicked((cur) => { const n = new Set(cur); if (e.target.checked) n.add(g.id); else n.delete(g.id); return n; })}
                        />
                      )}
                    </td>
                    <td>{g.guestName ?? '—'}</td>
                    <td>{g.phone ?? '—'}</td>
                    <td>{(lang === 'my' && g.seatLabelMy) || g.seatLabel}</td>
                    <td>{g.label ?? ''}</td>
                    <td>
                      {g.checkedIn ? <span className="badge PUBLISHED">{L.stIn}</span> : g.status === 'VALID' ? <span className="badge">{L.stNotIn}</span> : <span className="badge CANCELLED">{L.stRevoked}</span>}
                    </td>
                    <td>
                      {canEdit && g.status === 'VALID' && (
                        <button
                          type="button"
                          className="danger"
                          disabled={pending}
                          onClick={() => {
                            if (window.confirm(L.stRevokeConfirm)) run(() => revokeCompAction(orgId, eventId, g.id), L.stRevokedOk, () => setPicked((cur) => { const n = new Set(cur); n.delete(g.id); return n; }));
                          }}
                        >
                          {L.stRevoke}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </div>
    </>
  );
}
