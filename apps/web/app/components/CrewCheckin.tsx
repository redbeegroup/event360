'use client';

import QRCode from 'qrcode';
import { useActionState, useEffect, useState } from 'react';
import { useFormStatus } from 'react-dom';
import type { FormState } from '../actions';
import type { AttendanceStats } from '../organizer/actions';

export interface CrewLabels {
  label: string;
  labelHint: string;
  gate: string;
  create: string;
  codeTitle: string;
  codeHint: string;
  openCrewApp: string;
  copy: string;
  expires: string;
  registered: string;
  checkedIn: string;
  byGate: string;
  noGate: string;
  recent: string;
  noScans: string;
  duplicate: string;
  undone: string;
  manual: string;
  offline: string;
  updated: string;
}

function Submit({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending} aria-busy={pending}>{pending ? '…' : label}</button>;
}

/** Creates a volunteer event code and shows it once, with a QR the Crew app can scan. */
export function CrewCodeForm({
  action,
  hidden,
  labels,
  crewAppUrl,
  lang,
}: {
  action: (state: FormState, fd: FormData) => Promise<FormState>;
  hidden: Record<string, string>;
  labels: CrewLabels;
  crewAppUrl: string;
  lang: string;
}) {
  const [state, formAction] = useActionState(action, {} as FormState);
  const [qr, setQr] = useState<string>('');
  const code = typeof state.data?.code === 'string' ? state.data.code : null;
  const link = code && crewAppUrl ? `${crewAppUrl}#/redeem?code=${encodeURIComponent(code)}` : null;
  useEffect(() => {
    if (!code) return;
    // The QR carries the web link (opens the crew web app) — the Crew app scanner also understands it.
    QRCode.toDataURL(link ?? `event360crew://redeem?code=${code}`, { margin: 1, width: 240 }).then(setQr, () => setQr(''));
  }, [code, link]);

  return (
    <form action={formAction}>
      {state.error && <div className="error">{state.error}</div>}
      {code && (
        <div className="ok crew-code">
          <p style={{ margin: '0 0 6px' }}><strong>{labels.codeTitle}</strong> — {String(state.data?.label ?? '')}{state.data?.gate ? ` · ${String(state.data.gate)}` : ''}</p>
          <div className="crew-code-row">
            {qr && <img src={qr} alt={code} width={180} height={180} />}
            <div>
              <div className="code big-code">{code}</div>
              <p className="muted" style={{ margin: '6px 0' }}>{labels.codeHint}</p>
              <p className="muted" style={{ margin: '6px 0' }}>
                {labels.expires}: {new Date(String(state.data?.expiresAt)).toLocaleString(lang === 'my' ? 'my-MM' : 'en-GB', { timeZone: 'Asia/Yangon' })}
              </p>
              <button type="button" className="secondary" onClick={() => navigator.clipboard?.writeText(code)}>{labels.copy}</button>{' '}
              {link && <a className="button secondary" href={link} target="_blank" rel="noreferrer">{labels.openCrewApp}</a>}
            </div>
          </div>
        </div>
      )}
      {Object.entries(hidden).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
      <div className="grid">
        <div className="field">
          <label>{labels.label}</label>
          <input name="label" required maxLength={80} placeholder={labels.labelHint} />
        </div>
        <div className="field">
          <label>{labels.gate}</label>
          <input name="gate" maxLength={60} placeholder="Main gate" />
        </div>
      </div>
      <Submit label={labels.create} />
    </form>
  );
}

/** Attendance numbers that refresh every 15 seconds while the page is open. */
export function AttendanceLive({
  initial,
  load,
  labels,
  lang,
}: {
  initial: AttendanceStats | null;
  load: () => Promise<AttendanceStats | null>;
  labels: CrewLabels;
  lang: string;
}) {
  const [s, setS] = useState(initial);
  const [at, setAt] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(async () => {
      if (document.hidden) return;
      const next = await load();
      if (next) {
        setS(next);
        setAt(new Date());
      }
    }, 15_000);
    return () => clearInterval(id);
  }, [load]);
  if (!s) return null;
  const pct = s.registered ? Math.round((s.checkedIn / s.registered) * 100) : 0;
  const name = (n: { name: string; nameMy: string | null }) => (lang === 'my' && n.nameMy ? n.nameMy : n.name);
  const time = (d: string | Date) => new Date(d).toLocaleTimeString(lang === 'my' ? 'my-MM' : 'en-GB', { timeZone: 'Asia/Yangon', hour: '2-digit', minute: '2-digit' });
  return (
    <div>
      <div className="stat-row">
        <div className="stat"><div className="stat-num">{s.checkedIn}</div><div className="muted">{labels.checkedIn}</div></div>
        <div className="stat"><div className="stat-num">{s.registered}</div><div className="muted">{labels.registered}</div></div>
        <div className="stat"><div className="stat-num">{pct}%</div><div className="muted">&nbsp;</div></div>
      </div>
      <div className="progress" aria-label={`${pct}%`}><div style={{ width: `${pct}%` }} /></div>
      <div className="grid" style={{ marginTop: 12 }}>
        <table>
          <tbody>
            {s.byTicketType.map((t) => (
              <tr key={t.id}><td>{name(t)}</td><td style={{ textAlign: 'right' }}>{t.checkedIn} / {t.registered}</td></tr>
            ))}
          </tbody>
        </table>
        <table>
          <thead><tr><th>{labels.byGate}</th><th /></tr></thead>
          <tbody>
            {s.byGate.length === 0 && <tr><td className="muted" colSpan={2}>{labels.noScans}</td></tr>}
            {s.byGate.map((g) => (
              <tr key={g.gate ?? '-'}><td>{g.gate ?? labels.noGate}</td><td style={{ textAlign: 'right' }}>{g.checkedIn}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
      <h3>{labels.recent}</h3>
      {s.recent.length === 0 ? (
        <p className="muted">{labels.noScans}</p>
      ) : (
        <div className="table-wrap">
          <table>
            <tbody>
              {s.recent.map((r) => (
                <tr key={r.id} className={r.undone ? 'muted' : undefined}>
                  <td>{time(r.at)}</td>
                  <td>{r.ticket.holderName} <span className="muted">#{r.ticket.code}</span></td>
                  <td>{name(r.ticket.ticketType)}</td>
                  <td>{r.gate ?? '—'}</td>
                  <td>{r.by ?? '—'}</td>
                  <td>
                    {r.duplicate && <span className="badge REJECTED">{labels.duplicate}</span>}{' '}
                    {r.undone && <span className="badge CANCELLED">{labels.undone}</span>}{' '}
                    {r.method === 'MANUAL' && <span className="badge DRAFT">{labels.manual}</span>}{' '}
                    {r.offline && <span className="badge SUBMITTED">{labels.offline}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="muted" style={{ fontSize: 12 }}>{labels.updated} {time(at)}</p>
    </div>
  );
}
