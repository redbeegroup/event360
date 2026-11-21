import Link from 'next/link';
import { redirect } from 'next/navigation';
import { api, getMe } from '../../../lib/api';
import { fmtDate, fmtMmk, t } from '../../../lib/i18n';

export const dynamic = 'force-dynamic';

interface Summary {
  earnedMmk: number;
  paidOutMmk: number;
  owedMmk: number;
  eventsNetMmk: number;
  reconciled: boolean;
  events: { eventId: string; title: string; grossMmk: number; discountMmk: number; commissionMmk: number; refundsMmk: number; netMmk: number }[];
  payouts: { id: string; amountMmk: number; paidAt: string; method: string; reference: string | null; note: string | null; voidedAt: string | null; voidReason: string | null }[];
}

export default async function PayoutsPage({ params, searchParams }: { params: Promise<{ orgId: string }>; searchParams: Promise<{ csvError?: string }> }) {
  const { orgId } = await params;
  const sp = await searchParams;
  const [tr, me] = await Promise.all([t(), getMe()]);
  const role = me.organizations.find((o) => o.id === orgId)?.role;
  if (role !== 'ORG_OWNER' && role !== 'ORG_FINANCE') redirect(`/organizer/${orgId}`);
  const s = await api<Summary>(`/organizations/${orgId}/payouts/summary`);
  const money = (n: number) => fmtMmk(n, tr.lang);
  const owing = s.owedMmk < 0;
  return (
    <>
      <p><Link href={`/organizer/${orgId}`}>← {tr.back}</Link></p>
      <h1>{tr.pyTitle}</h1>
      <p className="muted">{tr.pyIntro}</p>

      {sp.csvError && <div className="error" data-testid="csv-error">{tr.pyCsvError}</div>}

      <div className="grid">
        <div className="card"><div className="muted">{tr.pyEarned}</div><h2 style={{ margin: '4px 0' }} data-testid="earned">{money(s.earnedMmk)}</h2></div>
        <div className="card"><div className="muted">{tr.pyPaidOut}</div><h2 style={{ margin: '4px 0' }} data-testid="paid-out">{money(s.paidOutMmk)}</h2></div>
        <div className="card">
          {!owing && <div className="muted">{tr.pyOwed}</div>}
          <h2 style={{ margin: '4px 0' }} data-testid="owed" className={owing ? 'error-text' : undefined}>
            {owing ? tr.pyYouOwe.replace('{amount}', money(-s.owedMmk)) : money(s.owedMmk)}
          </h2>
        </div>
      </div>

      <div className="row" style={{ justifyContent: 'space-between' }}>
        <h2>{tr.pyPerEvent}</h2>
        <a className="btn secondary" href={`/organizer/${orgId}/payouts/summary.csv`}>{tr.downloadCsv}</a>
      </div>
      <div className="card table-wrap">
        {s.events.length === 0 ? (
          <p className="muted">{tr.nothingYet}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.event}</th><th>{tr.gross}</th><th>{tr.pyDiscount}</th><th>{tr.commission}</th><th>{tr.refunded}</th><th>{tr.net}</th></tr></thead>
            <tbody>
              {s.events.map((e) => (
                <tr key={e.eventId}>
                  <td>{e.title}</td>
                  <td>{money(e.grossMmk)}</td>
                  <td>{money(e.discountMmk)}</td>
                  <td>{money(e.commissionMmk)}</td>
                  <td>{money(e.refundsMmk)}</td>
                  <td><strong>{money(e.netMmk)}</strong></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {!s.reconciled && <p className="muted" data-testid="recon-note">{tr.pyReconNote}</p>}
      </div>

      <h2>{tr.pyHistory}</h2>
      <div className="card table-wrap">
        {s.payouts.length === 0 ? (
          <p className="muted">{tr.pyNone}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.pyDate}</th><th>{tr.pyAmount}</th><th>{tr.pyMethod}</th><th>{tr.pyReference}</th><th>{tr.note}</th></tr></thead>
            <tbody>
              {s.payouts.map((p) => (
                <tr key={p.id}>
                  <td style={p.voidedAt ? { textDecoration: 'line-through' } : undefined}>{fmtDate(p.paidAt, tr.lang)}</td>
                  <td style={p.voidedAt ? { textDecoration: 'line-through' } : undefined}>{money(p.amountMmk)}</td>
                  <td style={p.voidedAt ? { textDecoration: 'line-through' } : undefined}>{String((tr as Record<string, unknown>)[`pyMethod${p.method}`] ?? p.method)}</td>
                  <td style={p.voidedAt ? { textDecoration: 'line-through' } : undefined}>{p.reference ?? ''}</td>
                  <td>
                    <span style={p.voidedAt ? { textDecoration: 'line-through' } : undefined}>{p.note ?? ''}</span>
                    {p.voidedAt && (
                      <div className="error-text" style={{ fontSize: 12 }}>
                        <span className="badge REJECTED">{tr.pyVoided}</span> {fmtDate(p.voidedAt, tr.lang)} · {tr.pyVoidedReason}: {p.voidReason}
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
