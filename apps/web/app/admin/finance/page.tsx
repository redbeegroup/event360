import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { PageHeader } from '../../components/PageHeader';
import { StatTile } from '../../components/StatTile';
import { RecordPayout, VoidPayout, type PayoutLabels } from '../../components/PayoutAdmin';
import { api } from '../../lib/api';
import { fmtDate, fmtMmk, t, toLocalInput } from '../../lib/i18n';
import { completeRefundAction, recordPayoutAction, refundOrderAction, retryRefundAction, saveFeeAction, voidPayoutAction } from '../actions';

export const dynamic = 'force-dynamic';

interface Fee {
  percentBp: number;
  fixedMmk: number;
  minMmk: number | null;
  maxMmk: number | null;
  isActive: boolean;
}
interface RefundRow {
  id: string;
  status: string;
  amountMmk: number;
  reference: string | null;
  error: string | null;
  createdAt: string;
}
interface OrderRow {
  id: string;
  status: string;
  needsReview: boolean;
  reviewNote: string | null;
  totalMmk: number;
  commissionMmk: number;
  createdAt: string;
  paidAt: string | null;
  buyer: { phone: string | null; name: string | null };
  event: string;
  organization: string;
  tickets: number;
  payments: { id: string; provider: string; status: string; providerRef: string | null }[];
  refunds: RefundRow[];
}
interface Balance {
  organizationId: string;
  organization: string;
  orders: number;
  grossMmk: number;
  refundedMmk: number;
  commissionMmk: number;
  paidOutMmk: number;
  owedMmk: number;
}
interface PayoutRow {
  id: string;
  amountMmk: number;
  paidAt: string;
  method: string;
  reference: string | null;
  note: string | null;
  voidedAt: string | null;
  voidReason: string | null;
}

const STATUSES = ['PENDING_PAYMENT', 'PAID', 'REFUNDED', 'EXPIRED', 'CANCELLED'];
const badge = (s: string) => (s === 'PAID' || s === 'SUCCEEDED' ? 'PUBLISHED' : s === 'PENDING_PAYMENT' || s === 'PENDING' || s === 'MANUAL' ? 'SUBMITTED' : s === 'REFUNDED' ? 'DRAFT' : 'REJECTED');

