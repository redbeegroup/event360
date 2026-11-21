import { cookies } from 'next/headers';
import { ACCESS_COOKIE, API_URL } from '../../../../../lib/api';

export const dynamic = 'force-dynamic';

/** Streams the guest-ticket PDF (all valid comps, or `?ids=a,b`) from the API with the signed-in organizer's token. */
export async function GET(req: Request, { params }: { params: Promise<{ orgId: string; id: string }> }) {
  const { orgId, id } = await params;
  const token = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!token) return new Response('Unauthorized', { status: 401 });
  const ids = new URL(req.url).searchParams.get('ids');
  const qs = ids ? `?ids=${encodeURIComponent(ids)}` : '';
  const res = await fetch(`${API_URL}/v1/organizations/${encodeURIComponent(orgId)}/events/${encodeURIComponent(id)}/seating/comps.pdf${qs}`, {
    headers: { authorization: `Bearer ${token}` },
    cache: 'no-store',
  });
  if (!res.ok) return new Response(`Error ${res.status}`, { status: res.status });
  return new Response(await res.arrayBuffer(), {
    headers: {
      'content-type': 'application/pdf',
      'content-disposition': res.headers.get('content-disposition') ?? 'inline; filename="guest-tickets.pdf"',
      'cache-control': 'no-store',
    },
  });
}
