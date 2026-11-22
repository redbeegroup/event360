import Link from 'next/link';
import { ActionForm } from '../../../components/ActionForm';
import { PageHeader } from '../../../components/PageHeader';
import { RecordPayout } from '../../../components/PayoutAdmin';
import { api } from '../../../lib/api';
import { fmtDate, fmtMmk, t, toLocalInput } from '../../../lib/i18n';
import { payoutLabels } from '../../../lib/payoutLabels';
import { adminInviteMemberAction, recordPayoutAction, setKycAction } from '../../actions';

interface OrgDetail {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  kycStatus: string;
  kycNote: string | null;
  verifiedAt: string | null;
  contactEmail: string | null;
  contactPhone: string | null;
  members: { role: string; user: { id: string; email: string | null; displayName: string | null; phone: string | null } }[];
  invitations: { id: string; email: string; orgRole: string; expiresAt: string }[];
  _count: { events: number };
}

export default async function OrgDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const tr = await t();
  const [o, summary] = await Promise.all([api<OrgDetail>(`/admin/organizations/${id}`), api<{ owedMmk: number }>(`/admin/finance/organizations/${id}/summary`).catch(() => null)]);
  return (
    <>
      <PageHeader
        breadcrumb={<Link href="/admin/organizations">← {tr.organizations}</Link>}
        title={o.name}
        badge={<span className={`badge ${o.kycStatus}`}>{tr.kycStatus[o.kycStatus]}</span>}
        subtitle={`${o.contactEmail ?? ''} · ${o.contactPhone ?? '—'} · ${o._count.events} ${tr.events}`}
      />
      <div className="card">
        {o.description && <p>{o.description}</p>}
        <p className="muted">{o.kycStatus === 'APPROVED' ? tr.verifiedNote : tr.unverifiedNote}</p>
        {o.kycNote && <p className="muted">{tr.note}: {o.kycNote}</p>}
        <div className="row">
          <ActionForm action={setKycAction} submitLabel={tr.verify}>
            <input type="hidden" name="id" value={o.id} />
            <input type="hidden" name="status" value="APPROVED" />
          </ActionForm>
          <ActionForm action={setKycAction} submitLabel={tr.unverify} variant="danger" className="row">
            <input type="hidden" name="id" value={o.id} />
            <input type="hidden" name="status" value="REJECTED" />
            <input name="note" placeholder={tr.note} style={{ width: 220 }} />
          </ActionForm>
        </div>
      </div>

      {summary && (
        <>
          <h2>{tr.pyTitle}</h2>
          <div className="card">
            <div className="card-head">
              <strong>{o.name}</strong>
              <span>{tr.owed}: <strong>{fmtMmk(summary.owedMmk, tr.lang)}</strong></span>
            </div>
            <RecordPayout orgId={o.id} orgName={o.name} owedMmk={summary.owedMmk} defaultPaidAt={toLocalInput(new Date())} action={recordPayoutAction} labels={payoutLabels(tr)} errorText={{ alreadyVoided: tr.pyAlreadyVoided }} />
          </div>
        </>
      )}

      <h2>{tr.members}</h2>
      <div className="table-card">
        <table>
          <tbody>
            {o.members.map((m) => (
              <tr key={m.user.id}>
                <td>{m.user.displayName ?? '—'}</td>
                <td>{m.user.email ?? m.user.phone}</td>
                <td>{tr.roles[m.role] ?? m.role}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {o.invitations.length > 0 && (
        <>
          <h2>{tr.pendingInvites}</h2>
          <div className="card">
            <ul className="fine-list">
              {o.invitations.map((i) => (
                <li key={i.id}>{i.email} — {tr.roles[i.orgRole]} ({fmtDate(i.expiresAt, tr.lang)})</li>
              ))}
            </ul>
          </div>
        </>
      )}

      <h2>{tr.inviteMember}</h2>
      <div className="card">
        <ActionForm
          action={adminInviteMemberAction}
          submitLabel={tr.inviteMember}
          variant="gold"
          inviteLabels={{ text: tr.inviteLink, copy: tr.copy }}
        >
          <input type="hidden" name="orgId" value={o.id} />
          <div className="grid">
            <div className="field"><label>{tr.email}</label><input name="email" type="email" required /></div>
            <div className="field">
              <label>{tr.role}</label>
              <select name="role" defaultValue="ORG_MANAGER">
                {['ORG_OWNER', 'ORG_MANAGER', 'ORG_FINANCE'].map((r) => <option key={r} value={r}>{tr.roles[r]}</option>)}
              </select>
            </div>
          </div>
        </ActionForm>
      </div>
    </>
  );
}
