/**
 * Notifications over HTTP against a real PostgreSQL: inbox, device tokens, push (Firebase faked), SMS (spied),
 * organizer announcements and the triggers (registration, event change/cancel, reminders).
 * Skipped when DATABASE_URL is not set.
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
import { SmsService } from '../src/modules/notifications/sms.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });

run('Notifications', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let notify: NotifyService;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const pushed: { token: string; title: string; body: string; data: Record<string, string> }[] = [];
  const texts: { phone: string; text: string }[] = [];

  async function consumer() {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return { h: bearer(r2.body.accessToken as string), phone: `+95${phone.slice(1)}` }; // stored as +959…
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const inbox = async (h: Record<string, string>) => (await http.get('/v1/me/notifications').set(h).expect(200)).body as { items: any[]; unread: number };

  let A: Record<string, string>, O: Record<string, string>, orgId: string, eventId: string, ttId: string;

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    notify = app.get(NotifyService);
    prisma = app.get(PrismaService);

    // Push "configured" without touching shared settings rows; Firebase faked
    jest.spyOn(app.get(PushSettingsService), 'config').mockResolvedValue({ projectId: 'p', clientEmail: 'x@p.iam.gserviceaccount.com', privateKey, enabled: true });
    notify.fcm = new FcmClient(async (url: string, init: any) => {
      if (url.includes('oauth2')) return { status: 200, text: async () => '{"access_token":"at","expires_in":3600}' };
      const m = JSON.parse(init.body).message;
      if (m.token.startsWith('gone-')) return { status: 404, text: async () => '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}' };
      pushed.push({ token: m.token, title: m.notification.title, body: m.notification.body, data: m.data });
      return { status: 200, text: async () => '{}' };
    });
    // SMS "enabled", sends recorded
    const sms = app.get(SmsService);
    jest.spyOn(sms, 'settingsConfig').mockResolvedValue({ provider: 'smspoh', apiKey: 'k', apiSecret: 's', senderId: 'E360', enabled: true, testMode: true, otpTemplate: '{code}', waitlistSms: true });
    jest.spyOn(sms, 'send').mockImplementation(async (phone: string, text: string) => {
      texts.push({ phone, text });
      return { messageId: 'm', status: 'Accepted', network: 'MPT' };
    });

    const adm = await app.get(AuthService).createInvitation({ email: `adm-n-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Notify Org ${tag}`, slug: `ntf-${tag}`, ownerEmail: `own-n-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 10 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: cats.body[0].children[0].id,
        title: `Notify Fest ${tag}`,
        format: 'IN_PERSON',
        venue: { name: 'Old Hall', city: 'Yangon' },
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString(),
      })
      .expect(201);
    eventId = ev.body.id;
    ttId = (await http.post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`).set(O).send({ name: 'Free', priceMmk: 0, quota: 50, maxPerOrder: 2 }).expect(201)).body.id;
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
  });
  afterAll(async () => {
    await notify?.idle();
    jest.restoreAllMocks();
    await app?.close();
  });

  let B1: { h: Record<string, string>; phone: string }, B2: { h: Record<string, string>; phone: string };

  it('registering sends "ticket ready" to the inbox and to the phone', async () => {
    B1 = await consumer();
    B2 = await consumer();
    const t1 = `tok-${tag}-b1-${'x'.repeat(20)}`;
    await http.post('/v1/me/devices').set(B1.h).send({ pushToken: t1, platform: 'android' }).expect(200);
    await http.post('/v1/me/devices').set(B1.h).send({ pushToken: t1, platform: 'android' }).expect(200); // idempotent
    await http.post('/v1/me/devices').set(B2.h).send({ pushToken: `gone-${tag}-${'y'.repeat(20)}`, platform: 'android' }).expect(200);

    await http.post(`/v1/events/${eventId}/orders`).set(B1.h).send({ items: [{ ticketTypeId: ttId, quantity: 2 }] }).expect(201);
    await http.post(`/v1/events/${eventId}/registrations`).set(B2.h).send({ ticketTypeId: ttId, quantity: 1 }).expect(201);
    await notify.idle();

    const i1 = await inbox(B1.h);
    expect(i1.unread).toBe(1);
    expect(i1.items[0]).toMatchObject({ kind: 'ticket_confirmed', title: 'Your 2 tickets are ready', link: '/tickets', eventId });
    expect(i1.items[0].titleMy).toBeTruthy();
    expect(pushed.filter((p) => p.token === t1)).toHaveLength(1);
    // Default language is Myanmar → push in Myanmar
    expect(pushed.find((p) => p.token === t1)!.title).toBe('လက်မှတ် 2 စောင် အသင့်ဖြစ်ပါပြီ');
    expect(pushed.find((p) => p.token === t1)!.data).toMatchObject({ kind: 'ticket_confirmed', link: '/tickets', eventId });
    expect((await inbox(B2.h)).items[0].kind).toBe('ticket_confirmed');
    // Stale token was removed; no SMS for confirmations
    expect(await prisma.device.count({ where: { pushToken: { startsWith: `gone-${tag}` } } })).toBe(0);
    expect(texts).toHaveLength(0);
  });

  it('moving the event notifies holders by push, inbox and SMS; plain edits do not', async () => {
    await http.patch(`/v1/organizations/${orgId}/events/${eventId}`).set(O).send({ summary: 'Now with more bands' }).expect(200);
    await notify.idle();
    expect(texts).toHaveLength(0);

    const newStart = new Date(Date.now() + 12 * 86400e3);
    await http
      .patch(`/v1/organizations/${orgId}/events/${eventId}`)
      .set(O)
      .send({ startsAt: newStart.toISOString(), endsAt: new Date(newStart.getTime() + 3 * 3600e3).toISOString(), venue: { name: 'New Hall', city: 'Yangon' } })
      .expect(200);
    await notify.idle();
    const changed = (await inbox(B1.h)).items[0];
    expect(changed).toMatchObject({ kind: 'event_changed', link: `/event/${eventId}` });
    expect(changed.body).toContain('New Hall');
    expect(texts.map((t) => t.phone).sort()).toEqual([B1.phone, B2.phone].sort());
    expect(texts[0].text).toMatch(/^Event 360: ".*" changed\. Now .* at New Hall\. Details in the app\.$/);
    expect(texts[0].text.length).toBeLessThanOrEqual(160);
  });

  it('organizers announce to ticket holders (limited per day); others cannot', async () => {
    const outsider = await consumer();
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/announcements`).set(outsider.h).send({ title: 'Hello', body: 'Hello all' }).expect(403);
    const sent = texts.length;
    for (let i = 1; i <= 3; i++) {
      const a = await http.post(`/v1/organizations/${orgId}/events/${eventId}/announcements`).set(O).send({ title: `Gate opens ${i}`, body: 'Doors open at 4 PM. Bring your QR.' }).expect(201);
      expect(a.body.recipients).toBe(2);
    }
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/announcements`).set(O).send({ title: 'One more', body: 'Too many today' }).expect(409);
    const list = await http.get(`/v1/organizations/${orgId}/events/${eventId}/announcements`).set(O).expect(200);
    expect(list.body).toMatchObject({ ticketHolders: 2, remainingToday: 0 });
    expect(list.body.items).toHaveLength(3);
    await notify.idle();
    const i2 = await inbox(B2.h);
    expect(i2.items[0]).toMatchObject({ kind: 'announcement', title: `Notify Fest ${tag}: Gate opens 3` });
    expect(texts.length).toBe(sent); // announcements never go by SMS
    expect((await inbox(outsider.h)).items).toHaveLength(0);
  });

  it('day-before reminder goes out once', async () => {
    const soon = new Date(Date.now() + 20 * 3600e3);
    // (the unverified organizer's edits sent it back to review; reminders are for live listings)
    await prisma.event.update({ where: { id: eventId }, data: { status: 'PUBLISHED', startsAt: soon, endsAt: new Date(soon.getTime() + 3600e3), reminderSentAt: null } });
    // Other events in the shared database may be due too (the batch is limited): settle them first, so only this one is left
    await prisma.event.updateMany({ where: { id: { not: eventId }, status: 'PUBLISHED', reminderSentAt: null, startsAt: { gt: new Date(), lte: new Date(Date.now() + 24 * 3600e3) } }, data: { reminderSentAt: new Date() } });
    expect(await notify.sendReminders()).toBe(1);
    expect(await notify.sendReminders()).toBe(0);
    await notify.idle();
    const r = (await inbox(B1.h)).items.filter((x: any) => x.kind === 'event_reminder' && x.eventId === eventId);
    expect(r).toHaveLength(1);
  });

  it('read marks; sign-out removes the device; cancelling notifies with SMS', async () => {
    const before = await inbox(B1.h);
    expect(before.unread).toBeGreaterThan(1);
    await http.post('/v1/me/notifications/read').set(B1.h).send({ ids: [before.items[0].id] }).expect(200);
    expect((await inbox(B1.h)).unread).toBe(before.unread - 1);
    await http.post('/v1/me/notifications/read').set(B1.h).send({}).expect(200);
    expect((await inbox(B1.h)).unread).toBe(0);
    // Someone else can't mark B1's notifications
    const r = await http.post('/v1/me/notifications/read').set(B2.h).send({ ids: [before.items[1].id] }).expect(200);
    expect(r.body.updated).toBe(0);

    await http.post('/v1/me/devices/remove').set(B1.h).send({ pushToken: `tok-${tag}-b1-${'x'.repeat(20)}` }).expect(200);
    const pushes = pushed.length;
    texts.length = 0;
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/cancel`).set(O).expect(200);
    await notify.idle();
    expect((await inbox(B1.h)).items[0]).toMatchObject({ kind: 'event_cancelled' });
    expect(pushed.length).toBe(pushes); // B1 signed out, B2's token was stale
    expect(texts.map((t) => t.phone).sort()).toEqual([B1.phone, B2.phone].sort());
    expect(texts[0].text).toContain('CANCELLED');
  });

  it('admin push settings validate the Firebase key and never return it', async () => {
    await http.put('/v1/admin/settings/push').set(A).send({ serviceAccountJson: '{"nope":1}' }).expect(503);
    await http.get('/v1/admin/settings/push').set(O).expect(403);
    const key = JSON.stringify({ type: 'service_account', project_id: `e360-${tag}`, client_email: `push@e360-${tag}.iam.gserviceaccount.com`, private_key: privateKey });
    const v = await http.put('/v1/admin/settings/push').set(A).send({ serviceAccountJson: key, enabled: false }).expect(200);
    expect(v.body).toMatchObject({ projectId: `e360-${tag}`, privateKeySet: true, enabled: false });
    expect(JSON.stringify(v.body)).not.toContain('PRIVATE KEY');
    const t = await http.post('/v1/admin/settings/push/test').set(A).expect(200);
    expect(t.body.ok).toBe(true);
    expect((await inbox(A)).items[0].kind).toBe('test');
  });
});
