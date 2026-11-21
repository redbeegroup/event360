import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { PageHeader } from '../../components/PageHeader';
import { api } from '../../lib/api';
import { t } from '../../lib/i18n';
import { createOrgAction } from '../actions';

interface Org {
  id: string;
  name: string;
  slug: string;
  kycStatus: string;
  contactEmail: string | null;
  _count: { events: number; members: number };
}

export default async function OrganizationsPage() {
  const tr = await t();
  const orgs = await api<Org[]>('/admin/organizations');
  return (
    <>
      <PageHeader title={tr.organizations} />
      <div className="table-card">
        <table>
          <thead>
            <tr><th>{tr.name}</th><th>{tr.kyc}</th><th>{tr.events}</th><th>{tr.members}</th></tr>
          </thead>
          <tbody>
            {orgs.map((o) => (
              <tr key={o.id}>
                <td><Link href={`/admin/organizations/${o.id}`}>{o.name}</Link><div className="muted">{o.contactEmail}</div></td>
                <td><span className={`badge ${o.kycStatus}`}>{tr.kycStatus[o.kycStatus]}</span></td>
                <td>{o._count.events}</td>
                <td>{o._count.members}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>{tr.newOrganization}</h2>
      <div className="card">
        <ActionForm
          action={createOrgAction}
          submitLabel={tr.create}
          variant="gold"
          inviteLabels={{ text: tr.inviteLink, copy: tr.copy }}
        >
          <div className="grid">
            <div className="field"><label>{tr.name}</label><input name="name" required minLength={2} /></div>
            <div className="field"><label>{tr.slug}</label><input name="slug" required pattern="[a-z0-9]+(-[a-z0-9]+)*" placeholder="yangon-live-events" /></div>
            <div className="field"><label>{tr.ownerEmail}</label><input name="ownerEmail" type="email" required /></div>
            <div className="field"><label>{tr.contactPhone}</label><input name="contactPhone" /></div>
          </div>
          <div className="field"><label>{tr.description}</label><textarea name="description" /></div>
        </ActionForm>
      </div>
    </>
  );
}
