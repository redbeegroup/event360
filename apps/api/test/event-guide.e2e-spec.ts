/**
 * Event guide server pieces over HTTP against a real PostgreSQL: announcements for ticket holders
 * (GET /v1/me/events/:eventId/announcements) and checkedInAt on GET /v1/me/tickets.
 * Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { NotifyService } from '../src/modules/notifications/notify.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

// Every key of a ticket item before this round (checkedInAt is the only addition)
const OLD_TICKET_KEYS = ['id', 'status', 'createdAt', 'seatKey', 'seatLabel', 'seatLabelMy', 'isComplimentary', 'compLabel', 'ticketType', 'event', 'qr', 'canCancel', 'canTransfer'];

run('Event guide server', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  let notify: NotifyService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  type U = { h: Record<string, string>; phone: string };

  async function consumer(): Promise<U> {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return { h: bearer(r2.body.accessToken as string), phone: `+95${phone.slice(1)}` };
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }

  let A: Record<string, string>, O: Record<string, string>, orgId: string;
  async function publishedEvent(name: string) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 10 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: cats.body[0].children[0].id,
        title: `${name} ${tag}`,
        format: 'IN_PERSON',
        venue: { name: 'Old Hall', city: 'Yangon' },
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString(),
      })
      .expect(201);
    const eventId = ev.body.id as string;
    const ttId = (await http.post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`).set(O).send({ name: 'Free', priceMmk: 0, quota: 50, maxPerOrder: 4 }).expect(201)).body.id as string;
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    return { eventId, ttId };
  }
  const register = async (u: U, ev: { eventId: string; ttId: string }, quantity = 1) => {
    await http.post(`/v1/events/${ev.eventId}/registrations`).set(u.h).send({ ticketTypeId: ev.ttId, quantity }).expect(201);
  };
  const mine = async (u: U) => (await http.get('/v1/me/tickets').set(u.h).expect(200)).body as any[];
  const guide = (u: U | null, eventId: string) => {
    const r = http.get(`/v1/me/events/${eventId}/announcements`);
    return u ? r.set(u.h) : r;
  };

  let E1: { eventId: string; ttId: string }, E2: { eventId: string; ttId: string };

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
    prisma = app.get(PrismaService);
    notify = app.get(NotifyService);

    const adm = await app.get(AuthService).createInvitation({ email: `adm-g-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Guide Org ${tag}`, slug: `gd-${tag}`, ownerEmail: `own-g-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    E1 = await publishedEvent('Guide Fest');
    E2 = await publishedEvent('Other Fest');
  });
  afterAll(async () => {
    await notify?.idle();
    await app?.close();
  });

  it('a holder gets the event announcements, newest first, with exactly six keys', async () => {
    const H = await consumer();
    await register(H, E1);
    const t0 = Date.now();
    const owner = await prisma.user.findFirstOrThrow({ where: { email: `own-g-${tag}@e2e.test` }, select: { id: true } });
    const make = (eventId: string, title: string, ago: number) =>
      prisma.announcement.create({
        data: { eventId, createdById: owner.id, title, titleMy: ago === 2 ? null : `${title} MY`, body: `${title} body`, bodyMy: ago === 2 ? null : `${title} body MY`, createdAt: new Date(t0 - ago * 60_000) },
      });
    const older = await make(E1.eventId, 'Doors open', 2);
    const newer = await make(E1.eventId, 'Gate change', 1);
    await make(E2.eventId, 'Elsewhere', 0);

    const r = await guide(H, E1.eventId).expect(200);
    expect(r.body.map((a: any) => a.id)).toEqual([newer.id, older.id]);
    expect(Object.keys(r.body[0]).sort()).toEqual(['body', 'bodyMy', 'createdAt', 'id', 'title', 'titleMy']);
    expect(r.body[0]).toMatchObject({ title: 'Gate change', titleMy: 'Gate change MY', body: 'Gate change body', bodyMy: 'Gate change body MY' });
    expect(r.body[1]).toMatchObject({ titleMy: null, bodyMy: null });
    expect(new Date(r.body[0].createdAt).getTime()).toBe(newer.createdAt.getTime());
    expect(JSON.stringify(r.body)).not.toContain('Elsewhere');
  });

  it('caps at 50 newest', async () => {
    const H = await consumer();
    const ev = await publishedEvent('Many');
    await register(H, ev);
    const owner = await prisma.user.findFirstOrThrow({ where: { email: `own-g-${tag}@e2e.test` }, select: { id: true } });
    const base = Date.now() - 3600e3;
    await prisma.announcement.createMany({ data: Array.from({ length: 52 }, (_, i) => ({ eventId: ev.eventId, createdById: owner.id, title: `n${i}`, body: 'b', createdAt: new Date(base + i * 1000) })) });
    const r = await guide(H, ev.eventId).expect(200);
    expect(r.body).toHaveLength(50);
    expect(r.body[0].title).toBe('n51');
  });

  it('access: 401 signed out, 404 unknown event (first), 403 without a valid ticket', async () => {
    const H = await consumer();
    const N = await consumer();
    await register(H, E1);
    await guide(null, E1.eventId).expect(401);
    const unknown = '00000000-0000-4000-8000-000000000001';
    await guide(H, unknown).expect(404);
    await guide(N, unknown).expect(404);
    await guide(N, E1.eventId).expect(403); // signed in, no ticket
    await guide(H, E2.eventId).expect(403); // ticket for another event only
    // only ticket VOID
    const V = await consumer();
    await register(V, E1);
    await prisma.ticket.update({ where: { id: (await mine(V))[0].id }, data: { status: 'VOID' } });
    await guide(V, E1.eventId).expect(403);
  });

  it('a guest (comp) ticket holder is a holder', async () => {
    const G = await consumer();
    await register(G, E1);
    const t = (await mine(G))[0];
    await prisma.ticket.update({ where: { id: t.id }, data: { isComplimentary: true, compLabel: 'VIP guest' } });
    expect((await mine(G))[0]).toMatchObject({ isComplimentary: true, compLabel: 'VIP guest' });
    await guide(G, E1.eventId).expect(200);
  });

  it('after a transfer the old holder loses access and the new holder gains it', async () => {
    const S = await consumer();
    const R = await consumer();
    await register(S, E1);
    const t = (await mine(S))[0];
    await guide(S, E1.eventId).expect(200);
    await guide(R, E1.eventId).expect(403);
    await http.post(`/v1/me/tickets/${t.id}/transfer`).set(S.h).send({ phone: R.phone }).expect(200);
    await guide(S, E1.eventId).expect(403);
    await guide(R, E1.eventId).expect(200);
  });

  it('/me/tickets: checkedInAt follows the crew check-in and undo; duplicates are ignored; old keys unchanged', async () => {
    const H = await consumer();
    await register(H, E1, 2);
    const before = await mine(H);
    expect(before).toHaveLength(2);
    for (const t of before) {
      expect(t.checkedInAt).toBeNull();
      expect(Object.keys(t).sort()).toEqual([...OLD_TICKET_KEYS, 'checkedInAt'].sort());
    }
    const [a, b] = before;
    const scan = await http.post(`/v1/crew/events/${E1.eventId}/scan`).set(O).send({ qr: a.qr, gate: 'Main' }).expect(200);
    expect(scan.body.result).toBe('ACCEPTED');
    const row = await prisma.checkin.findFirstOrThrow({ where: { ticketId: a.id, isDuplicate: false, undoneAt: null } });
    let after = await mine(H);
    const ta = after.find((t) => t.id === a.id);
    const tb = after.find((t) => t.id === b.id);
    expect(ta.checkedInAt).toBe(row.scannedAt.toISOString());
    expect(tb.checkedInAt).toBeNull(); // the other ticket is unaffected
    expect(ta.status).toBe('CHECKED_IN');
    expect(ta.qr).toBeNull();
    // every pre-existing key keeps its value (apart from the check-in's own status/qr changes)
    const old = before.find((t) => t.id === a.id);
    for (const k of OLD_TICKET_KEYS.filter((k) => !['status', 'qr', 'canCancel', 'canTransfer'].includes(k))) expect(ta[k]).toEqual(old[k]);
    const untouched = before.find((t) => t.id === b.id);
    for (const k of OLD_TICKET_KEYS) expect(tb[k]).toEqual(untouched[k]);

    // a duplicate scan does not change it
    await prisma.checkin.create({ data: { ticketId: a.id, eventId: E1.eventId, scannedAt: new Date(row.scannedAt.getTime() + 60_000), isDuplicate: true } });
    after = await mine(H);
    expect(after.find((t) => t.id === a.id).checkedInAt).toBe(row.scannedAt.toISOString());

    // undo clears it
    await http.post(`/v1/crew/events/${E1.eventId}/tickets/${a.id}/undo`).set(O).expect(200);
    after = await mine(H);
    expect(after.find((t) => t.id === a.id).checkedInAt).toBeNull();
  });
});
