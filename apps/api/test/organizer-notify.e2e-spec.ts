/**
 * Organizer notices (organizer app): approval, sales milestones, daily summary; pushed only to organizer-app
 * devices and kept in a separate inbox. Firebase faked. Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { generateKeyPairSync, randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { FcmClient } from '../src/modules/notifications/fcm';
import { NotifyService } from '../src/modules/notifications/notify.service';
import { PushSettingsService } from '../src/modules/notifications/settings.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });

run('Organizer notices', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let notify: NotifyService;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const pushed: { token: string; kind: string }[] = [];

  async function consumer() {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return bearer(r2.body.accessToken as string);
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const orgInbox = async (h: Record<string, string>) => (await http.get('/v1/me/notifications?audience=organizer').set(h).expect(200)).body as { items: any[]; unread: number };

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    notify = app.get(NotifyService);
    prisma = app.get(PrismaService);
    jest.spyOn(app.get(PushSettingsService), 'config').mockResolvedValue({ projectId: 'p', clientEmail: 'x@p.iam.gserviceaccount.com', privateKey, enabled: true });
    notify.fcm = new FcmClient(async (url: string, init: any) => {
      if (url.includes('oauth2')) return { status: 200, text: async () => '{"access_token":"at","expires_in":3600}' };
      const m = JSON.parse(init.body).message;
      pushed.push({ token: m.token, kind: m.data.kind });
      return { status: 200, text: async () => '{}' };
    });
  });
  afterAll(async () => {
    await notify?.idle();
    jest.restoreAllMocks();
    await app?.close();
  });

  it('approval, half sold, sold out and daily summary reach the organizer app only', async () => {
    const adm = await app.get(AuthService).createInvitation({ email: `adm-on-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Notice Org ${tag}`, slug: `ntc-${tag}`, ownerEmail: `own-on-${tag}@e2e.test` }).expect(201);
    const orgId = org.body.organization.id;
    const O = await acceptInvite(org.body.inviteUrl);
    // The owner has the organizer app and (on the same account) the user app
    await http.post('/v1/me/devices').set(O).send({ pushToken: `org-${tag}-${'o'.repeat(20)}`, platform: 'android', appId: 'organizer_app' }).expect(200);
    await http.post('/v1/me/devices').set(O).send({ pushToken: `usr-${tag}-${'u'.repeat(20)}`, platform: 'android', appId: 'user_app' }).expect(200);

    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 9 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Notice Night ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    const eventId = ev.body.id;
    const tt = await http.post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`).set(O).send({ name: 'Free', priceMmk: 0, quota: 4, maxPerOrder: 2 }).expect(201);
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    await notify.idle();
    let inbox = await orgInbox(O);
    expect(inbox.items[0]).toMatchObject({ kind: 'org_event_approved', eventId, link: `/event/${eventId}` });
    expect(pushed.filter((p) => p.kind === 'org_event_approved').map((p) => p.token)).toEqual([`org-${tag}-${'o'.repeat(20)}`]); // not the user-app device
    // Attendee inbox stays separate
    expect((await http.get('/v1/me/notifications').set(O).expect(200)).body.items.filter((n: any) => n.kind.startsWith('org_'))).toHaveLength(0);

    // 2 of 4 → half sold; 4 of 4 → sold out (each once)
    const B1 = await consumer();
    const B2 = await consumer();
    await http.post(`/v1/events/${eventId}/orders`).set(B1).send({ items: [{ ticketTypeId: tt.body.id, quantity: 2 }] }).expect(201);
    await notify.idle();
    inbox = await orgInbox(O);
    expect(inbox.items[0]).toMatchObject({ kind: 'org_half_sold' });
    await http.post(`/v1/events/${eventId}/registrations`).set(B2).send({ ticketTypeId: tt.body.id, quantity: 2 }).expect(201);
    await notify.idle();
    inbox = await orgInbox(O);
    expect(inbox.items[0]).toMatchObject({ kind: 'org_sold_out', body: `All 4 tickets for Notice Night ${tag} are gone.` });
    expect(inbox.items.filter((n) => n.kind === 'org_half_sold')).toHaveLength(1);

    // Daily summary: once per day; includes this organization
    await prisma.platformSetting.deleteMany({ where: { key: { startsWith: 'org_digest:' } } });
    expect(await notify.sendDailySummaries(new Date(), true)).toBeGreaterThanOrEqual(1);
    expect(await notify.sendDailySummaries(new Date(), true)).toBe(0);
    await notify.idle();
    inbox = await orgInbox(O);
    expect(inbox.items[0]).toMatchObject({ kind: 'org_daily', body: '2 orders · 4 tickets · 0 MMK' });

    // Mark all read applies to the organizer inbox only
    await http.post('/v1/me/notifications/read').set(O).send({ audience: 'organizer' }).expect(200);
    expect((await orgInbox(O)).unread).toBe(0);

    // Rejection is announced too
    await http.post(`/v1/admin/events/${eventId}/reject`).set(A).send({ reason: 'Cover image is blurry' }).expect(200);
    await notify.idle();
    expect((await orgInbox(O)).items[0]).toMatchObject({ kind: 'org_event_rejected', body: expect.stringContaining('Cover image is blurry') });
  });
});
