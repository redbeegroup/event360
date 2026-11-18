'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { api, ApiError, clearSession, getMe, isAdmin, setSession, TokenPair } from './lib/api';
import { LANG_COOKIE } from './lib/i18n';

export interface FormState {
  error?: string;
  problems?: string[];
  ok?: string;
  data?: Record<string, unknown>;
}

export async function setLangAction(fd: FormData) {
  (await cookies()).set(LANG_COOKIE, fd.get('lang') === 'en' ? 'en' : 'my', { path: '/', maxAge: 60 * 60 * 24 * 365 });
}

export async function logoutAction() {
  await clearSession();
  redirect('/login');
}

async function landing() {
  const me = await getMe();
  redirect(isAdmin(me) ? '/admin' : '/organizer');
}

export async function loginAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const tokens = await api<TokenPair>('/auth/password/login', {
      method: 'POST',
      auth: false,
      json: { email: String(fd.get('email') ?? ''), password: String(fd.get('password') ?? '') },
    });
    await setSession(tokens);
  } catch (e) {
    return { error: e instanceof ApiError && e.status === 401 ? 'invalid' : (e as Error).message };
  }
  await landing();
  return {};
}

export async function acceptInviteAction(_: FormState, fd: FormData): Promise<FormState> {
  const token = String(fd.get('token') ?? '');
  try {
    const tokens = await api<TokenPair>(`/auth/invitations/${encodeURIComponent(token)}/accept`, {
      method: 'POST',
      auth: false,
      json: { password: String(fd.get('password') ?? ''), displayName: String(fd.get('displayName') ?? '') || undefined },
    });
    await setSession(tokens);
  } catch (e) {
    return { error: (e as Error).message };
  }
  await landing();
  return {};
}
