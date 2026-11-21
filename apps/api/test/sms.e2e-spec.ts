/**
 * SMS settings + production OTP delivery through SMSPoh v3 (HTTP stubbed), against a real PostgreSQL.
 * Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';
import { SmsService } from '../src/modules/notifications/sms.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(60_000);

run('SMS via SMSPoh', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  const tag = randomBytes(4).toString('hex');
  const realFetch = global.fetch;
  const calls: { url: string; init: RequestInit }[] = [];
  let fail = false;

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'false'; // production behaviour
    process.env.SETTINGS_KEY = randomBytes(32).toString('base64');
    jest.spyOn(global, 'fetch').mockImplementation(async (input: any, init?: any) => {
      const url = String(input);
      if (!url.startsWith('https://v3.smspoh.com/')) return realFetch(input, init);
      calls.push({ url, init });
      if (fail) return new Response(JSON.stringify({ name: 'Unauthorized', message: 'Your request was made with invalid credentials.', status: 401 }), { status: 401 });
      if (url.endsWith('/account/get-balance')) return new Response(JSON.stringify({ balance: 120000, currency: 'MMK' }), { status: 201 });
      const body = JSON.parse(init.body);
      return new Response(
        JSON.stringify({ messages: [{ messageId: `MSG-${calls.length}`, to: body.to, status: 'Accepted', network: 'MPT', messageCount: 1, test: !!body.test }] }),
        { status: 201 },
      );
    });
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    // Start from "not configured"
    await app.get(PrismaService).platformSetting.deleteMany({ where: { key: 'sms' } });
  });

  afterAll(async () => {
    jest.restoreAllMocks();
    process.env.OTP_DEV_ECHO = 'true';
    await app?.close();
  });

  it('admin configures SMSPoh; login codes go out by SMS', async () => {
    const phone = () => `09${randomInt(700_000_000, 799_999_999)}`;

    // Not configured yet → login is unavailable (and the attempt is not counted)
    const p1 = phone();
    const r0 = await http.post('/v1/auth/otp/request').send({ phone: p1 }).expect(503);
    expect(r0.body.message).toMatch(/not available/);

    const inv = await app.get(AuthService).createInvitation({ email: `sms-admin-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const acc = await http.post(`/v1/auth/invitations/${inv.url.split('/invite/')[1]}/accept`).send({ password: 'admin-password-123' }).expect(200);
    const A = { Authorization: `Bearer ${acc.body.accessToken}` };

    // Consumers can't see or change settings
    const cons = await http.get('/v1/admin/settings/sms').expect(401);
    expect(cons.status).toBe(401);

    // Save credentials; the secret is never returned
    const saved = await http
      .put('/v1/admin/settings/sms')
      .set(A)
      .send({ apiKey: 'KEY-abcdef123456', apiSecret: 'SECRET-zyxwvu987654', senderId: 'Event360', enabled: false, testMode: true })
      .expect(200);
    expect(JSON.stringify(saved.body)).not.toContain('SECRET-zyxwvu987654');
    expect(saved.body).toMatchObject({ apiSecretSet: true, apiSecretHint: '••••7654', senderId: 'Event360', testMode: true, enabled: false });
    const row = await app.get(PrismaService).platformSetting.findUnique({ where: { key: 'sms' } });
    expect(JSON.stringify(row!.value)).not.toContain('SECRET-zyxwvu987654');

    // View shows the provider balance
    const view = await http.get('/v1/admin/settings/sms').set(A).expect(200);
    expect(view.body.balance).toEqual({ balance: 120000, currency: 'MMK' });

    // "Waitlist SMS" is on by default and can be switched off on its own
    expect(saved.body.waitlistSms).toBe(true);
    const wlOff = await http.put('/v1/admin/settings/sms').set(A).send({ waitlistSms: false }).expect(200);
    expect(wlOff.body).toMatchObject({ waitlistSms: false, senderId: 'Event360', apiSecretSet: true });
    expect((await app.get(SmsService).settingsConfig())!.waitlistSms).toBe(false);
    await http.put('/v1/admin/settings/sms').set(A).send({ waitlistSms: 'yes' }).expect(400);
    await http.put('/v1/admin/settings/sms').set(A).send({ waitlistSms: true }).expect(200);
    expect((await app.get(SmsService).settingsConfig())!.waitlistSms).toBe(true);

    // Test SMS: correct auth header and payload
    calls.length = 0;
    const t = await http.post('/v1/admin/settings/sms/test').set(A).send({ phone: '09791234567' }).expect(200);
    expect(t.body).toMatchObject({ ok: true, messageId: 'MSG-1', network: 'MPT' });
    expect(calls[0].url).toBe('https://v3.smspoh.com/api/rest/send');
    expect((calls[0].init.headers as Record<string, string>).authorization).toBe(
      `Bearer ${Buffer.from('KEY-abcdef123456:SECRET-zyxwvu987654').toString('base64')}`,
    );
    expect(JSON.parse(calls[0].init.body as string)).toMatchObject({ to: '959791234567', from: 'Event360', test: true });

    // Saved but disabled → login still unavailable
    await http.post('/v1/auth/otp/request').send({ phone: phone() }).expect(503);

    // Enable (keeping the secret) with a custom template → the code goes out, no devCode in the response
    await http.put('/v1/admin/settings/sms').set(A).send({ enabled: true, testMode: false, otpTemplate: 'Event360 code {code} ({minutes} min)' }).expect(200);
    calls.length = 0;
    const p2 = phone();
    const r = await http.post('/v1/auth/otp/request').send({ phone: p2 }).expect(200);
    expect(r.body).toEqual({ expiresInSeconds: 300 });
    const sent = JSON.parse(calls[0].init.body as string);
    expect(sent.message).toMatch(/^Event360 code \d{6} \(5 min\)$/);
    expect(sent.test).toBeUndefined();
    const code = sent.message.match(/\d{6}/)[0];
    await http.post('/v1/auth/otp/verify').send({ phone: p2, code }).expect(200);

    // Provider failure → 503, and the user can retry immediately (cooldown not used up)
    fail = true;
    const p3 = phone();
    await http.post('/v1/auth/otp/request').send({ phone: p3 }).expect(503);
    fail = false;
    await http.post('/v1/auth/otp/request').send({ phone: p3 }).expect(200);

    // Bad test request shows the provider's message
    fail = true;
    const bad = await http.post('/v1/admin/settings/sms/test').set(A).send({ phone: '09791234567' }).expect(400);
    expect(bad.body.message).toMatch(/invalid credentials/);
    fail = false;

    // Log: masked numbers, no message text
    const log = await http.get('/v1/admin/sms-log').set(A).expect(200);
    expect(log.body.length).toBeGreaterThanOrEqual(4);
    expect(log.body.some((l: any) => l.status === 'failed')).toBe(true);
    expect(JSON.stringify(log.body)).not.toMatch(/9791234567|code \d{6}/);
    expect(log.body[0].to).toMatch(/^959•••••\d{4}$/);
  });
});
