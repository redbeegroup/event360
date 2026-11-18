import 'server-only';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

export const API_URL = process.env.API_URL ?? 'http://localhost:3000';
export const ACCESS_COOKIE = 'e360_at';
export const REFRESH_COOKIE = 'e360_rt';

export class ApiError extends Error {
  constructor(
    public status: number,
    public body: { message?: string | string[]; problems?: string[] } | null,
  ) {
    super(Array.isArray(body?.message) ? body!.message.join(', ') : (body?.message ?? `HTTP ${status}`));
  }
  get problems(): string[] {
    return this.body?.problems ?? [];
  }
}

/** Server-side call to the Event 360 API with the signed-in user's token. Redirects to /login on 401. */
export async function api<T = unknown>(path: string, init: RequestInit & { json?: unknown; auth?: boolean } = {}): Promise<T> {
  const { json, auth = true, headers, ...rest } = init;
  const h = new Headers(headers);
  if (json !== undefined) h.set('content-type', 'application/json');
  if (auth) {
    const token = (await cookies()).get(ACCESS_COOKIE)?.value;
    if (!token) redirect('/login');
    h.set('authorization', `Bearer ${token}`);
  }
  const res = await fetch(`${API_URL}/v1${path}`, {
    ...rest,
    headers: h,
    body: json !== undefined ? JSON.stringify(json) : rest.body,
    cache: 'no-store',
  });
  if (res.status === 401 && auth) redirect('/login');
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(res.status, body);
  return body as T;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export async function setSession(t: TokenPair) {
  const jar = await cookies();
  const secure = process.env.NODE_ENV === 'production';
  jar.set(ACCESS_COOKIE, t.accessToken, { httpOnly: true, secure, sameSite: 'lax', path: '/', maxAge: 60 * 60 * 24 * 30 });
  jar.set(REFRESH_COOKIE, t.refreshToken, { httpOnly: true, secure, sameSite: 'lax', path: '/', maxAge: 60 * 60 * 24 * 30 });
}

export async function clearSession() {
  const jar = await cookies();
  jar.delete(ACCESS_COOKIE);
  jar.delete(REFRESH_COOKIE);
}

export interface Me {
  id: string;
  displayName: string | null;
  email: string | null;
  platformRoles: string[];
  organizations: { id: string; name: string; slug: string; kycStatus: string; role: string }[];
}

export const getMe = () => api<Me>('/auth/me');
export const isAdmin = (me: Me) => me.platformRoles.includes('PLATFORM_ADMIN');
