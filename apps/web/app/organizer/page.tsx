import Link from 'next/link';
import { redirect } from 'next/navigation';
import { PageHeader } from '../components/PageHeader';
import { getMe } from '../lib/api';
import { t } from '../lib/i18n';

export const dynamic = 'force-dynamic';

export default async function OrganizerHome() {
  const [me, tr] = await Promise.all([getMe(), t()]);
  if (me.organizations.length === 1) redirect(`/organizer/${me.organizations[0].id}`);
  return (
    <>
      <PageHeader title={tr.chooseOrg} />
      {me.organizations.length === 0 && <p className="muted">{tr.noOrgs}</p>}
      {me.organizations.map((o) => (
        <div className="card" key={o.id}>
          <Link href={`/organizer/${o.id}`}><strong>{o.name}</strong></Link>{' '}
          <span className="muted">{tr.roles[o.role]}</span>{' '}
          <span className={`badge ${o.kycStatus}`}>{tr.kycStatus[o.kycStatus]}</span>
        </div>
      ))}
    </>
  );
}
