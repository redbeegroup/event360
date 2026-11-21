import Link from 'next/link';
import { redirect } from 'next/navigation';
import { PageHeader } from '../../../components/PageHeader';
import { StatTile } from '../../../components/StatTile';
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
      <PageHeader
        breadcrumb={<Link href={`/organizer/${orgId}`}>← {tr.back}</Link>}
        title={tr.pyTitle}
        subtitle={tr.pyIntro}
        actions={<a className="btn btn-outline" href={`/organizer/${orgId}/payouts/summary.csv`}>{tr.downloadCsv}</a>}
      />

      {sp.csvError && <div className="error" data-testid="csv-error">{tr.pyCsvError}</div>}

      <div className="stat-grid">
        <StatTile label={tr.pyEarned} value={money(s.earnedMmk)} testId="earned" />
        <StatTile label={tr.pyPaidOut} value={money(s.paidOutMmk)} testId="paid-out" />
        <StatTile
          label={owing ? '' : tr.pyOwed}
          value={owing ? tr.pyYouOwe.replace('{amount}', money(-s.owedMmk)) : money(s.owedMmk)}
          testId="owed"
          tone={owing ? 'danger' : undefined}
        />
      </div>

      <h2>{tr.pyPerEvent}</h2>
      <div className="table-card">
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
      <div className="table-card">
        {s.payouts.length === 0 ? (
          <p className="muted">{tr.pyNone}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.pyDate}</th><th>{tr.pyAmount}</th><th>{tr.pyMethod}</th><th>{tr.pyReference}</th><th>{tr.note}</th></tr></thead>
            <tbody>
              {s.payouts.map((p) => (
                <tr key={p.id}>
                  <td className={p.voidedAt ? 'struck' : undefined}>{fmtDate(p.paidAt, tr.lang)}</td>
                  <td className={p.voidedAt ? 'struck' : undefined}>{money(p.amountMmk)}</td>
                  <td className={p.voidedAt ? 'struck' : undefined}>{String((tr as Record<string, unknown>)[`pyMethod${p.method}`] ?? p.method)}</td>
                  <td className={p.voidedAt ? 'struck' : undefined}>{p.reference ?? ''}</td>
                  <td>
                    <span className={p.voidedAt ? 'struck' : undefined}>{p.note ?? ''}</span>
                    {p.voidedAt && (
                      <div className="error-text small">
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
