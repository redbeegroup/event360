import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { Shell } from '../components/Shell';
import { getMe, isAdmin } from '../lib/api';
import { t } from '../lib/i18n';

export const dynamic = 'force-dynamic';

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const me = await getMe();
  if (!isAdmin(me)) redirect('/organizer');
  const tr = await t();
  const items = [
    { href: '/admin/organizations', label: tr.organizations },
    { href: '/admin/events', label: tr.events },
    { href: '/admin/venues', label: tr.smVenues },
    { href: '/admin/finance', label: tr.finance },
    { href: '/admin/ops', label: tr.operations },
    { href: '/admin/settings', label: tr.settings },
  ];
  return <Shell items={items} label={tr.admin}>{children}</Shell>;
}
