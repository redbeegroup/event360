'use client';

import { useMemo, useRef, useState, useTransition } from 'react';
import type { FormState } from '../actions';
import { expandSeats, validateLayout, type Layout, type LayoutRow, type LayoutSection, type SeatAttr } from '../lib/seat-layout';
import { SeatMapView } from './SeatMapView';

type Labels = Record<string, string>;

export interface SeatMapEditorProps {
  initial: Layout;
  /** Saves the layout as the draft. */
  onSave: (layout: Layout) => Promise<FormState>;
  /** Imports a layout through the API's import endpoint (also saves it as the draft). */
  onImport?: (layout: Layout) => Promise<FormState>;
  /** Publishes the saved draft. */
  onPublish?: () => Promise<FormState>;
  labels: Labels;
  lang?: 'en' | 'my';
}

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));
const rowLabelFor = (i: number) => (i < 26 ? String.fromCharCode(65 + i) : String(i + 1));
const numOr = (v: string, d?: number) => (v.trim() === '' || !Number.isFinite(Number(v)) ? d : Number(v));

/** Builds rows of seats for the "add seated section" form. */
function buildRows(rows: number, perRow: number, start: number, dir: 'LTR' | 'RTL', parity: 'ALL' | 'ODD' | 'EVEN'): LayoutRow[] {
  const step = parity === 'ALL' ? 1 : 2;
  let base = start;
  if (parity === 'ODD' && base % 2 === 0) base += 1;
  if (parity === 'EVEN' && base % 2 !== 0) base += 1;
  return Array.from({ length: rows }, (_, r) => ({
    label: rowLabelFor(r),
    seats: Array.from({ length: perRow }, (_, i) => ({ n: base + step * (dir === 'LTR' ? i : perRow - 1 - i) })),
  }));
}

/** Index of the seat after which a gap sits (0 = none). */
const gapIndexes = (row: LayoutRow) => row.seats.flatMap((s, idx) => (idx > 0 && (s.gapBefore ?? 0) > 0 ? [idx] : []));
const gapAfterOf = (row: LayoutRow) => gapIndexes(row)[0] ?? 0;

