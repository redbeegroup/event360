import { NextRequest, NextResponse } from 'next/server';

const ACCESS = 'e360_at';
const REFRESH = 'e360_rt';
const API_URL = process.env.API_URL ?? 'http://localhost:3000';

function expiresSoon(jwt: string | undefined): boolean {
  if (!jwt) return true;
  try {
    const payload = JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return payload.exp * 1000 - Date.now() < 60_000;
  } catch {
    return true;
  }
}

/** Refreshes the access token (rotating refresh token) before pages render. */
export async function middleware(req: NextRequest) {
  const access = req.cookies.get(ACCESS)?.value;
  const refresh = req.cookies.get(REFRESH)?.value;
  if (!refresh || !expiresSoon(access)) return NextResponse.next();

  const r = await fetch(`${API_URL}/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ refreshToken: refresh }),
  }).catch(() => null);

  if (!r?.ok) {
    const res = NextResponse.redirect(new URL('/login', req.url));
    res.cookies.delete(ACCESS);
    res.cookies.delete(REFRESH);
    return res;
  }
  const t = (await r.json()) as { accessToken: string; refreshToken: string };
  // Make the new token visible to this request's server components, and store it for the browser.
  req.cookies.set(ACCESS, t.accessToken);
  req.cookies.set(REFRESH, t.refreshToken);
  const res = NextResponse.next({ request: { headers: req.headers } });
  const opts = { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax' as const, path: '/', maxAge: 60 * 60 * 24 * 30 };
  res.cookies.set(ACCESS, t.accessToken, opts);
  res.cookies.set(REFRESH, t.refreshToken, opts);
  return res;
}

export const config = { matcher: ['/admin/:path*', '/organizer/:path*'] };
