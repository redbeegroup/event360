/**
 * Operations: error capture (API 5xx + app reports), health monitor alerting/recovery, email settings.
 * SMTP is faked. Skipped when DATABASE_URL is not set.
 */
import { Controller, Get, INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { EmailService } from '../src/modules/ops/email.service';
import { ErrorsService } from '../src/modules/ops/errors.service';
import { FAIL_THRESHOLD, MonitorService } from '../src/modules/ops/monitor.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

const marker = randomBytes(4).toString('hex');

@Controller('boom-test')
class BoomController {
  @Get()
  boom() {
    throw new Error(`Kaboom ${marker} for order 3339531d-5c29-4452-8096-64e3f4ab0ea1`);
  }
}

run('Operations', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const mails: { to: string; subject: string; text: string }[] = [];
  let A: Record<string, string>;
  const tag = randomBytes(4).toString('hex');

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    const mod = await Test.createTestingModule({ imports: [AppModule], controllers: [BoomController] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    app.get(EmailService).transport = () => ({ sendMail: async (m: any) => void mails.push(m) }) as any;
    const adm = await app.get(AuthService).createInvitation({ email: `adm-ops-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const r = await http.post(`/v1/auth/invitations/${adm.url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'Ops' }).expect(200);
    A = { Authorization: `Bearer ${r.body.accessToken}` };
  });
  afterAll(async () => {
    await prisma.platformSetting.deleteMany({ where: { key: 'email' } });
    await app?.close();
  });

  it('email settings: password sealed, test send, enabling needs recipients', async () => {
    await http.put('/v1/admin/settings/email').set(A).send({ host: 'smtp.example.com', enabled: true }).expect(503);
    const v = await http
      .put('/v1/admin/settings/email')
      .set(A)
      .send({ host: 'smtp.example.com', port: 587, user: 'alerts', pass: `smtp-secret-${tag}`, from: 'Event 360 <alerts@example.com>', alertTo: ['ops@example.com'], enabled: true })
      .expect(200);
    expect(v.body).toMatchObject({ host: 'smtp.example.com', passSet: true, enabled: true, alertTo: ['ops@example.com'] });
    expect(JSON.stringify(v.body)).not.toContain('smtp-secret');
    await http.post('/v1/admin/settings/email/test').set(A).expect(200);
    expect(mails.pop()).toMatchObject({ to: 'ops@example.com', subject: '[Event 360] Test alert' });
  });

  it('API server errors and app reports are grouped; resolving reopens on recurrence', async () => {
    await http.get('/v1/boom-test').expect(500);
    await http.get('/v1/boom-test').expect(500);
    await new Promise((r) => setTimeout(r, 300));
    const g = await prisma.errorGroup.findFirstOrThrow({ where: { message: { contains: marker } } });
    expect(g).toMatchObject({ source: 'api', count: 2, path: 'GET /v1/boom-test' });
    // 4xx are not errors
    await http.get('/v1/events/00000000-0000-0000-0000-000000000000').expect(404);

    await http.post('/v1/telemetry/errors').send({ source: 'user_app', message: `Null check ${marker}`, stack: 'at main.dart:12', path: '/tickets', release: '1.0.0' }).expect(202);
    await http.post('/v1/telemetry/errors').send({ source: 'evil', message: 'x' }).expect(400);
    await new Promise((r) => setTimeout(r, 300));
    const list = await http.get('/v1/admin/ops/errors').set(A).expect(200);
    const appErr = list.body.find((e: any) => e.message === `Null check ${marker}`);
    expect(appErr).toMatchObject({ source: 'user_app', path: '/tickets', lastRelease: '1.0.0' });
    await http.post(`/v1/admin/ops/errors/${appErr.id}/resolve`).set(A).expect(200);
    expect((await http.get('/v1/admin/ops/errors?status=resolved').set(A)).body.map((e: any) => e.id)).toContain(appErr.id);
    await http.post('/v1/telemetry/errors').send({ source: 'user_app', message: `Null check ${marker}`, stack: 'at main.dart:12' }).expect(202);
    await new Promise((r) => setTimeout(r, 300));
    expect((await prisma.errorGroup.findUniqueOrThrow({ where: { id: appErr.id } })).resolvedAt).toBeNull();
    // New errors are emailed (batched)
    await app.get(ErrorsService).flush();
    await http.get('/v1/admin/ops/status').set(A).expect(200);
  });

  it(`monitor alerts after ${FAIL_THRESHOLD} failures in a row and announces recovery`, async () => {
    const monitor = app.get(MonitorService);
    const name = `test-${tag}`;
    let healthy = false;
    const checks = [{ name, run: async () => (healthy ? 'fine' : Promise.reject(new Error('connection refused'))) }];
    mails.length = 0;
    for (let i = 0; i < FAIL_THRESHOLD - 1; i++) await monitor.runOnce(checks);
    expect(mails).toHaveLength(0); // a blip doesn't alert
    await monitor.runOnce(checks);
    expect(mails.map((m) => m.subject)).toEqual([`[Event 360] ${name} is DOWN`]);
    await monitor.runOnce(checks);
    expect(mails).toHaveLength(1); // no repeat while still down
    const st = await http.get('/v1/admin/ops/status').set(A).expect(200);
    expect(st.body.checks.find((c: any) => c.name === name)).toMatchObject({ ok: false, alerting: true, lastError: 'connection refused' });
    expect(st.body.incidents.find((i: any) => i.check === name)).toMatchObject({ endedAt: null });
    healthy = true;
    await monitor.runOnce(checks);
    expect(mails[1].subject).toBe(`[Event 360] ${name} recovered`);
    const inc = await prisma.monitorIncident.findFirstOrThrow({ where: { check: name } });
    expect(inc.endedAt).not.toBeNull();
    await prisma.monitorCheck.delete({ where: { name } });
    await prisma.monitorIncident.deleteMany({ where: { check: name } });
  });

  it('only one runner at a time; admin pages are admin-only', async () => {
    const monitor = app.get(MonitorService);
    let release!: () => void;
    const slow = [{ name: `slow-${tag}`, run: () => new Promise<string>((r) => (release = () => r('ok'))) }];
    const first = monitor.runOnce(slow);
    await new Promise((r) => setTimeout(r, 200));
    expect(await monitor.runOnce([{ name: `other-${tag}`, run: async () => 'ok' }])).toBe(false);
    release();
    expect(await first).toBe(true);
    await prisma.monitorCheck.deleteMany({ where: { name: { in: [`slow-${tag}`, `other-${tag}`] } } });
    const p = '09' + String(700000000 + Math.floor(Math.random() * 99999999));
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    await http.get('/v1/admin/ops/status').set({ Authorization: `Bearer ${r2.body.accessToken}` }).expect(403);
  });
});
