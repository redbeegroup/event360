import { createVerify, generateKeyPairSync } from 'crypto';
import { FcmClient, serviceAccountJwt } from './fcm';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
const cfg = { projectId: 'event360-test', clientEmail: 'push@event360-test.iam.gserviceaccount.com', privateKey, enabled: true };

describe('FCM', () => {
  it('signs a valid RS256 service-account JWT with the messaging scope', () => {
    const jwt = serviceAccountJwt(cfg, 1_700_000_000);
    const [h, c, sig] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'RS256', typ: 'JWT' });
    expect(JSON.parse(Buffer.from(c, 'base64url').toString())).toEqual({
      iss: cfg.clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: 1_700_000_000,
      exp: 1_700_003_600,
    });
    expect(createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, Buffer.from(sig, 'base64url'))).toBe(true);
  });

  it('gets one access token, sends v1 messages, and reports stale tokens', async () => {
    const calls: { url: string; body: string; auth?: string }[] = [];
    const http = async (url: string, init: any) => {
      calls.push({ url, body: init.body, auth: init.headers.authorization });
      if (url.includes('oauth2')) return { status: 200, text: async () => JSON.stringify({ access_token: 'at-1', expires_in: 3600 }) };
      const token = JSON.parse(init.body).message.token;
      if (token === 'gone') return { status: 404, text: async () => '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}' };
      return { status: 200, text: async () => '{"name":"projects/x/messages/1"}' };
    };
    const fcm = new FcmClient(http);
    const msg = { title: 'Hi', body: 'There', data: { kind: 'test', link: '/tickets' } };
    expect(await fcm.send(cfg, 'tok-1', msg)).toBe('ok');
    expect(await fcm.send(cfg, 'gone', msg)).toBe('invalid_token');
    expect(calls.filter((c) => c.url.includes('oauth2'))).toHaveLength(1);
    const send = calls.find((c) => c.url.includes('fcm.googleapis.com'))!;
    expect(send.url).toBe('https://fcm.googleapis.com/v1/projects/event360-test/messages:send');
    expect(send.auth).toBe('Bearer at-1');
    expect(JSON.parse(send.body).message).toMatchObject({ token: 'tok-1', notification: { title: 'Hi', body: 'There' }, data: { kind: 'test', link: '/tickets' } });
    expect(new URLSearchParams(calls[0].body).get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
  });
});
