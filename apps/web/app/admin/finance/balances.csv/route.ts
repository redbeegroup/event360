import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { ACCESS_COOKIE, API_URL } from '../../../lib/api';

export const dynamic = 'force-dynamic';

/** Streams the admin balances CSV from the API with the signed-in admin's token. Failures send the user back to the page. */
export async function GET() {
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) redirect('/login');
  let res: Response;
  try {
    res = await fetch(`${API_URL}/v1/admin/finance/balances.csv`, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  } catch {
    redirect('/admin/finance?csvError=1');
  }
  if (res.status === 401) redirect('/login');
  if (!res.ok) redirect('/admin/finance?csvError=1');
  return new Response(await res.text(), {
    headers: { 'content-type': 'text/csv; charset=utf-8', 'content-disposition': 'attachment; filename="event360-balances.csv"' },
  });
}
