import Link from 'next/link';
import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { getMe, isAdmin } from '../lib/api';
import { t } from '../lib/i18n';

export const dynamic = 'force-dynamic';

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const me = await getMe();
  if (!isAdmin(me)) redirect('/organizer');
  const tr = await t();
  return (
    <>
      <nav className="row" style={{ marginBottom: 20 }}>
        <Link href="/admin/organizations" className="btn secondary">{tr.organizations}</Link>
        <Link href="/admin/events" className="btn secondary">{tr.moderation}</Link>
        <Link href="/admin/finance" className="btn secondary">{tr.finance}</Link>
        <Link href="/admin/venues" className="btn secondary">{tr.smVenues}</Link>
        <Link href="/admin/ops" className="btn secondary">{tr.operations}</Link>
        <Link href="/admin/settings" className="btn secondary">{tr.settings}</Link>
      </nav>
      {children}
    </>
  );
}
