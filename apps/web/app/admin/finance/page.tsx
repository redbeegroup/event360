import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { api } from '../../lib/api';
import { fmtDate, fmtMmk, t } from '../../lib/i18n';
import { completeRefundAction, refundOrderAction, retryRefundAction, saveFeeAction } from '../actions';

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
  owedMmk: number;
}

const STATUSES = ['PENDING_PAYMENT', 'PAID', 'REFUNDED', 'EXPIRED', 'CANCELLED'];
const badge = (s: string) => (s === 'PAID' || s === 'SUCCEEDED' ? 'PUBLISHED' : s === 'PENDING_PAYMENT' || s === 'PENDING' || s === 'MANUAL' ? 'SUBMITTED' : s === 'REFUNDED' ? 'DRAFT' : 'REJECTED');

export default async function FinancePage({ searchParams }: { searchParams: Promise<{ q?: string; status?: string }> }) {
  const sp = await searchParams;
  const qs = new URLSearchParams({ ...(sp.q ? { q: sp.q } : {}), ...(sp.status ? { status: sp.status } : {}), limit: '50' });
  const [tr, fee, review, orders, balances] = await Promise.all([
    t(),
    api<Fee>('/admin/finance/fee'),
    api<OrderRow[]>('/admin/finance/orders?review=1'),
    api<OrderRow[]>(`/admin/finance/orders?${qs}`),
    api<Balance[]>('/admin/finance/balances'),
  ]);
  const okText = { saved: tr.saved, refunded: tr.refundStarted };
  const openRefunds = orders.concat(review).flatMap((o) => o.refunds.filter((r) => r.status === 'MANUAL' || r.status === 'FAILED').map((r) => ({ ...r, order: o })));
  const seen = new Set<string>();

  const orderRow = (o: OrderRow) => (
    <tr key={o.id}>
      <td>
        <code>{o.id.slice(0, 8)}</code>
        <div className="muted" style={{ fontSize: 12 }}>{fmtDate(o.createdAt, tr.lang)}</div>
      </td>
      <td>{o.event}<div className="muted" style={{ fontSize: 12 }}>{o.organization}</div></td>
      <td>{o.buyer.name ?? ''}<div className="muted" style={{ fontSize: 12 }}>{o.buyer.phone}</div></td>
      <td>{fmtMmk(o.totalMmk, tr.lang)}<div className="muted" style={{ fontSize: 12 }}>{tr.commission}: {fmtMmk(o.commissionMmk, tr.lang)}</div></td>
      <td>
        <span className={`badge ${badge(o.status)}`}>{o.status}</span> <span className="muted">{o.tickets}🎟</span>
        {o.reviewNote && <div className="error-text" style={{ fontSize: 12 }}>{o.reviewNote}</div>}
        <div className="muted" style={{ fontSize: 12 }}>{o.payments.map((p) => `${p.provider} ${p.status.toLowerCase()}`).join(' · ')}</div>
        {o.refunds.map((r) => (
          <div key={r.id} style={{ fontSize: 12 }}>
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
    <table>
      <thead><tr><th>{tr.orders}</th><th>{tr.event}</th><th>{tr.buyer}</th><th>{tr.total}</th><th>{tr.status}</th><th /></tr></thead>
      <tbody>{rows.map(orderRow)}</tbody>
    </table>
  );

  return (
    <>
      <h1>{tr.finance}</h1>

      <h2>{tr.reviewQueue} ({review.length})</h2>
      <div className="card table-wrap">{review.length ? table(review) : <p className="muted">{tr.reviewEmpty}</p>}</div>

      {openRefunds.length > 0 && (
        <>
          <h2>{tr.refunds}</h2>
          <div className="card table-wrap">
            <p className="muted">{tr.refundManualHint}</p>
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
      <div className="card table-wrap">
        <form className="row" method="get" style={{ marginBottom: 12, gap: 8 }}>
          <input name="q" defaultValue={sp.q ?? ''} placeholder={tr.searchHint} style={{ flex: 1, minWidth: 200 }} />
          <select name="status" defaultValue={sp.status ?? ''}>
            <option value="">{tr.allStatuses}</option>
            {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          <button type="submit" className="secondary">{tr.search}</button>
        </form>
        {orders.length ? table(orders) : <p className="muted">{tr.nothingYet}</p>}
      </div>

      <h2>{tr.balances}</h2>
      <div className="card table-wrap">
        <p className="muted">{tr.balancesHint}</p>
        {balances.length === 0 ? (
          <p className="muted">{tr.nothingYet}</p>
        ) : (
          <>
            <table>
              <thead><tr><th>{tr.organization}</th><th>{tr.paidOrders}</th><th>{tr.gross}</th><th>{tr.refunded}</th><th>{tr.commission}</th><th>{tr.owed}</th></tr></thead>
              <tbody>
                {balances.map((b) => (
                  <tr key={b.organizationId}>
                    <td><Link href={`/admin/organizations/${b.organizationId}`}>{b.organization}</Link></td>
                    <td>{b.orders}</td>
                    <td>{fmtMmk(b.grossMmk, tr.lang)}</td>
                    <td>{fmtMmk(b.refundedMmk, tr.lang)}</td>
                    <td>{fmtMmk(b.commissionMmk, tr.lang)}</td>
                    <td><strong>{fmtMmk(b.owedMmk, tr.lang)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p><a className="btn secondary" href="/admin/finance/balances.csv">{tr.downloadCsv}</a></p>
          </>
        )}
      </div>

      <h2>{tr.feeTitle}</h2>
      <div className="card">
        <p className="muted">{tr.feeHint}</p>
        <ActionForm action={saveFeeAction} submitLabel={tr.save} okText={okText}>
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
