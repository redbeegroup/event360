import { createSign } from 'crypto';
import type { PushConfig } from './settings.service';

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string; signal?: AbortSignal }) => Promise<{ status: number; text(): Promise<string> }>;

const b64url = (b: Buffer | string) => Buffer.from(b).toString('base64url');

/** Service-account JWT (RS256) exchanged for an OAuth access token with the firebase.messaging scope. */
export function serviceAccountJwt(cfg: Pick<PushConfig, 'clientEmail' | 'privateKey'>, nowSec = Math.floor(Date.now() / 1000)) {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: cfg.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: nowSec,
      exp: nowSec + 3600,
    }),
  );
  const sig = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(cfg.privateKey);
  return `${header}.${claims}.${b64url(sig)}`;
}

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

export type SendResult = 'ok' | 'invalid_token' | 'error';

/** Firebase Cloud Messaging HTTP v1 client (one request per device token). */
export class FcmClient {
  private token: { value: string; exp: number; key: string } | null = null;

  constructor(private readonly http: FetchLike = (u, i) => fetch(u, i)) {}

  private async accessToken(cfg: PushConfig) {
    const key = `${cfg.projectId}:${cfg.clientEmail}`;
    if (this.token && this.token.key === key && this.token.exp > Date.now() + 60_000) return this.token.value;
    const res = await this.http('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: serviceAccountJwt(cfg) }).toString(),
      signal: AbortSignal.timeout(10_000),
    });
    const j = JSON.parse((await res.text()) || '{}') as { access_token?: string; expires_in?: number; error_description?: string; error?: string };
    if (res.status !== 200 || !j.access_token) throw new Error(`Firebase auth failed: ${j.error_description ?? j.error ?? res.status}`);
    this.token = { value: j.access_token, exp: Date.now() + (j.expires_in ?? 3600) * 1000, key };
    return j.access_token;
  }

  async send(cfg: PushConfig, token: string, m: PushMessage): Promise<SendResult> {
    const at = await this.accessToken(cfg);
    const res = await this.http(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(cfg.projectId)}/messages:send`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${at}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: m.title, body: m.body },
          data: m.data,
          android: { priority: 'high', notification: { channel_id: 'event360' } },
        },
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (res.status === 200) return 'ok';
    const text = await res.text();
    // Token no longer valid (app uninstalled / token rotated): caller removes the device
    if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/.test(text)) return 'invalid_token';
    if (res.status === 400 && /INVALID_ARGUMENT/.test(text) && /token/i.test(text)) return 'invalid_token';
    if (res.status === 401) this.token = null;
    return 'error';
  }
}
