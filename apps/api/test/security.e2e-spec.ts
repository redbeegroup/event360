/**
 * Security regressions from the hardening review: invite takeover, private bucket keys, OTP attempt
 * races, logout, and the global rate limit. Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { createHash, randomBytes, randomInt, randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { isPrivateIp } from '../src/common/throttle.guard';
import { AuthService } from '../src/modules/auth/auth.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

describe('isPrivateIp', () => {
  it('recognises cluster and LAN addresses only', () => {
    for (const ip of ['10.244.1.5', '127.0.0.1', '::1', '::ffff:10.0.0.1', '172.16.16.180', '172.31.0.1', '192.168.1.2', 'fd00::1']) expect(isPrivateIp(ip)).toBe(true);
    for (const ip of ['122.248.126.20', '172.32.0.1', '8.8.8.8', '2001:db8::1', '', undefined]) expect(isPrivateIp(ip)).toBe(false);
  });
});

run('Security', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const token = (url: string) => url.split('/invite/')[1];

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.S3_PREFIX = 'dev';
    process.env.THROTTLE_INTERNAL = 'true'; // local test calls are limited like visitors
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
  });
  afterAll(async () => {
    delete process.env.THROTTLE_INTERNAL;
    await app?.close();
  });

  it('an org owner cannot take over an existing account (e.g. a platform admin) with an invite', async () => {
    const auth = app.get(AuthService);
    const adminEmail = `adm-s-${tag}@e2e.test`;
    const adm = await auth.createInvitation({ email: adminEmail, platformRole: 'PLATFORM_ADMIN' });
    const A = bearer((await http.post(`/v1/auth/invitations/${token(adm.url)}/accept`).send({ password: 'admin-password-1' }).expect(200)).body.accessToken);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Sec Org ${tag}`, slug: `sec-${tag}`, ownerEmail: `own-s-${tag}@e2e.test` }).expect(201);
    const O = bearer((await http.post(`/v1/auth/invitations/${token(org.body.inviteUrl)}/accept`).send({ password: 'owner-password-1' }).expect(200)).body.accessToken);

    // The owner invites the admin's email into their org and tries to set a password on it
    const inv = await http.post(`/v1/organizations/${org.body.organization.id}/invitations`).set(O).send({ email: adminEmail, role: 'ORG_MANAGER' }).expect(201);
    expect((await http.get(`/v1/auth/invitations/${token(inv.body.inviteUrl)}`).expect(200)).body.existingAccount).toBe(true);
    const r = await http.post(`/v1/auth/invitations/${token(inv.body.inviteUrl)}/accept`).send({ password: 'attacker-chosen-1' }).expect(400);
    expect(r.body.message).toMatch(/current password/);
    await http.post('/v1/auth/password/login').send({ email: adminEmail, password: 'attacker-chosen-1' }).expect(401);
    await http.post('/v1/auth/password/login').send({ email: adminEmail, password: 'admin-password-1' }).expect(200);

    // The real owner of the account can join with their own password
    await http.post(`/v1/auth/invitations/${token(inv.body.inviteUrl)}/accept`).send({ password: 'admin-password-1' }).expect(200);
    const u = await prisma.user.findUniqueOrThrow({ where: { email: adminEmail }, include: { memberships: true } });
    expect(u.memberships.map((m) => m.role)).toEqual(['ORG_MANAGER']);
    expect(u.platformRoles).toContain('PLATFORM_ADMIN');
  });

  it('only uploaded images are served from the bucket', async () => {
    await http.get('/v1/media/dev/backups/daily/2026-11-20.dump').expect(404);
    await http.get('/v1/media/dev/vod/00000000-0000-0000-0000-000000000000/v0/index.m3u8').expect(404);
    await http.get('/v1/media/dev/uploads/x/source.mp4').expect(404);
    await http.get('/v1/media/prod/images/2026/11/a.jpg').expect(404);
    const ok = await http.get('/v1/media/dev/images/2026/11/a.jpg').expect(302);
    expect(ok.headers.location).toContain('dev/images/2026/11/a.jpg');
  });

  it('parallel wrong guesses cannot exceed 5 attempts per code', async () => {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const code = r.body.devCode as string;
    const wrong = code === '000000' ? '111111' : '000000';
    await Promise.all(Array.from({ length: 12 }, () => http.post('/v1/auth/otp/verify').send({ phone, code: wrong })));
    const c = await prisma.otpChallenge.findFirstOrThrow({ where: { phone: `+959${phone.slice(2)}` }, orderBy: { createdAt: 'desc' } });
    expect(c.attempts).toBe(5);
    await http.post('/v1/auth/otp/verify').send({ phone, code }).expect(401);
  });

  it('a code can be used once even when sent twice at the same time', async () => {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const results = await Promise.all([0, 1, 2].map(() => http.post('/v1/auth/otp/verify').send({ phone, code: r.body.devCode })));
    expect(results.filter((x) => x.status === 200)).toHaveLength(1);
  });

  it('logout revokes the refresh token', async () => {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const t = (await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200)).body;
    await http.post('/v1/auth/logout').send({ refreshToken: t.refreshToken }).expect(204);
    await http.post('/v1/auth/refresh').send({ refreshToken: t.refreshToken }).expect(401);
    const row = await prisma.refreshToken.findUnique({ where: { tokenHash: createHash('sha256').update(t.refreshToken).digest('hex') } });
    expect(row?.revokedAt).toBeTruthy();
  });

  it('every route is rate limited, with tighter limits on promo-code checks', async () => {
    const id = randomUUID();
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) codes.push((await http.post(`/v1/events/${id}/promo-check`).send({ code: 'VIP100' })).status);
    expect(codes.slice(0, 10).every((s) => s !== 429)).toBe(true);
    expect(codes[10]).toBe(429);
  });
});
