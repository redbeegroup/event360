import type { ReactNode } from 'react';
import { Shell } from '../../components/Shell';
import { getMe } from '../../lib/api';
import { t } from '../../lib/i18n';

export const dynamic = 'force-dynamic';

export default async function OrgLayout({ children, params }: { children: ReactNode; params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const [tr, me] = await Promise.all([t(), getMe()]);
  const role = me.organizations.find((o) => o.id === orgId)?.role;
  const canSeePayouts = role === 'ORG_OWNER' || role === 'ORG_FINANCE'; // same check as the payouts page
  const canEdit = role === 'ORG_OWNER' || role === 'ORG_MANAGER' || me.platformRoles.includes('PLATFORM_ADMIN'); // same check as the events page's profile link
  const base = `/organizer/${orgId}`;
  const items = [
    { href: base, label: tr.events, exact: true, also: [`${base}/events`] },
    ...(canSeePayouts ? [{ href: `${base}/payouts`, label: tr.pyNav }] : []),
    ...(canEdit ? [{ href: `${base}/profile`, label: tr.menuOrgProfile }] : []),
  ];
  // The print sheet (seats/print) is a bare page: no shell around it.
  return <Shell items={items} label={tr.organizer} bare="/seats/print">{children}</Shell>;
}