export default async function FinancePage({ searchParams }: { searchParams: Promise<{ q?: string; status?: string; csvError?: string }> }) {
  const sp = await searchParams;
  const qs = new URLSearchParams({ ...(sp.q ? { q: sp.q } : {}), ...(sp.status ? { status: sp.status } : {}), limit: '50' });
  const [tr, fee, review, orders, balances] = await Promise.all([
    t(),
    api<Fee>('/admin/finance/fee'),
    api<OrderRow[]>('/admin/finance/orders?review=1'),
    api<OrderRow[]>(`/admin/finance/orders?${qs}`),
    api<Balance[]>('/admin/finance/balances'),
  ]);
  const payoutLists = await Promise.allSettled(balances.map((b) => api<PayoutRow[]>(`/admin/finance/organizations/${b.organizationId}/payouts`)));
  const payoutsOf = new Map(balances.map((b, i) => [b.organizationId, (payoutLists[i] as PromiseFulfilledResult<PayoutRow[]>).status === 'fulfilled' ? (payoutLists[i] as PromiseFulfilledResult<PayoutRow[]>).value : []]));
  const methods = Object.fromEntries(['BANK', 'KBZPAY', 'WAVEPAY', 'CASH', 'OTHER'].map((m) => [m, String((tr as Record<string, unknown>)[`pyMethod${m}`])]));
  const pl: PayoutLabels = {
    record: tr.pyRecord, amount: tr.pyAmount, paidAt: tr.pyDate, method: tr.pyMethod, reference: tr.pyReference, note: tr.note,
    review: tr.pyReview, confirmLine: tr.pyConfirmLine, confirm: tr.pyConfirm, back: tr.pyBack, overWarn: tr.pyOverWarn,
    recorded: tr.pyRecorded, newOwed: tr.pyNewOwed, newOwing: tr.pyNewOwing, voidBtn: tr.pyVoidBtn, voidReasonPh: tr.pyVoidReasonPh,
    voidConfirm: tr.pyVoidConfirm, voidDone: tr.pyVoidDone, alreadyVoided: tr.pyAlreadyVoided, methods,
    currency: tr.lang === 'my' ? 'ကျပ်' : 'MMK', locale: tr.lang === 'my' ? 'my-MM' : 'en-US',
  };
  const payoutErrors = { alreadyVoided: tr.pyAlreadyVoided };
  const nowLocal = toLocalInput(new Date());
  const okText = { saved: tr.saved, refunded: tr.refundStarted };
  const openRefunds = orders.concat(review).flatMap((o) => o.refunds.filter((r) => r.status === 'MANUAL' || r.status === 'FAILED').map((r) => ({ ...r, order: o })));
  const seen = new Set<string>();

  const orderRow = (o: OrderRow) => (
    <tr key={o.id}>
      <td>
        <code>{o.id.slice(0, 8)}</code>
        <div className="muted small">{fmtDate(o.createdAt, tr.lang)}</div>
      </td>
      <td>{o.event}<div className="muted small">{o.organization}</div></td>
      <td>{o.buyer.name ?? ''}<div className="muted small">{o.buyer.phone}</div></td>
      <td>{fmtMmk(o.totalMmk, tr.lang)}<div className="muted small">{tr.commission}: {fmtMmk(o.commissionMmk, tr.lang)}</div></td>
      <td>
        <span className={`badge ${badge(o.status)}`}>{o.status}</span> <span className="muted">{o.tickets}🎟</span>
        {o.reviewNote && <div className="error-text small">{o.reviewNote}</div>}
        <div className="muted small">{o.payments.map((p) => `${p.provider} ${p.status.toLowerCase()}`).join(' · ')}</div>
        {o.refunds.map((r) => (
          <div key={r.id} className="small">
            {tr.refund}: <span className={`badge ${badge(r.status)}`}>{r.status}</span> {r.reference ?? r.error ?? ''}
          </div>
        ))}
      </td>
      <td style={{ minWidth: 220 }}>
        {o.status === 'PAID' && (
          <ActionForm action={refundOrderAction} submitLabel={tr.refund} variant="danger" confirm={tr.refundConfirm} okText={okText}>
            <input type="hidden" name="id" value={o.id} />
            <input name="reason" placeholder={tr.refundReason} required minLength={3} maxLength={500} />
          </ActionForm>
        )}
      </td>
    </tr>
  );
  const table = (rows: OrderRow[]) => (
    <div className="table-card"><table>
      <thead><tr><th>{tr.orders}</th><th>{tr.event}</th><th>{tr.buyer}</th><th>{tr.total}</th><th>{tr.status}</th><th /></tr></thead>
      <tbody>{rows.map(orderRow)}</tbody>
    </table></div>
  );

  return (
    <>
      <PageHeader title={tr.finance} />
      {sp.csvError && <div className="error">{tr.pyCsvError}</div>}

      <div className="stat-grid">
        <StatTile label={tr.reviewQueue} value={review.length} />
        <StatTile label={tr.refunds} value={new Set(openRefunds.map((r) => r.id)).size} />
        <StatTile label={tr.owed} value={fmtMmk(balances.reduce((n, b) => n + b.owedMmk, 0), tr.lang)} />
      </div>

      <h2>{tr.reviewQueue} ({review.length})</h2>
      {review.length ? table(review) : <div className="card"><p className="muted">{tr.reviewEmpty}</p></div>}

      {openRefunds.length > 0 && (
        <>
          <h2>{tr.refunds}</h2>
          <p className="muted">{tr.refundManualHint}</p>
          <div className="table-card">
            <table>
              <thead><tr><th>{tr.orders}</th><th>{tr.buyer}</th><th>{tr.total}</th><th>{tr.status}</th><th /></tr></thead>
              <tbody>
                {openRefunds.filter((r) => !seen.has(r.id) && seen.add(r.id)).map((r) => (
                  <tr key={r.id}>
                    <td><code>{r.order.id.slice(0, 8)}</code> {r.order.event}</td>
                    <td>{r.order.buyer.phone}</td>
                    <td>{fmtMmk(r.amountMmk, tr.lang)}</td>
                    <td><span className={`badge ${badge(r.status)}`}>{r.status}</span> <span className="muted">{r.error ?? ''}</span></td>
                    <td style={{ minWidth: 260 }}>
                      <ActionForm action={completeRefundAction} submitLabel={tr.markRefunded} okText={okText}>
                        <input type="hidden" name="id" value={r.id} />
                        <input name="reference" placeholder={tr.refundReference} required minLength={2} maxLength={200} />
                      </ActionForm>
                      {r.status === 'FAILED' && (
                        <ActionForm action={retryRefundAction} submitLabel={tr.retry} variant="secondary" okText={okText}>
                          <input type="hidden" name="id" value={r.id} />
                        </ActionForm>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <h2>{tr.orders}</h2>
      <div className="card">
        <form className="row" method="get">
          <input name="q" defaultValue={sp.q ?? ''} placeholder={tr.searchHint} style={{ flex: 1, minWidth: 200 }} />
          <select name="status" defaultValue={sp.status ?? ''}>
            <option value="">{tr.allStatuses}</option>
            {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          <button type="submit" className="secondary">{tr.search}</button>
        </form>
      </div>
      {orders.length ? table(orders) : <div className="card"><p className="muted">{tr.nothingYet}</p></div>}

      <h2>{tr.balances}</h2>
      <p className="muted">{tr.balancesHint}</p>
      {balances.length === 0 ? (
        <div className="card"><p className="muted">{tr.nothingYet}</p></div>
      ) : (
        <>
          <div className="table-card">
            <table>
              <thead><tr><th>{tr.organization}</th><th>{tr.paidOrders}</th><th>{tr.gross}</th><th>{tr.refunded}</th><th>{tr.commission}</th><th>{tr.pyPaidOutCol}</th><th>{tr.owed}</th></tr></thead>
              <tbody>
                {balances.map((b) => (
                  <tr key={b.organizationId}>
                    <td><Link href={`/admin/organizations/${b.organizationId}`}>{b.organization}</Link></td>
                    <td>{b.orders}</td>
                    <td>{fmtMmk(b.grossMmk, tr.lang)}</td>
                    <td>{fmtMmk(b.refundedMmk, tr.lang)}</td>
                    <td>{fmtMmk(b.commissionMmk, tr.lang)}</td>
                    <td>{fmtMmk(b.paidOutMmk, tr.lang)}</td>
                    <td><strong>{fmtMmk(b.owedMmk, tr.lang)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p><a className="btn btn-outline" href="/admin/finance/balances.csv">{tr.downloadCsv}</a></p>
          <h2>{tr.pyPayoutsFor}</h2>
          {balances.map((b) => (
            <div key={b.organizationId} data-testid={`payouts-${b.organizationId}`}>
              <div className="card">
                <div className="card-head">
                  <strong>{b.organization}</strong>
                  <span>{tr.owed}: <strong>{fmtMmk(b.owedMmk, tr.lang)}</strong></span>
                </div>
                <RecordPayout orgId={b.organizationId} orgName={b.organization} owedMmk={b.owedMmk} defaultPaidAt={nowLocal} action={recordPayoutAction} labels={pl} errorText={payoutErrors} />
                {(payoutsOf.get(b.organizationId) ?? []).length === 0 && <p className="muted">{tr.pyNone}</p>}
              </div>
              {(payoutsOf.get(b.organizationId) ?? []).length > 0 && (
                <div className="table-card">
                  <table>
                    <thead><tr><th>{tr.pyDate}</th><th>{tr.pyAmount}</th><th>{tr.pyMethod}</th><th>{tr.pyReference}</th><th /></tr></thead>
                    <tbody>
                      {payoutsOf.get(b.organizationId)!.map((p) => {
                        const strike = p.voidedAt ? 'struck' : undefined;
                        return (
                          <tr key={p.id}>
                            <td className={strike}>{fmtDate(p.paidAt, tr.lang)}</td>
                            <td className={strike}>{fmtMmk(p.amountMmk, tr.lang)}</td>
                            <td className={strike}>{methods[p.method] ?? p.method}</td>
                            <td><span className={strike}>{p.reference ?? ''}</span>{p.note && <div className="muted small">{p.note}</div>}</td>
                            <td style={{ minWidth: 220 }}>
                              {p.voidedAt ? (
                                <span className="error-text small"><span className="badge REJECTED">{tr.pyVoided}</span> {p.voidReason}</span>
                              ) : (
                                <VoidPayout id={p.id} action={voidPayoutAction} labels={pl} errorText={payoutErrors} />
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          ))}
        </>
      )}

      <h2>{tr.feeTitle}</h2>
      <div className="card">
        <p className="muted">{tr.feeHint}</p>
        <ActionForm action={saveFeeAction} submitLabel={tr.save} variant="gold" okText={okText}>
          <div className="grid">
            <div className="field"><label>{tr.feePercent} (%)</label><input name="percent" type="number" min={0} max={50} step={0.01} defaultValue={fee.percentBp / 100} required /></div>
            <div className="field"><label>{tr.feeFixed}</label><input name="fixedMmk" type="number" min={0} step={1} defaultValue={fee.fixedMmk} /></div>
            <div className="field"><label>{tr.feeMin}</label><input name="minMmk" type="number" min={0} step={1} defaultValue={fee.minMmk ?? ''} /></div>
            <div className="field"><label>{tr.feeMax}</label><input name="maxMmk" type="number" min={0} step={1} defaultValue={fee.maxMmk ?? ''} /></div>
          </div>
          <label className="check"><input type="checkbox" name="isActive" defaultChecked={fee.isActive} /> {tr.feeActive}</label>
        </ActionForm>
      </div>
    </>
  );
}
