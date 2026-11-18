import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { ACCESS_COOKIE, getMe, isAdmin } from './lib/api';

export const dynamic = 'force-dynamic';

export default async function Home() {
  if (!(await cookies()).get(ACCESS_COOKIE)) redirect('/login');
  const me = await getMe();
  redirect(isAdmin(me) ? '/admin' : '/organizer');
}
