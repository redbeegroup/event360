import { cookies } from 'next/headers';
import { ACCESS_COOKIE, API_URL } from '../../../lib/api';

export const dynamic = 'force-dynamic';

/** Streams the admin balances CSV from the API with the signed-in admin's token. */
export async function GET() {
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) return new Response('Unauthorized', { status: 401 });
  const res = await fetch(`${API_URL}/v1/admin/finance/balances.csv`, { headers: { authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!res.ok) return new Response(`Error ${res.status}`, { status: res.status });
  return new Response(await res.text(), {
    headers: { 'content-type': 'text/csv; charset=utf-8', 'content-disposition': 'attachment; filename="event360-balances.csv"' },
  });
}
