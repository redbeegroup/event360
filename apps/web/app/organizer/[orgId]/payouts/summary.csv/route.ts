import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { ACCESS_COOKIE, API_URL } from '../../../../lib/api';

export const dynamic = 'force-dynamic';

/** Streams the payouts CSV from the API with the signed-in organizer's token. Failures send the user back to the page. */
export async function GET(_: Request, { params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) redirect('/login');
  let res: Response;
  try {
    res = await fetch(`${API_URL}/v1/organizations/${encodeURIComponent(orgId)}/payouts/summary.csv`, {
      headers: { authorization: `Bearer ${token}` },
      cache: 'no-store',
    });
  } catch {
    redirect(`/organizer/${orgId}/payouts?csvError=1`);
  }
  if (res.status === 401) redirect('/login');
  if (!res.ok) redirect(`/organizer/${orgId}/payouts?csvError=1`);
  return new Response(await res.arrayBuffer(), {
    headers: { 'content-type': 'text/csv; charset=utf-8', 'content-disposition': res.headers.get('content-disposition') ?? 'attachment; filename="event360-payouts.csv"' },
  });
}