export function SeatMapEditor({ initial, onSave, onImport, onPublish, labels: L, lang }: SeatMapEditorProps) {
  const [layout, setLayout] = useState<Layout>(() => clone(initial));
  const [activeKey, setActiveKey] = useState<string | null>(initial.sections[0]?.key ?? null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [json, setJson] = useState('');
  const [result, setResult] = useState<FormState | null>(null);
  const [dirty, setDirty] = useState(false);
  const [pending, start] = useTransition();

  // new seated section form
  const [ns, setNs] = useState({ key: '', name: '', rows: '5', perRow: '10', start: '1', dir: 'LTR', parity: 'ALL' });
  // new standing section form
  const [nt, setNt] = useState({ key: '', name: '', capacity: '200', w: '300', h: '120' });

  const check = useMemo(() => validateLayout(layout), [layout]);
  const lastValid = useRef<Layout | null>(null);
  if (check.ok) lastValid.current = check.layout;
  const problems = check.ok ? [] : check.problems;
  const seatCount = useMemo(() => (check.ok ? expandSeats(check.layout).length : 0), [check]);
  const active = layout.sections.find((s) => s.key === activeKey) ?? null;

  const edit = (fn: (l: Layout) => void) => {
    setLayout((prev) => {
      const next = clone(prev);
      fn(next);
      return next;
    });
    setDirty(true);
    setResult(null);
  };
  const editSection = (key: string, fn: (s: LayoutSection) => void) =>
    edit((l) => {
      const s = l.sections.find((x) => x.key === key);
      if (s) fn(s);
    });

  const nextY = () => layout.sections.reduce((m, s) => Math.max(m, s.y + (s.kind === 'STANDING' ? (s.h ?? 100) : (s.rows?.length ?? 0) * 24)), 140) + 60;
  const uniqueKey = (wanted: string) => {
    let k = wanted.trim().replace(/:/g, '') || `S${layout.sections.length + 1}`;
    const taken = new Set(layout.sections.map((s) => s.key));
    let i = 2;
    const base = k;
    while (taken.has(k)) k = `${base}${i++}`;
    return k;
  };

  const addSeated = () => {
    const key = uniqueKey(ns.key);
    const rows = buildRows(Math.max(1, numOr(ns.rows, 1)!), Math.max(1, numOr(ns.perRow, 1)!), numOr(ns.start, 1)!, ns.dir as 'LTR' | 'RTL', ns.parity as 'ALL' | 'ODD' | 'EVEN');
    edit((l) => {
      l.sections.push({ key, name: ns.name.trim() || key, kind: 'SEATED', x: 120, y: nextY(), rows });
    });
    setActiveKey(key);
  };
  const addStanding = () => {
    const key = uniqueKey(nt.key);
    edit((l) => {
      l.sections.push({ key, name: nt.name.trim() || key, kind: 'STANDING', x: 120, y: nextY(), capacity: Math.max(1, numOr(nt.capacity, 1)!), w: numOr(nt.w, 300), h: numOr(nt.h, 120) });
    });
    setActiveKey(key);
  };
  const removeSection = (key: string) => {
    edit((l) => {
      l.sections = l.sections.filter((s) => s.key !== key);
    });
    setActiveKey(null);
  };

  const setSectionKey = (oldKey: string, newKey: string) => {
    editSection(oldKey, (s) => {
      s.key = newKey;
    });
    setActiveKey(newKey);
    setSelected(new Set());
  };

  // ---- seat-level editing ----
  const toggleSeat = (k: string) =>
    setSelected((prev) => {
      const n = new Set(prev);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  const seatKeyOf = (secKey: string, row: LayoutRow, s: { n: number; label?: string }) => `${secKey}:${row.label}:${s.label ?? s.n}`;
  const eachSelectedSeat = (l: Layout, fn: (seat: LayoutRow['seats'][number], row: LayoutRow, sec: LayoutSection) => void) => {
    for (const sec of l.sections) for (const row of sec.rows ?? []) for (const seat of row.seats) if (selected.has(seatKeyOf(sec.key, row, seat))) fn(seat, row, sec);
  };
  const removeSelected = () => {
    edit((l) => {
      for (const sec of l.sections) {
        if (!sec.rows) continue;
        for (const row of sec.rows) row.seats = row.seats.filter((s) => !selected.has(seatKeyOf(sec.key, row, s)));
        sec.rows = sec.rows.filter((r) => r.seats.length > 0);
      }
    });
    setSelected(new Set());
  };
  const mark = (attr: SeatAttr) =>
    edit((l) =>
      eachSelectedSeat(l, (seat) => {
        const set = new Set(seat.attrs ?? []);
        set.add(attr);
        seat.attrs = [...set];
      }),
    );
  const clearMarks = () =>
    edit((l) =>
      eachSelectedSeat(l, (seat) => {
        delete seat.attrs;
      }),
    );

  // ---- row editing ----
  const setRowSeatCount = (sec: string, ri: number, count: number) =>
    editSection(sec, (s) => {
      const row = s.rows![ri];
      const c = Math.max(1, count);
      while (row.seats.length > c) row.seats.pop();
      const used = new Set(row.seats.map((x) => x.label ?? String(x.n)));
      while (row.seats.length < c) {
        const len = row.seats.length;
        const last = row.seats[len - 1]?.n ?? 0;
        // Step from the last two seats (RTL rows descend, odd/even rows step by 2); default +1.
        let step = len >= 2 ? last - row.seats[len - 2].n : 1;
        if (!step) step = 1;
        let n = last + step;
        while (n < 1 || used.has(String(n))) n = n < 1 ? Math.max(...row.seats.map((x) => x.n), 0) + 1 : n + (step > 0 ? step : 1);
        used.add(String(n));
        row.seats.push({ n });
      }
    });
  const setRowGap = (sec: string, ri: number, after: number) =>
    editSection(sec, (s) => {
      const row = s.rows![ri];
      const old = gapIndexes(row)[0];
      const width = old != null ? row.seats[old].gapBefore || 1 : 1;
      if (old != null) delete row.seats[old].gapBefore;
      if (after > 0 && after < row.seats.length) row.seats[after].gapBefore = width;
    });
  const setRowLabel = (sec: string, ri: number, label: string) =>
    editSection(sec, (s) => {
      s.rows![ri].label = label;
    });

  // ---- server calls ----
  const run = (fn: () => Promise<FormState>, after?: (r: FormState) => void) =>
    start(async () => {
      const r = await fn();
      setResult(r);
      if (!r.error && !r.problems?.length) {
        setDirty(false);
        after?.(r);
      }
    });
  const save = () => run(() => onSave(layout));
  const publish = () => {
    if (!onPublish || !window.confirm(L.smPublishConfirm)) return;
    run(async () => {
      const s = await onSave(layout);
      if (s.error || s.problems?.length) return s;
      return onPublish();
    });
  };
  const doExport = () => setJson(JSON.stringify(layout, null, 2));
  const doImport = () => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(json);
    } catch {
      setResult({ error: L.smInvalidJson });
      return;
    }
    const v = validateLayout(parsed);
    if (!v.ok) {
      setResult({ error: L.smInvalidLayout, problems: v.problems });
      return;
    }
    setLayout(v.layout);
    setActiveKey(v.layout.sections[0]?.key ?? null);
    setSelected(new Set());
    setDirty(true);
    run(() => (onImport ?? onSave)(v.layout), () => setResult({ ok: 'imported' }));
  };

  const okText: Record<string, string> = { saved: L.smSaved, published: L.smPublishedOk, imported: L.smImported };

  return (
    <div className="seat-editor">
      <div className="seat-editor-side">
        <div className="card">
          <h3 style={{ marginTop: 0 }}>{L.smSections}</h3>
          {layout.sections.length === 0 && <p className="muted">{L.smNoSections}</p>}
          <div className="col" style={{ display: 'grid', gap: 6 }}>
            {layout.sections.map((s) => (
              <button key={s.key} type="button" className={s.key === activeKey ? '' : 'secondary'} onClick={() => setActiveKey(s.key)} style={{ textAlign: 'left' }}>
                {s.key} · {s.name} {s.kind === 'STANDING' ? `(${L.smStanding})` : ''}
              </button>
            ))}
          </div>
        </div>

        <details className="card">
          <summary>{L.smAddSeated}</summary>
          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
            <div className="field"><label>{L.smKey}</label><input value={ns.key} onChange={(e) => setNs({ ...ns, key: e.target.value })} /></div>
            <div className="field"><label>{L.smSectionName}</label><input value={ns.name} onChange={(e) => setNs({ ...ns, name: e.target.value })} /></div>
            <div className="field"><label>{L.smRows}</label><input type="number" min={1} value={ns.rows} onChange={(e) => setNs({ ...ns, rows: e.target.value })} /></div>
            <div className="field"><label>{L.smSeatsPerRow}</label><input type="number" min={1} value={ns.perRow} onChange={(e) => setNs({ ...ns, perRow: e.target.value })} /></div>
            <div className="field"><label>{L.smStartNumber}</label><input type="number" value={ns.start} onChange={(e) => setNs({ ...ns, start: e.target.value })} /></div>
            <div className="field">
              <label>{L.smDirection}</label>
              <select value={ns.dir} onChange={(e) => setNs({ ...ns, dir: e.target.value })}>
                <option value="LTR">{L.smLtr}</option>
                <option value="RTL">{L.smRtl}</option>
              </select>
            </div>
            <div className="field">
              <label>{L.smNumbering}</label>
              <select value={ns.parity} onChange={(e) => setNs({ ...ns, parity: e.target.value })}>
                <option value="ALL">{L.smAll}</option>
                <option value="ODD">{L.smOdd}</option>
                <option value="EVEN">{L.smEven}</option>
              </select>
            </div>
          </div>
          <button type="button" onClick={addSeated}>{L.smAdd}</button>
        </details>

        <details className="card">
          <summary>{L.smAddStanding}</summary>
          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
            <div className="field"><label>{L.smKey}</label><input value={nt.key} onChange={(e) => setNt({ ...nt, key: e.target.value })} /></div>
            <div className="field"><label>{L.smSectionName}</label><input value={nt.name} onChange={(e) => setNt({ ...nt, name: e.target.value })} /></div>
            <div className="field"><label>{L.smCapacity}</label><input type="number" min={1} value={nt.capacity} onChange={(e) => setNt({ ...nt, capacity: e.target.value })} /></div>
            <div className="field"><label>{L.smWidth}</label><input type="number" value={nt.w} onChange={(e) => setNt({ ...nt, w: e.target.value })} /></div>
            <div className="field"><label>{L.smHeight}</label><input type="number" value={nt.h} onChange={(e) => setNt({ ...nt, h: e.target.value })} /></div>
          </div>
          <button type="button" onClick={addStanding}>{L.smAdd}</button>
        </details>

        <details className="card">
          <summary>{L.smCanvas} / {L.smStage}</summary>
          <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
            <div className="field"><label>{L.smWidth}</label><input type="number" value={layout.width} onChange={(e) => edit((l) => { l.width = Math.max(1, numOr(e.target.value, 1)!); })} /></div>
            <div className="field"><label>{L.smHeight}</label><input type="number" value={layout.height} onChange={(e) => edit((l) => { l.height = Math.max(1, numOr(e.target.value, 1)!); })} /></div>
            {!layout.stage && (
              <div className="field"><button type="button" className="secondary" onClick={() => edit((l) => { l.stage = { x: Math.round(l.width / 2 - 280), y: 40, w: 560, h: 60, label: L.smStage }; })}>{L.smAddStage}</button></div>
            )}
            {layout.stage && (
              <>
                {(['x', 'y', 'w', 'h'] as const).map((f) => (
                  <div className="field" key={f}>
                    <label>{L.smStage} {f}</label>
                    <input type="number" value={layout.stage![f]} onChange={(e) => edit((l) => { l.stage![f] = numOr(e.target.value, 0)!; })} />
                  </div>
                ))}
                <div className="field"><label>{L.smStageLabel}</label><input value={layout.stage.label ?? ''} onChange={(e) => edit((l) => { l.stage!.label = e.target.value; })} /></div>
              </>
            )}
          </div>
        </details>

        {active && (
          <div className="card">
            <h3 style={{ marginTop: 0 }}>{L.smEditSection}: {active.key}</h3>
            <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
              <div className="field"><label>{L.smKey}</label><input value={active.key} onChange={(e) => setSectionKey(active.key, e.target.value)} /></div>
              <div className="field"><label>{L.smSectionName}</label><input value={active.name} onChange={(e) => editSection(active.key, (s) => { s.name = e.target.value; })} /></div>
              <div className="field"><label>{L.smSectionNameMy}</label><input value={active.nameMy ?? ''} onChange={(e) => editSection(active.key, (s) => { s.nameMy = e.target.value || undefined; })} /></div>
              <div className="field"><label>X</label><input type="number" value={active.x} onChange={(e) => editSection(active.key, (s) => { s.x = numOr(e.target.value, 0)!; })} /></div>
              <div className="field"><label>Y</label><input type="number" value={active.y} onChange={(e) => editSection(active.key, (s) => { s.y = numOr(e.target.value, 0)!; })} /></div>
              <div className="field"><label>{L.smRotation}</label><input type="number" value={active.rotation ?? 0} onChange={(e) => editSection(active.key, (s) => { s.rotation = numOr(e.target.value, 0); })} /></div>
              {active.kind === 'SEATED' ? (
                <div className="field"><label>{L.smCurve}</label><input type="number" step="0.01" value={active.curve ?? 0} onChange={(e) => editSection(active.key, (s) => { s.curve = numOr(e.target.value, 0); })} /></div>
              ) : (
                <>
                  <div className="field"><label>{L.smCapacity}</label><input type="number" min={1} value={active.capacity ?? 0} onChange={(e) => editSection(active.key, (s) => { s.capacity = numOr(e.target.value, 0); })} /></div>
                  <div className="field"><label>{L.smWidth}</label><input type="number" value={active.w ?? 0} onChange={(e) => editSection(active.key, (s) => { s.w = numOr(e.target.value, 0); })} /></div>
                  <div className="field"><label>{L.smHeight}</label><input type="number" value={active.h ?? 0} onChange={(e) => editSection(active.key, (s) => { s.h = numOr(e.target.value, 0); })} /></div>
                </>
              )}
            </div>
            {active.kind === 'SEATED' && (
              <div className="table-wrap">
                <table>
                  <thead><tr><th>{L.smRowLabel}</th><th>{L.smSeatCount}</th><th>{L.smGapAfter}</th></tr></thead>
                  <tbody>
                    {(active.rows ?? []).map((row, ri) => (
                      <tr key={ri}>
                        <td><input style={{ width: 70 }} value={row.label} onChange={(e) => setRowLabel(active.key, ri, e.target.value)} /></td>
                        <td><input style={{ width: 70 }} type="number" min={1} value={row.seats.length} onChange={(e) => setRowSeatCount(active.key, ri, numOr(e.target.value, 1)!)} /></td>
                        <td><input style={{ width: 70 }} type="number" min={0} value={gapAfterOf(row)} disabled={gapIndexes(row).length > 1} title={gapIndexes(row).length > 1 ? L.smMultiGapHint : undefined} onChange={(e) => setRowGap(active.key, ri, numOr(e.target.value, 0)!)} />
                          {gapIndexes(row).length > 1 && <div className="muted" style={{ fontSize: 12 }}>{L.smMultiGapHint}</div>}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <button type="button" className="danger" style={{ marginTop: 8 }} onClick={() => removeSection(active.key)}>{L.smRemoveSection}</button>
          </div>
        )}
      </div>

      <div className="seat-editor-main">
        <div className="card">
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <strong data-testid="seat-total">{L.smSeatTotal}: {seatCount.toLocaleString('en')}</strong>
            {dirty && <span className="badge PENDING">{L.smUnsaved}</span>}
          </div>
          {problems.length > 0 && (
            <div className="error" data-testid="problems">
              <strong>{L.smProblems}</strong>
              <ul style={{ margin: 0, paddingLeft: 18 }}>{problems.map((p) => <li key={p}>{p}</li>)}</ul>
            </div>
          )}
          {result?.error && <div className="error">{result.error}</div>}
          {result?.problems?.length ? (
            <div className="error"><ul style={{ margin: 0, paddingLeft: 18 }}>{result.problems.map((p) => <li key={p}>{p}</li>)}</ul></div>
          ) : null}
          {result?.ok && <div className="ok">{okText[result.ok] ?? result.ok}</div>}
          <div className="row" style={{ margin: '8px 0' }}>
            <button type="button" onClick={save} disabled={pending || problems.length > 0}>{L.smSaveDraft}</button>
            {onPublish && <button type="button" className="secondary" onClick={publish} disabled={pending || problems.length > 0}>{L.smPublish}</button>}
          </div>
          <div className="row" style={{ margin: '8px 0' }}>
            <span className="muted">{selected.size > 0 ? `${L.smSelectedSeats}: ${selected.size}` : L.smHintClick}</span>
            <button type="button" className="secondary" disabled={!selected.size} onClick={removeSelected}>{L.smRemoveSelected}</button>
            <button type="button" className="secondary" disabled={!selected.size} onClick={() => mark('RESTRICTED_VIEW')}>{L.smMarkRestricted}</button>
            <button type="button" className="secondary" disabled={!selected.size} onClick={() => mark('WHEELCHAIR')}>{L.smMarkWheelchair}</button>
            <button type="button" className="secondary" disabled={!selected.size} onClick={clearMarks}>{L.smClearMarks}</button>
            <button type="button" className="secondary" disabled={!selected.size} onClick={() => setSelected(new Set())}>{L.smClearSelection}</button>
          </div>
          <div className="row muted" style={{ fontSize: 13 }}>
            <span style={{ color: '#d97706' }}>● {L.smRestricted}</span>
            <span style={{ color: '#1d6fd8' }}>● {L.smWheelchair}</span>
          </div>
          {lastValid.current && (
            <SeatMapView layout={lastValid.current} selected={selected} onToggle={toggleSeat} onSectionClick={setActiveKey} showRowLabels lang={lang} ariaLabel={L.smSeatMap} stageLabel={L.smStage} />
          )}
        </div>

        <div className="card">
          <div className="field">
            <label>{L.smJsonBox}</label>
            <textarea data-testid="layout-json" rows={8} value={json} onChange={(e) => setJson(e.target.value)} style={{ fontFamily: 'ui-monospace, monospace', width: '100%' }} />
          </div>
          <div className="row">
            <button type="button" className="secondary" onClick={doExport}>{L.smExportJson}</button>
            <button type="button" className="secondary" onClick={doImport} disabled={pending || !json.trim()}>{L.smImportJson}</button>
          </div>
        </div>
      </div>
    </div>
  );
}
