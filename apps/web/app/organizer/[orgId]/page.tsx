import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { PageHeader } from '../../components/PageHeader';
import { api, getMe } from '../../lib/api';
import { fmtDate, pick, t } from '../../lib/i18n';
import type { EventDto } from '../../lib/types';
import { inviteTeamAction } from '../actions';

export const dynamic = 'force-dynamic';

interface Org {
  id: string;
  name: string;
  kycStatus: string;
  members: { role: string; user: { id: string; email: string | null; displayName: string | null } }[];
}

export default async function OrgEventsPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const [tr, me, org, events] = await Promise.all([
    t(),
    getMe(),
    api<Org>(`/organizations/${orgId}`),
    api<EventDto[]>(`/organizations/${orgId}/events`),
  ]);
  const myRole = me.organizations.find((o) => o.id === orgId)?.role;
  const canEdit = myRole === 'ORG_OWNER' || myRole === 'ORG_MANAGER' || me.platformRoles.includes('PLATFORM_ADMIN');
  return (
    <>
      <PageHeader
        title={org.name}
        badge={<span className={`badge ${org.kycStatus}`}>{tr.kycStatus[org.kycStatus]}</span>}
        subtitle={org.kycStatus === 'APPROVED' ? tr.verifiedNote : tr.unverifiedNote}
        actions={canEdit && <Link className="btn btn-gold" href={`/organizer/${orgId}/events/new`}>{tr.newEvent}</Link>}
      />

      <h2>{tr.events}</h2>
      {events.length === 0 ? (
        <div className="card"><p className="muted">{tr.noEvents}</p></div>
      ) : (
        <div className="table-card">
          <table>
            <thead>
              <tr><th>{tr.title}</th><th>{tr.startsAt}</th><th>{tr.status}</th><th>{tr.sold}</th></tr>
            </thead>
            <tbody>
              {events.map((e) => (
                <tr key={e.id}>
                  <td><Link href={`/organizer/${orgId}/events/${e.id}`}>{pick(tr.lang, e.title, e.titleMy)}</Link></td>
                  <td>{fmtDate(e.startsAt, tr.lang)}</td>
                  <td><span className={`badge ${e.status}`}>{tr.statuses[e.status]}</span></td>
                  <td>{e.ticketTypes.reduce((n, x) => n + (x.sold ?? 0), 0)} / {e.ticketTypes.reduce((n, x) => n + x.quota, 0)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h2>{tr.team}</h2>
      <div className="card">
        <ul className="fine-list">
          {org.members.map((m) => (
            <li key={m.user.id}>{m.user.displayName ?? m.user.email} — {tr.roles[m.role]}</li>
          ))}
        </ul>
        {myRole === 'ORG_OWNER' && (
          <ActionForm action={inviteTeamAction} submitLabel={tr.inviteMember} inviteLabels={{ text: tr.inviteLink, copy: tr.copy }} className="invite-form">
            <input type="hidden" name="orgId" value={orgId} />
            <div className="grid">
              <div className="field"><label>{tr.email}</label><input name="email" type="email" required /></div>
              <div className="field">
                <label>{tr.role}</label>
                <select name="role" defaultValue="ORG_MANAGER">
                  {['ORG_MANAGER', 'CREW', 'ORG_FINANCE', 'ORG_OWNER'].map((r) => <option key={r} value={r}>{tr.roles[r]}</option>)}
                </select>
              </div>
            </div>
          </ActionForm>
        )}
      </div>
    </>
  );
}
