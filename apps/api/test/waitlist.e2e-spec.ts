/**
 * Waitlist for sold-out ticket types, against a real PostgreSQL. Skipped when DATABASE_URL is not set.
 * SMS goes to a stubbed fetch (SMSPoh); nothing is ever sent for real.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { NotifyService } from '../src/modules/notifications/notify.service';
import { SettingsService } from '../src/modules/notifications/settings.service';
import { PaymentsService } from '../src/modules/payments/payments.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';
import { WaitlistService } from '../src/modules/waitlist/waitlist.service';
import { expireHold } from './expire-hold';
import { gated, lockGate, queued } from './lock-gate';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Waitlist', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  let pay: PaymentsService;
  let wl: WaitlistService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const realFetch = global.fetch;
  const smsCalls: { to: string; message: string }[] = [];
  // Hall: section V is one row of 4 seats (VIP)
  const hall = {
    width: 600,
    height: 400,
    sections: [{ key: 'V', name: 'VIP', kind: 'SEATED', x: 10, y: 10, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }] }] }],
  };
  let A: Record<string, string>, O: Record<string, string>, orgId: string, versionId: string;

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  /** A signed-in consumer: auth header and user id. */
  async function consumer() {
    const p = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return { H: bearer(r2.body.accessToken as string), id: r2.body.user.id as string, phone: p };
  }
  const base = (eventId: string) => `/v1/organizations/${orgId}/events/${eventId}`;
  const tt = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });
  const entry = (id: string) => prisma.waitlistEntry.findUniqueOrThrow({ where: { id } });
  const seat = (eventId: string, key: string) => prisma.eventSeat.findUniqueOrThrow({ where: { eventId_seatKey: { eventId, seatKey: key } } });
  const order = (H: Record<string, string>, eventId: string, body: object) => http.post(`/v1/events/${eventId}/orders`).set(H).send(body);
  const join = (H: Record<string, string>, typeId: string, quantity: number) => http.post(`/v1/ticket-types/${typeId}/waitlist`).set(H).send({ quantity });
  const items = (ticketTypeId: string, quantity: number) => ({ items: [{ ticketTypeId, quantity }] });

  async function newEvent(title: string) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `${title} ${tag}`, format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    return ev.body.id as string;
  }
  const addType = async (eventId: string, b: object) => (await http.post(`${base(eventId)}/ticket-types`).set(O).send(b).expect(201)).body.id as string;
  const publish = (id: string) => prisma.event.update({ where: { id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });

  /** Published standing event with one paid type. */
  async function standing(title: string, quota: number, maxPerOrder = 4, priceMmk = 5_000) {
    const id = await newEvent(title);
    const type = await addType(id, { name: 'Floor', priceMmk, quota, maxPerOrder });
    await publish(id);
    return { id, type };
  }
  /** Published seated event: V:1:1..V:1:4 are VIP (20,000). */
  async function seated(title: string) {
    const id = await newEvent(title);
    const vip = await addType(id, { name: 'VIP', priceMmk: 20_000, quota: 1, maxPerOrder: 4 });
    await http.put(`${base(id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'V', ticketTypeId: vip }] }).expect(200);
    await publish(id);
    return { id, vip };
  }
  /** Counters of a seated type always match its seats; WAITLIST_HOLD seats are `offered`, not available. */
  async function expectSeatCounters(typeId: string) {
    const [t, seats] = await Promise.all([tt(typeId), prisma.eventSeat.findMany({ where: { ticketTypeId: typeId } })]);
    const n = (s: string) => seats.filter((x) => x.status === s).length;
    expect({ quota: t.quota, held: t.held, sold: t.sold, offered: t.offered }).toEqual({
      quota: n('AVAILABLE') + n('CHECKOUT_HOLD') + n('SOLD') + n('WAITLIST_HOLD'),
      held: n('CHECKOUT_HOLD'),
      sold: n('SOLD'),
      offered: n('WAITLIST_HOLD'),
    });
  }
  /** Sweeper steps, run directly (the interval is off in tests). */
  const sweepWaitlist = async (now = new Date()) => {
    await wl.expireOffers(now);
    await wl.assignOffers(now);
    await app.get(NotifyService).idle();
  };

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    jest.spyOn(global, 'fetch').mockImplementation(async (input: any, init?: any) => {
      const url = String(input);
      if (!url.startsWith('https://v3.smspoh.com/')) return realFetch(input, init);
      const body = JSON.parse(init.body);
      smsCalls.push({ to: body.to, message: body.message });
      return new Response(JSON.stringify({ messages: [{ messageId: `MSG-${smsCalls.length}`, to: body.to, status: 'Accepted', network: 'MPT', messageCount: 1 }] }), { status: 201 });
    });
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    pay = app.get(PaymentsService);
    wl = app.get(WaitlistService);
    // SMS off unless a test turns it on (the stored setting row is shared with other suites, so it is stubbed here)
    jest.spyOn(app.get(SettingsService) as any, 'stored').mockResolvedValue({ provider: 'smspoh' });
    const adm = await app.get(AuthService).createInvitation({ email: `adm-wl-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Waitlist Org ${tag}`, slug: `wl-${tag}`, ownerEmail: `own-wl-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `WL Hall ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id;
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    jest.restoreAllMocks();
    await app?.close();
  });

  it('join only when sold out; one active entry per user; quantity within maxPerOrder', async () => {
    const ev = await standing('Join', 2, 2);
    const [H, W1, W2] = [await consumer(), await consumer(), await consumer()];
    await http.post(`/v1/ticket-types/${ev.type}/waitlist`).send({ quantity: 1 }).expect(401);
    const notYet = await join(W1.H, ev.type, 1).expect(409);
    expect(notYet.body.message).toMatch(/not sold out/i);
    expect(notYet.body.reasonCode).toBe('NOT_SOLD_OUT');
    await order(H.H, ev.id, items(ev.type, 2)).expect(201); // held: sold out for the public
    expect((await http.get(`/v1/events/${ev.id}`).expect(200)).body.ticketTypes[0].remaining).toBe(0);

    await join(W1.H, ev.type, 3).expect(400); // above maxPerOrder
    await join(W1.H, ev.type, 0).expect(400);
    // The per-person limit counts what the buyer already holds or is paying for
    const limit = await join(H.H, ev.type, 1).expect(409);
    expect(limit.body.message).toMatch(/limit is 2 per person/);
    expect(limit.body.reasonCode).toBe('LIMIT');
    const j1 = await join(W1.H, ev.type, 2).expect(201);
    expect(j1.body).toEqual({ entryId: expect.any(String), position: 1 });
    const again = await join(W1.H, ev.type, 1).expect(409);
    expect(again.body.message).toMatch(/already/i);
    expect(again.body.reasonCode).toBe('ALREADY_WAITING');
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    expect(j2.body.position).toBe(2);

    const mine = await http.get('/v1/me/waitlist').set(W1.H).expect(200);
    expect(mine.body).toHaveLength(1);
    expect(mine.body[0]).toMatchObject({ id: j1.body.entryId, ticketTypeId: ev.type, eventId: ev.id, status: 'WAITING', quantity: 2, position: 1, offeredQty: 0, offerExpiresAt: null, seatKeys: [] });

    // Organizer counts per type
    const counts = await http.get(`${base(ev.id)}/waitlist`).set(O).expect(200);
    expect(counts.body.ticketTypes).toEqual([expect.objectContaining({ id: ev.type, waiting: 2, waitingQuantity: 3, offered: 0 })]);
    expect(counts.body.total).toBe(2);
    await http.get(`${base(ev.id)}/waitlist`).set(W1.H).expect(403);

    // Leave, then join again at the back of the line
    await http.delete(`/v1/ticket-types/${ev.type}/waitlist`).set(W1.H).expect(200);
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'LEFT' });
    expect((await http.delete(`/v1/ticket-types/${ev.type}/waitlist`).set(W1.H).expect(404)).body.reasonCode).toBe('NOT_WAITING');
    const mineRows = (await http.get('/v1/me/waitlist').set(W2.H).expect(200)).body;
    expect(mineRows[0].position).toBe(1);
    expect(Math.abs(Date.parse(mineRows[0].serverNow) - Date.now())).toBeLessThan(60_000);
    const j3 = await join(W1.H, ev.type, 1).expect(201);
    expect(j3.body.position).toBe(2);

    // Closed after sales end and once the event starts
    await prisma.ticketType.update({ where: { id: ev.type }, data: { salesEndAt: new Date(Date.now() - 1000) } });
    const closed = await join(H.H, ev.type, 1).expect(409);
    expect(closed.body.message).toMatch(/closed/i);
    expect(closed.body.reasonCode).toBe('WAITLIST_CLOSED');
    await prisma.ticketType.update({ where: { id: ev.type }, data: { salesEndAt: null } });
    await prisma.event.update({ where: { id: ev.id }, data: { startsAt: new Date(Date.now() - 1000) } });
    await join(H.H, ev.type, 1).expect(409);
  });

  it('freed standing ticket is reserved for the line: 20 parallel public orders all 409, offeree can buy', async () => {
    const ev = await standing('Reserve', 2, 2);
    const [H, W, X] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    const j = await join(W.H, ev.type, 2).expect(201);

    // Releasing the hold reserves the stock for the line in the same transaction
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 2 });
    expect((await http.get(`/v1/events/${ev.id}`).expect(200)).body.ticketTypes[0].remaining).toBe(0);
    const buyers = await Promise.all(Array.from({ length: 20 }, (_, i) => prisma.user.create({ data: { phone: `0961${tag.slice(0, 4)}${String(i).padStart(3, '0')}`.slice(0, 14) } })));
    const buy = (id: string) => pay.createOrder(id, ev.id, [{ ticketTypeId: ev.type, quantity: 1 }]);
    const rush = await Promise.allSettled(buyers.map((u) => buy(u.id)));
    // A busy machine can make some wait longer than Prisma's 2 s for a pool connection (P2028, before any lock):
    // those try again, one at a time
    const outcome = await Promise.all(
      rush.map(async (r, i) => {
        let res: PromiseSettledResult<unknown> = r;
        if (res.status === 'rejected' && (res.reason as any).code === 'P2028') res = (await Promise.allSettled([buy(buyers[i].id)]))[0];
        return res.status === 'rejected' ? ((res.reason as any).getStatus?.() ?? String((res.reason as any).message)) : 'ordered';
      }),
    );
    expect(outcome).toEqual(Array(20).fill(409));
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 2 });
    // Joining is allowed while everything left is reserved for offers
    await join(X.H, ev.type, 1).expect(201);

    await sweepWaitlist();
    const offered = await entry(j.body.entryId);
    expect(offered).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    expect(offered.offerExpiresAt!.getTime() - offered.offeredAt!.getTime()).toBe(30 * 60e3);
    const mine = (await http.get('/v1/me/waitlist').set(W.H).expect(200)).body[0];
    expect(mine).toMatchObject({ status: 'OFFERED', offeredQty: 2, position: null });
    expect(new Date(mine.offerExpiresAt).getTime()).toBe(offered.offerExpiresAt!.getTime());
    expect(await prisma.notification.count({ where: { userId: W.id, kind: 'waitlist_offer' } })).toBe(1);

    // Still nothing for the public; nobody else can use the offer; not more than offered
    await order(X.H, ev.id, items(ev.type, 1)).expect(409);
    await order(X.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j.body.entryId }).expect(404);
    await order(W.H, ev.id, { ...items(ev.type, 3), waitlistEntryId: j.body.entryId }).expect(400);
    const bought = await order(W.H, ev.id, { ...items(ev.type, 2), waitlistEntryId: j.body.entryId }).expect(201);
    expect(bought.body).toMatchObject({ status: 'PENDING_PAYMENT', totalMmk: 10_000 });
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'PURCHASED', orderId: bought.body.id });
    expect(await tt(ev.type)).toMatchObject({ held: 2, sold: 0, offered: 0 });
    // A used offer cannot be used again
    const used = await order(W.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j.body.entryId }).expect(409);
    expect(used.body.reasonCode).toBe('OFFER_CLOSED');
  });

  it('offeree may buy fewer than offered; the rest goes to the next entry', async () => {
    const ev = await standing('Fewer', 2, 2);
    const [H, W1, W2] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    const j1 = await join(W1.H, ev.type, 2).expect(201);
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    await expireHold(prisma, pay, held.body.id);
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'WAITING' });
    await order(W1.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j1.body.entryId }).expect(201);
    expect(await tt(ev.type)).toMatchObject({ held: 1, offered: 1 });
    await sweepWaitlist();
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    expect(await tt(ev.type)).toMatchObject({ held: 1, offered: 1 });
  });

  it('offer expires after 30 minutes and moves to the next entry', async () => {
    const ev = await standing('Expire', 1, 1);
    const [H, W1, W2] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    const j1 = await join(W1.H, ev.type, 1).expect(201);
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    await expireHold(prisma, pay, held.body.id);
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    // Not yet: 29 minutes later the offer still stands
    await sweepWaitlist(new Date(Date.now() + 29 * 60e3));
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED' });

    await prisma.waitlistEntry.update({ where: { id: j1.body.entryId }, data: { offerExpiresAt: new Date(Date.now() - 1000) } });
    await order(W1.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j1.body.entryId }).expect(409);
    smsCalls.length = 0;
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    // A one-line inbox notice, no SMS
    const gone = await prisma.notification.findMany({ where: { userId: W1.id, kind: 'waitlist_offer_expired' } });
    expect(gone).toHaveLength(1);
    expect(gone[0].body).toBe(`Your offer for Expire ${tag} expired.`);
    expect(gone[0].bodyMy).toBeTruthy();
    expect(smsCalls.filter((c) => c.to === `95${W1.phone.slice(1)}`)).toHaveLength(0);
    await sweepWaitlist();
    expect(await prisma.notification.count({ where: { userId: W1.id, kind: 'waitlist_offer_expired' } })).toBe(1);
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 1 });
    await order(W2.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j2.body.entryId }).expect(201);
    expect(await tt(ev.type)).toMatchObject({ held: 1, offered: 0 });
  });

  it('offer expiring while the offeree holds a checkout does not double count', async () => {
    const ev = await standing('Double', 1, 1);
    const [H, W1, W2] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    const j1 = await join(W1.H, ev.type, 1).expect(201);
    await expireHold(prisma, pay, held.body.id);
    await sweepWaitlist();

    // The offer is used for a checkout; the offer's expiry no longer matters
    const co = await order(W1.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j1.body.entryId }).expect(201);
    await prisma.waitlistEntry.update({ where: { id: j1.body.entryId }, data: { offerExpiresAt: new Date(Date.now() - 1000) } });
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'PURCHASED' });
    expect(await tt(ev.type)).toMatchObject({ held: 1, sold: 0, offered: 0 });

    // The checkout's hold expires: the ticket goes to the next in line, counted once
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    await expireHold(prisma, pay, co.body.id);
    await sweepWaitlist();
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 1 });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });

    // The offer expires while W2's checkout is in flight: the checkout waits on the entry row, then fails; the
    // ticket stays reserved once
    const [c, x] = await gated(
      prisma,
      (tx) => tx.$executeRaw`UPDATE waitlist_entries SET offer_expires_at = now() - interval '1 second' WHERE id = ${j2.body.entryId}::uuid`,
      () => order(W2.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j2.body.entryId }).then((r) => r),
      () => wl.expireOffers(new Date(Date.now() + 31 * 60e3)),
    );
    expect(c.status).toBe(409);
    expect(x.expired).toBeGreaterThanOrEqual(1);
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 1 });
    expect(await prisma.order.count({ where: { userId: W2.id } })).toBe(0);
    // Nobody left in line: the ticket returns to the public
    await sweepWaitlist();
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 0 });
  });

  it('offer assignment racing a releaseHold or a purchase on the same type does not deadlock', async () => {
    const ev = await standing('Race', 3, 1);
    const [H1, H2, W1, W2] = [await consumer(), await consumer(), await consumer(), await consumer()];
    const h1 = await order(H1.H, ev.id, items(ev.type, 1)).expect(201);
    const h2 = await order(H2.H, ev.id, items(ev.type, 1)).expect(201);
    await order((await consumer()).H, ev.id, items(ev.type, 1)).expect(201);
    const j1 = await join(W1.H, ev.type, 1).expect(201);
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    await http.post(`/v1/orders/${h1.body.id}/cancel`).set(H1.H).expect(200);
    expect(await tt(ev.type)).toMatchObject({ held: 2, offered: 1 });

    // Both queue on the counter row: the release (order row → type row → entries read) and the assignment
    // (type row → entry rows)
    const lockType = (tx: any) => tx.$queryRaw`SELECT id FROM ticket_types WHERE id = ${ev.type}::uuid FOR NO KEY UPDATE`;
    const [rel, asg] = await gated(
      prisma,
      lockType,
      () => http.post(`/v1/orders/${h2.body.id}/cancel`).set(H2.H).then((r) => r),
      () => wl.assignOffers(new Date()),
    );
    expect(rel.status).toBe(200);
    expect(asg.offered).toBeGreaterThanOrEqual(1);
    await sweepWaitlist();
    expect(await tt(ev.type)).toMatchObject({ held: 1, offered: 2 });
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED' });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED' });

    // A purchase (type row → entry row) and an assignment (type row → entry rows) queue on the type row. W2 gives
    // up their offer (it becomes the pool) and W3 waits, so the assignment has work to do.
    const W3 = await consumer();
    const j3 = await join(W3.H, ev.type, 1).expect(201);
    await http.delete(`/v1/ticket-types/${ev.type}/waitlist`).set(W2.H).expect(200);
    const [buy, asg2] = await gated(
      prisma,
      lockType,
      () => order(W1.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j1.body.entryId }).then((r) => r),
      () => wl.assignOffers(new Date()),
    );
    expect(buy.status).toBe(201);
    expect(asg2.offered).toBeGreaterThanOrEqual(1);
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'PURCHASED' });
    expect(await entry(j3.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    expect(await tt(ev.type)).toMatchObject({ held: 2, offered: 1 });
  });

  it('seated: freed seats become WAITLIST_HOLD for the offeree; best-available and public claims skip them; offeree buys them', async () => {
    const ev = await seated('Seated');
    const [H, W, X] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4'] }).expect(201);
    const j = await join(W.H, ev.vip, 2).expect(201);

    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    // Two seats are kept for the line (seat_key order), two go back on sale
    expect((await seat(ev.id, 'V:1:1')).status).toBe('WAITLIST_HOLD');
    expect((await seat(ev.id, 'V:1:2')).status).toBe('WAITLIST_HOLD');
    expect((await seat(ev.id, 'V:1:3')).status).toBe('AVAILABLE');
    expect((await seat(ev.id, 'V:1:4')).status).toBe('AVAILABLE');
    await expectSeatCounters(ev.vip);
    expect(await tt(ev.vip)).toMatchObject({ quota: 4, offered: 2, held: 0 });
    const pub = await http.get(`/v1/events/${ev.id}/seats`).expect(200);
    expect(pub.body.status).toBe('TTAA');

    await sweepWaitlist();
    const e = await entry(j.body.entryId);
    expect(e).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    expect((await seat(ev.id, 'V:1:1')).waitlistEntryId).toBe(e.id);
    expect((await seat(ev.id, 'V:1:2')).waitlistEntryId).toBe(e.id);
    const mine = (await http.get('/v1/me/waitlist').set(W.H).expect(200)).body[0];
    expect(mine.seatKeys).toEqual(['V:1:1', 'V:1:2']);

    // The public can't take them, by claim or by best-available
    const taken = await order(X.H, ev.id, { seats: ['V:1:1'] }).expect(409);
    expect(taken.body.takenSeats).toEqual(['V:1:1']);
    const best = await http.post(`/v1/events/${ev.id}/seats/best`).send({ ticketTypeId: ev.vip, quantity: 2 }).expect(200);
    expect(best.body.seats).toEqual(['V:1:3', 'V:1:4']);
    await http.post(`/v1/events/${ev.id}/seats/best`).send({ ticketTypeId: ev.vip, quantity: 3 }).expect(409);
    // ... nor with someone else's entry id; the owner's own seats count for them
    await http.post(`/v1/events/${ev.id}/seats/best`).send({ ticketTypeId: ev.vip, quantity: 4, waitlistEntryId: e.id }).expect(401);
    await http.post(`/v1/events/${ev.id}/seats/best`).set(X.H).send({ ticketTypeId: ev.vip, quantity: 4, waitlistEntryId: e.id }).expect(409);
    const own = await http.post(`/v1/events/${ev.id}/seats/best`).set(W.H).send({ ticketTypeId: ev.vip, quantity: 4, waitlistEntryId: e.id }).expect(200);
    expect(own.body.seats).toEqual(['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4']);
    await order(X.H, ev.id, { seats: ['V:1:1'], waitlistEntryId: e.id }).expect(404);

    // The offeree buys their seats
    const r = await order(W.H, ev.id, { seats: ['V:1:1', 'V:1:2'], waitlistEntryId: e.id }).expect(201);
    expect(r.body).toMatchObject({ status: 'PENDING_PAYMENT', totalMmk: 40_000 });
    expect(await seat(ev.id, 'V:1:1')).toMatchObject({ status: 'CHECKOUT_HOLD', orderId: r.body.id, waitlistEntryId: null });
    expect(await entry(e.id)).toMatchObject({ status: 'PURCHASED', orderId: r.body.id });
    await expectSeatCounters(ev.vip);
    expect(await tt(ev.vip)).toMatchObject({ quota: 4, offered: 0, held: 2 });
  });

  it('seated purchase and offer assignment on the same type do not deadlock', async () => {
    const ev = await seated('SeatRace');
    const [H1, H2, W1, W2] = [await consumer(), await consumer(), await consumer(), await consumer()];
    const h1 = await order(H1.H, ev.id, { seats: ['V:1:1', 'V:1:2'] }).expect(201);
    const h2 = await order(H2.H, ev.id, { seats: ['V:1:3', 'V:1:4'] }).expect(201);
    const j1 = await join(W1.H, ev.vip, 2).expect(201);
    await http.post(`/v1/orders/${h1.body.id}/cancel`).set(H1.H).expect(200);
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    const j2 = await join(W2.H, ev.vip, 2).expect(201);
    await http.post(`/v1/orders/${h2.body.id}/cancel`).set(H2.H).expect(200);
    expect((await seat(ev.id, 'V:1:3')).status).toBe('WAITLIST_HOLD');

    // Purchase: seats V:1:1-2 → VIP counter row (held by the gate) → entry 1. Assignment: all of VIP's WAITLIST_HOLD
    // seats in seat_key order, so it queues behind the purchase on V:1:1; once the purchase commits it skips V:1:1-2
    // (now CHECKOUT_HOLD), keeps V:1:3-4, recounts the VIP counter row and offers them to entry 2.
    const [buy, asg] = await gated(
      prisma,
      (tx) => tx.$queryRaw`SELECT id FROM ticket_types WHERE id = ${ev.vip}::uuid FOR NO KEY UPDATE`,
      () => order(W1.H, ev.id, { seats: ['V:1:1', 'V:1:2'], waitlistEntryId: j1.body.entryId }).then((r) => r),
      () => wl.assignOffers(new Date()),
    );
    expect(buy.status).toBe(201);
    expect(asg).toBeTruthy();
    await sweepWaitlist();
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    await expectSeatCounters(ev.vip);
    expect(await tt(ev.vip)).toMatchObject({ held: 2, offered: 2 });
  });

  it('partial offer when fewer seats free than wanted', async () => {
    const ev = await seated('Partial');
    const [H1, H2, W] = [await consumer(), await consumer(), await consumer()];
    const h1 = await order(H1.H, ev.id, { seats: ['V:1:2'] }).expect(201);
    await order(H2.H, ev.id, { seats: ['V:1:1', 'V:1:3', 'V:1:4'] }).expect(201);
    const j = await join(W.H, ev.vip, 3).expect(201);
    await expireHold(prisma, pay, h1.body.id);
    await sweepWaitlist();
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1, quantity: 3 });
    expect((await http.get('/v1/me/waitlist').set(W.H).expect(200)).body[0].seatKeys).toEqual(['V:1:2']);
    await order(W.H, ev.id, { seats: ['V:1:2'], waitlistEntryId: j.body.entryId }).expect(201);
    await expectSeatCounters(ev.vip);
  });

  it('no WAITING entries: freed stock returns to public sale as today', async () => {
    const ev = await standing('Public', 2, 2);
    const [H, B] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    await expireHold(prisma, pay, held.body.id);
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 0 });
    await order(B.H, ev.id, items(ev.type, 2)).expect(201);

    const s = await seated('PublicSeats');
    const h2 = await order(H.H, s.id, { seats: ['V:1:1'] }).expect(201);
    await http.post(`/v1/orders/${h2.body.id}/cancel`).set(H.H).expect(200);
    expect((await seat(s.id, 'V:1:1')).status).toBe('AVAILABLE');
    await expectSeatCounters(s.vip);

    // Demand for 1 of 2 freed: 1 reserved, 1 back on sale
    const ev2 = await standing('Split', 2, 2);
    const h3 = await order(H.H, ev2.id, items(ev2.type, 2)).expect(201);
    await join(B.H, ev2.type, 1).expect(201);
    await http.post(`/v1/orders/${h3.body.id}/cancel`).set(H.H).expect(200);
    expect(await tt(ev2.type)).toMatchObject({ held: 0, offered: 1 });
    await order((await consumer()).H, ev2.id, items(ev2.type, 1)).expect(201);
    await order((await consumer()).H, ev2.id, items(ev2.type, 1)).expect(409);
  });

  it('every path that frees stock reserves it for the line', async () => {
    // Refund of a paid standing order
    const ev = await standing('Refund', 1, 1);
    const [H, W] = [await consumer(), await consumer()];
    const o = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(H.H).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(p.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t') }).expect(201);
    await join(W.H, ev.type, 1).expect(201);
    await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'test refund' }).expect(200);
    expect(await tt(ev.type)).toMatchObject({ sold: 0, offered: 1 });

    // Free ticket cancelled; free registration can't take the reserved one
    const fe = await newEvent('FreeCancel');
    const free = await addType(fe, { name: 'Free', priceMmk: 0, quota: 1, maxPerOrder: 1 });
    await publish(fe);
    const reg = await http.post(`/v1/events/${fe}/registrations`).set(H.H).send({ ticketTypeId: free, quantity: 1 }).expect(201);
    await join(W.H, free, 1).expect(201);
    await http.post(`/v1/me/tickets/${reg.body.ticketIds[0]}/cancel`).set(H.H).expect(200);
    expect(await tt(free)).toMatchObject({ sold: 0, offered: 1 });
    await http.post(`/v1/events/${fe}/registrations`).set((await consumer()).H).send({ ticketTypeId: free, quantity: 1 }).expect(409);
    await sweepWaitlist();
    const fwe = (await http.get('/v1/me/waitlist').set(W.H).expect(200)).body.find((x: any) => x.ticketTypeId === free);
    const fo = await order(W.H, fe, { ...items(free, 1), waitlistEntryId: fwe.id }).expect(201);
    expect(fo.body.status).toBe('CONFIRMED');
    expect(await tt(free)).toMatchObject({ sold: 1, offered: 0 });

    // Quota raised by the organizer
    const qe = await standing('Quota', 1, 1);
    await order(H.H, qe.id, items(qe.type, 1)).expect(201);
    await join(W.H, qe.type, 1).expect(201);
    await http.patch(`${base(qe.id)}/ticket-types/${qe.type}`).set(O).send({ quota: 3 }).expect(200);
    expect(await tt(qe.type)).toMatchObject({ quota: 3, held: 1, offered: 1 });
    await http.patch(`${base(qe.id)}/ticket-types/${qe.type}`).set(O).send({ quota: 1 }).expect(400); // below held + offered

    // Guest seats released to sale; seats newly assigned to a sold-out type
    const s = await seated('Guests');
    await http.post(`${base(s.id)}/seating/hold`).set(O).send({ seats: ['V:1:4'], label: 'Press' }).expect(201);
    await order(H.H, s.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3'] }).expect(201);
    await join(W.H, s.vip, 1).expect(201);
    await http.post(`${base(s.id)}/seating/release`).set(O).send({ seats: ['V:1:4'] }).expect(200);
    expect((await seat(s.id, 'V:1:4')).status).toBe('WAITLIST_HOLD');
    await expectSeatCounters(s.vip);
  });

  it('waitlist closes at sales end; remaining entries expire with an inbox message', async () => {
    const ev = await standing('Close', 1, 1);
    const [H, W1, W2, W3] = [await consumer(), await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    const j1 = await join(W1.H, ev.type, 1).expect(201);
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    const j3 = await join(W3.H, ev.type, 1).expect(201);
    await expireHold(prisma, pay, held.body.id);
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED' });

    await prisma.ticketType.update({ where: { id: ev.type }, data: { salesEndAt: new Date(Date.now() - 1000) } });
    await sweepWaitlist();
    for (const j of [j1, j2, j3]) expect(await entry(j.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    const inbox = await prisma.notification.findMany({ where: { userId: { in: [W2.id, W3.id] }, kind: 'waitlist_closed' } });
    expect(inbox).toHaveLength(2);
    expect(inbox[0].body).toMatch(/didn't become available/);
    expect(inbox[0].bodyMy).toBeTruthy();
    expect(await prisma.notification.count({ where: { userId: W1.id, kind: 'waitlist_closed' } })).toBe(0);
    // The reserve is released once nobody is in line
    expect(await tt(ev.type)).toMatchObject({ offered: 0 });
    await join(W2.H, ev.type, 1).expect(409);
  });

  it('offer notification: inbox always; SMS only when SMS enabled and waitlistSms on', async () => {
    const settings = app.get(SettingsService) as any;
    const sealed = settings.box.seal('SECRET-wl');
    const stored = jest.spyOn(settings, 'stored');
    const smsSetting = (enabled: boolean, waitlistSms?: boolean) =>
      stored.mockResolvedValue({ provider: 'smspoh', apiKey: 'KEY-wl', apiSecretSealed: sealed, senderId: 'Event360', enabled, testMode: true, ...(waitlistSms === undefined ? {} : { waitlistSms }) });

    async function offerTo(title: string) {
      const ev = await standing(title, 1, 1);
      const [H, W] = [await consumer(), await consumer()];
      const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
      const j = await join(W.H, ev.type, 1).expect(201);
      await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
      await sweepWaitlist();
      expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED' });
      const sms = () => smsCalls.filter((c) => c.to === `95${W.phone.slice(1)}`);
      return { W, sms, inbox: await prisma.notification.findMany({ where: { userId: W.id, kind: 'waitlist_offer' } }) };
    }

    // SMS on, waitlist SMS on by default: inbox and exactly one SMS
    smsSetting(true);
    const a = await offerTo('SmsOn');
    expect(a.inbox).toHaveLength(1);
    expect(a.inbox[0]).toMatchObject({ title: 'Tickets are available for you', titleMy: expect.any(String), bodyMy: expect.any(String) });
    expect(a.sms()).toHaveLength(1);
    expect(a.sms()[0].message).toMatch(/^Tickets for SmsOn .+ are available for you until .+\. Open Event 360\.$/);
    // Once per offer: later sweeps send nothing more
    await sweepWaitlist();
    expect(a.sms()).toHaveLength(1);

    // Waitlist SMS switched off by the admin: inbox only
    smsSetting(true, false);
    const b = await offerTo('SmsWlOff');
    expect(b.inbox).toHaveLength(1);
    expect(b.sms()).toHaveLength(0);

    // SMS disabled: inbox only
    smsSetting(false, true);
    const c = await offerTo('SmsOff');
    expect(c.inbox).toHaveLength(1);
    expect(c.sms()).toHaveLength(0);
    stored.mockResolvedValue({ provider: 'smspoh' });
  });

  it('a line paused while the event is re-reviewed keeps its entries and offers after it is published again', async () => {
    const ev = await standing('Paused', 2, 1);
    const [H1, H2, W1, W2, X] = [await consumer(), await consumer(), await consumer(), await consumer(), await consumer()];
    const h1 = await order(H1.H, ev.id, items(ev.type, 1)).expect(201);
    const h2 = await order(H2.H, ev.id, items(ev.type, 1)).expect(201);
    const j1 = await join(W1.H, ev.type, 1).expect(201);
    const j2 = await join(W2.H, ev.type, 1).expect(201);
    await http.post(`/v1/orders/${h1.body.id}/cancel`).set(H1.H).expect(200);
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED' });

    // Re-review: no joins, no new offers, nothing given back; the waiting entry and the live offer stay
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'SUBMITTED' } });
    expect((await join(X.H, ev.type, 1).expect(409)).body.reasonCode).toBe('WAITLIST_PAUSED');
    await http.post(`/v1/orders/${h2.body.id}/cancel`).set(H2.H).expect(200);
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 2 });
    expect(await wl.typesToOffer(new Date())).not.toContain(ev.type); // paused: not in the sweeper's batch
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'OFFERED' });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'WAITING' });
    expect(await tt(ev.type)).toMatchObject({ offered: 2 });
    // A live offer still runs to its normal expiry while paused
    await prisma.waitlistEntry.update({ where: { id: j1.body.entryId }, data: { offerExpiresAt: new Date(Date.now() - 1000) } });
    await sweepWaitlist();
    expect(await entry(j1.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'WAITING' });
    expect(await tt(ev.type)).toMatchObject({ offered: 2 });

    expect(await wl.typesToOffer(new Date())).not.toContain(ev.type);
    // Published again: the waiting entry gets its offer, the rest goes back on sale
    await publish(ev.id);
    expect(await wl.typesToOffer(new Date())).toContain(ev.type);
    await sweepWaitlist();
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 1 });

    // A cancelled event closes the line
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'CANCELLED' } });
    await sweepWaitlist();
    expect(await entry(j2.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    expect(await tt(ev.type)).toMatchObject({ offered: 0 });
  });

  it('a released checkout made from an offer gives the offer back until its original expiry', async () => {
    // Standing
    const ev = await standing('Lost', 2, 2);
    const [H, W, Y] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    const j = await join(W.H, ev.type, 2).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    const first = await entry(j.body.entryId);
    await join(Y.H, ev.type, 1).expect(201); // someone behind W
    const co = await order(W.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j.body.entryId }).expect(201);
    expect(await tt(ev.type)).toMatchObject({ held: 1, offered: 1 });
    await sweepWaitlist(); // the unused one goes to Y
    smsCalls.length = 0;
    await http.post(`/v1/orders/${co.body.id}/cancel`).set(W.H).expect(200);
    await app.get(NotifyService).idle();
    const back = await entry(j.body.entryId);
    expect(back).toMatchObject({ status: 'OFFERED', offeredQty: 1, orderId: co.body.id }); // the released order marks a reopened offer
    expect(back.offerExpiresAt!.getTime()).toBe(first.offerExpiresAt!.getTime());
    // An inbox notice (no SMS) that the tickets are still reserved
    const kept = await prisma.notification.findMany({ where: { userId: W.id, kind: 'waitlist_offer_reopened' } });
    expect(kept).toHaveLength(1);
    expect(kept[0].body).toMatch(new RegExp(`^Your tickets for Lost ${tag} are still reserved until .+\\.$`));
    expect(kept[0].bodyMy).toBeTruthy();
    expect(smsCalls.filter((c) => c.to === `95${W.phone.slice(1)}`)).toHaveLength(0);
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 2 });
    await sweepWaitlist(); // nothing changes hands
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 1 });
    const again = await order(W.H, ev.id, { ...items(ev.type, 1), waitlistEntryId: j.body.entryId }).expect(201);
    // After the original expiry the released ticket goes to the line instead
    await prisma.waitlistEntry.update({ where: { id: j.body.entryId }, data: { offerExpiresAt: new Date(Date.now() - 1000) } });
    await expireHold(prisma, pay, again.body.id);
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'PURCHASED' });
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 1 });

    // Seated: the released seats go back to the same offer
    const s = await seated('LostSeats');
    const hs = await order(H.H, s.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4'] }).expect(201);
    const js = await join(W.H, s.vip, 2).expect(201);
    await http.post(`/v1/orders/${hs.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    const cs = await order(W.H, s.id, { seats: ['V:1:1', 'V:1:2'], waitlistEntryId: js.body.entryId }).expect(201);
    await expireHold(prisma, pay, cs.body.id);
    expect(await entry(js.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    expect(await seat(s.id, 'V:1:1')).toMatchObject({ status: 'WAITLIST_HOLD', waitlistEntryId: js.body.entryId });
    expect(await seat(s.id, 'V:1:2')).toMatchObject({ status: 'WAITLIST_HOLD', waitlistEntryId: js.body.entryId });
    await expectSeatCounters(s.vip);
    await order(W.H, s.id, { seats: ['V:1:1', 'V:1:2'], waitlistEntryId: js.body.entryId }).expect(201);
  });

  it('a seated join that raced a release reserves the freed seats as soon as it commits', async () => {
    const ev = await seated('JoinRace');
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4'] }).expect(201);
    // The join takes the VIP counter row first and sees no AVAILABLE seat (the release hasn't committed); the
    // release read the line before the join committed and puts the seats on sale. The step after the join waits
    // here for the release to commit, then must reserve the seats.
    let cancel: Promise<unknown> | undefined;
    const svc = wl as any;
    const orig = svc.reserveAfterJoin.bind(wl);
    const spy = jest.spyOn(svc, 'reserveAfterJoin').mockImplementation(async (...a: unknown[]) => {
      await cancel;
      return orig(...a);
    });
    try {
      const [j, c] = await gated(
        prisma,
        (tx) => tx.$queryRaw`SELECT id FROM ticket_types WHERE id = ${ev.vip}::uuid FOR NO KEY UPDATE`,
        () => join(W.H, ev.vip, 2).then((r) => r),
        () => (cancel = http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).then((r) => r)) as Promise<request.Response>,
      );
      expect(j.status).toBe(201);
      expect((c as request.Response).status).toBe(200);
    } finally {
      spy.mockRestore();
    }
    const states = await prisma.eventSeat.findMany({ where: { eventId: ev.id }, orderBy: { seatKey: 'asc' }, select: { status: true } });
    expect(states.map((x) => x.status)).toEqual(['WAITLIST_HOLD', 'WAITLIST_HOLD', 'AVAILABLE', 'AVAILABLE']);
    await expectSeatCounters(ev.vip);
  });

  it('assignOffers only looks at types with something to offer', async () => {
    const ev = await standing('Starve', 1, 1);
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    await join(W.H, ev.type, 1).expect(201);
    expect(await wl.typesToOffer(new Date())).not.toContain(ev.type); // sold out, nothing reserved
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    expect(await wl.typesToOffer(new Date())).toContain(ev.type);
  });

  it('assignOffers never gives back a negative pool', async () => {
    const ev = await standing('Negative', 2, 1);
    const [H, W1, W2] = [await consumer(), await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    await order((await consumer()).H, ev.id, items(ev.type, 1)).expect(201);
    await join(W1.H, ev.type, 1).expect(201);
    await join(W2.H, ev.type, 1).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    // Corrupt the counter below the live offer: the sweep must not grow `offered` from it, and must warn
    await prisma.ticketType.update({ where: { id: ev.type }, data: { offered: 0 } });
    const warn = jest.spyOn((wl as any).logger, 'warn');
    await wl.assignOffers(new Date());
    expect(warn.mock.calls.some(([m]) => /pool/.test(String(m)))).toBe(true);
    warn.mockRestore();
    expect((await tt(ev.type)).offered).toBeGreaterThanOrEqual(0);
    expect((await tt(ev.type)).offered).toBeLessThanOrEqual(1);
  });

  it('a ticket type with reserved stock or a line cannot be deleted', async () => {
    const ev = await standing('Delete', 1, 1);
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    await join(W.H, ev.type, 1).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 1 });
    const r = await http.delete(`${base(ev.id)}/ticket-types/${ev.type}`).set(O).expect(409);
    expect(r.body.message).toMatch(/waitlist/i);
    // Only a waiting line, nothing sold, held or reserved
    const ev2 = await standing('Delete2', 1, 1);
    await prisma.waitlistEntry.create({ data: { ticketTypeId: ev2.type, userId: W.id, quantity: 1 } });
    await http.delete(`${base(ev2.id)}/ticket-types/${ev2.type}`).set(O).expect(409);
    // ...and once the line has ended it can go
    await prisma.waitlistEntry.updateMany({ where: { ticketTypeId: ev2.type }, data: { status: 'LEFT' } });
    await http.delete(`${base(ev2.id)}/ticket-types/${ev2.type}`).set(O).expect(200);
  });

  it('event_seats.waitlist_entry_id is indexed', async () => {
    const rows = await prisma.$queryRaw<{ indexdef: string }[]>`
      SELECT indexdef FROM pg_indexes WHERE tablename = 'event_seats' AND indexdef LIKE '%waitlist_entry_id%'`;
    expect(rows).toHaveLength(1);
    expect(rows[0].indexdef).toMatch(/WHERE \(waitlist_entry_id IS NOT NULL\)/);
  });

  it('a seated restore after a partial purchase gives back exactly the offered seats', async () => {
    const ev = await seated('Restore');
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4'] }).expect(201);
    const j = await join(W.H, ev.vip, 2).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    // One offered seat (V:1:1) plus one public seat (V:1:3); V:1:2 stays WAITLIST_HOLD pointing at the entry
    const co = await order(W.H, ev.id, { seats: ['V:1:1', 'V:1:3'], waitlistEntryId: j.body.entryId }).expect(201);
    expect(await seat(ev.id, 'V:1:2')).toMatchObject({ status: 'WAITLIST_HOLD', waitlistEntryId: j.body.entryId });
    await http.post(`/v1/orders/${co.body.id}/cancel`).set(W.H).expect(200);
    const mine = await prisma.eventSeat.findMany({ where: { waitlistEntryId: j.body.entryId, status: 'WAITLIST_HOLD' }, orderBy: { seatKey: 'asc' } });
    expect(mine.map((x) => x.seatKey)).toEqual(['V:1:1', 'V:1:2']);
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });
    expect(await seat(ev.id, 'V:1:3')).toMatchObject({ status: 'AVAILABLE', waitlistEntryId: null });
    await expectSeatCounters(ev.vip);

    // The line closes while the reopened offer is live: the buyer hears that tickets didn't become available
    await prisma.ticketType.update({ where: { id: ev.vip }, data: { salesEndAt: new Date(Date.now() - 1000) } });
    await sweepWaitlist();
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'EXPIRED' });
    expect(await prisma.notification.count({ where: { userId: W.id, kind: 'waitlist_closed' } })).toBe(1);
    await expectSeatCounters(ev.vip);
  });

  // ───────────── final review fixes ─────────────

  const payFor = async (H: Record<string, string>, orderId: string) => (await http.post(`/v1/orders/${orderId}/pay`).set(H).send({ provider: 'mock' }).expect(200)).body.payment.id as string;

  it('a re-join while paying for an offer is refused; an older re-join never wedges the release or the sweeper', async () => {
    const ev = await standing('Rejoin', 2, 4);
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    const j = await join(W.H, ev.type, 4).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2 }); // asked for 4, offered 2
    const co = await order(W.H, ev.id, { ...items(ev.type, 2), waitlistEntryId: j.body.entryId }).expect(201);
    // While that checkout is unpaid W can't join again (the release would reopen the offer)
    const re = await join(W.H, ev.type, 2).expect(409);
    expect(re.body.reasonCode).toBe('CHECKOUT_PENDING');

    // A re-join made before that check existed: cancelling skips the reopen, and the released stock is the pool
    const stray = await prisma.waitlistEntry.create({ data: { ticketTypeId: ev.type, userId: W.id, quantity: 2 } });
    await http.post(`/v1/orders/${co.body.id}/cancel`).set(W.H).expect(200);
    expect(await prisma.order.findUniqueOrThrow({ where: { id: co.body.id } })).toMatchObject({ status: 'CANCELLED' });
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'PURCHASED' });
    expect(await entry(stray.id)).toMatchObject({ status: 'WAITING' });
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 2 });
    await sweepWaitlist();
    expect(await entry(stray.id)).toMatchObject({ status: 'OFFERED', offeredQty: 2 });

    // The same through the sweeper: the hold expires while a stray re-join is active, and the sweep carries on
    const co2 = await order(W.H, ev.id, { ...items(ev.type, 2), waitlistEntryId: stray.id }).expect(201);
    const stray2 = await prisma.waitlistEntry.create({ data: { ticketTypeId: ev.type, userId: W.id, quantity: 1 } });
    await expireHold(prisma, pay, co2.body.id);
    expect(await prisma.order.findUniqueOrThrow({ where: { id: co2.body.id } })).toMatchObject({ status: 'EXPIRED' });
    expect(await entry(stray.id)).toMatchObject({ status: 'PURCHASED' });
    expect(await entry(stray2.id)).toMatchObject({ status: 'WAITING' });
    expect(await tt(ev.type)).toMatchObject({ held: 0, offered: 2 });
    // Once nothing is being paid for, W may join again as usual
    await prisma.waitlistEntry.update({ where: { id: stray2.id }, data: { status: 'LEFT' } });
    await join(W.H, ev.type, 1).expect(201);
  });

  it('one order or payment that fails to sweep does not stop the rest', async () => {
    const ev = await standing('Poison', 2, 1);
    const [P, Q] = [await consumer(), await consumer()];
    const bad = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const good = await order(Q.H, ev.id, items(ev.type, 1)).expect(201);
    const badPay = await payFor(P.H, bad.body.id);
    const goodPay = await payFor(Q.H, good.body.id);
    const old = new Date(Date.now() - 3 * 3600e3);
    await prisma.payment.updateMany({ where: { id: { in: [badPay, goodPay] } }, data: { status: 'PENDING', createdAt: old, lastCheckedAt: null } });
    await prisma.order.updateMany({ where: { id: { in: [bad.body.id, good.body.id] } }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
    const svc = pay as any;
    const release = svc.releaseHold.bind(pay);
    const apply = svc.applyStatus.bind(pay);
    const r1 = jest.spyOn(svc, 'releaseHold').mockImplementation((id: unknown, to: unknown) => (id === bad.body.id ? Promise.reject(new Error('poisoned order')) : release(id, to)));
    const r2 = jest.spyOn(svc, 'applyStatus').mockImplementation((id: unknown, st: unknown) => (id === badPay ? Promise.reject(new Error('poisoned payment')) : apply(id, st)));
    const warn = jest.spyOn(svc.logger, 'warn');
    try {
      for (let i = 0; i < 50; i++) {
        await expect(pay.sweep()).resolves.toBeDefined();
        const [o, p] = await Promise.all([prisma.order.findUniqueOrThrow({ where: { id: good.body.id } }), prisma.payment.findUniqueOrThrow({ where: { id: goodPay } })]);
        if (o.status !== 'PENDING_PAYMENT' && p.status !== 'PENDING') break;
      }
    } finally {
      r1.mockRestore();
      r2.mockRestore();
    }
    expect(await prisma.order.findUniqueOrThrow({ where: { id: good.body.id } })).toMatchObject({ status: 'EXPIRED' });
    expect(await prisma.payment.findUniqueOrThrow({ where: { id: goodPay } })).toMatchObject({ status: 'EXPIRED' });
    expect(await prisma.order.findUniqueOrThrow({ where: { id: bad.body.id } })).toMatchObject({ status: 'PENDING_PAYMENT' });
    expect(warn.mock.calls.some(([m]) => /poisoned order/.test(String(m)))).toBe(true);
    expect(warn.mock.calls.some(([m]) => /poisoned payment/.test(String(m)))).toBe(true);
    warn.mockRestore();
    (pay as any).skippedHolds.clear(); // its 10-minute skip, so it can expire now
    await expireHold(prisma, pay, bad.body.id); // not poisoned any more
  });

  it('a poisoned expired hold is skipped for a while after two failures and never starves the others', async () => {
    const ev = await standing('Starve', 2, 1);
    const [P, Q] = [await consumer(), await consumer()];
    const bad = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const good = await order(Q.H, ev.id, items(ev.type, 1)).expect(201);
    // Both long expired, the poisoned one first: oldest holds are swept first
    await prisma.order.update({ where: { id: bad.body.id }, data: { holdExpiresAt: new Date(Date.now() - 3600e3 - 1000) } });
    await prisma.order.update({ where: { id: good.body.id }, data: { holdExpiresAt: new Date(Date.now() - 3600e3) } });
    const svc = pay as any;
    const release = svc.releaseHold.bind(pay);
    const r1 = jest.spyOn(svc, 'releaseHold').mockImplementation((id: unknown, to: unknown) => (id === bad.body.id ? Promise.reject(new Error('poisoned order')) : release(id, to)));
    const warn = jest.spyOn(svc.logger, 'warn');
    const triesOfBad = () => r1.mock.calls.filter(([id]) => id === bad.body.id).length;
    try {
      for (let i = 0; i < 50; i++) {
        await pay.sweep();
        if ((await prisma.order.findUniqueOrThrow({ where: { id: good.body.id } })).status !== 'PENDING_PAYMENT') break;
      }
      expect(await prisma.order.findUniqueOrThrow({ where: { id: good.body.id } })).toMatchObject({ status: 'EXPIRED' });
      expect(triesOfBad()).toBe(1);
      expect(warn.mock.calls.some(([m]) => /poisoned order/.test(String(m)))).toBe(true);
      // One failure: tried again on the next pass; a second failure in a row: skipped from then on
      expect(await prisma.order.findUniqueOrThrow({ where: { id: bad.body.id } })).toMatchObject({ status: 'PENDING_PAYMENT' });
      await pay.sweep();
      expect(triesOfBad()).toBe(2);
      await pay.sweep();
      expect(triesOfBad()).toBe(2);
      // ...for 10 minutes, then it is tried again (its skip moved back rather than sweeping with a future clock,
      // which would expire other suites' holds running in parallel)
      expect(svc.skippedHolds.get(bad.body.id)).toBeGreaterThan(Date.now() + 9 * 60e3);
      svc.skippedHolds.set(bad.body.id, Date.now() - 1);
      await pay.sweep();
      expect(triesOfBad()).toBe(3);
    } finally {
      r1.mockRestore();
      warn.mockRestore();
    }
    svc.skippedHolds.clear();
    await expireHold(prisma, pay, bad.body.id);
  });

  it('a payment the provider reports as paid is never expired, even when settling it keeps failing', async () => {
    const ev = await standing('PaidStuck', 2, 1);
    const P = await consumer();
    const o = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const payId = await payFor(P.H, o.body.id);
    await expireHold(prisma, pay, o.body.id);
    // The wallet took the money but the callback was lost, long ago; the order already has an unrelated note
    await pay.mock.recordState(payId, 'SUCCEEDED');
    await prisma.order.update({ where: { id: o.body.id }, data: { reviewNote: 'Earlier note' } });
    await prisma.payment.update({ where: { id: payId }, data: { status: 'PENDING', createdAt: new Date(Date.now() - 3 * 3600e3), lastCheckedAt: null } });
    const svc = pay as any;
    const apply = svc.applyStatus.bind(pay);
    const r = jest.spyOn(svc, 'applyStatus').mockImplementation((id: unknown, st: unknown, ...rest: unknown[]) =>
      id === payId && st === 'SUCCEEDED' ? Promise.reject(new Error('settle broke')) : apply(id, st, ...rest),
    );
    const checkedPass = async () => {
      await prisma.payment.update({ where: { id: payId }, data: { lastCheckedAt: null } });
      for (let i = 0; i < 50; i++) {
        await pay.sweep();
        if ((await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).lastCheckedAt) return;
      }
      throw new Error('payment was never checked');
    };
    const note = `Provider reports paid (ref mock_${payId}) but settling failed: check`;
    try {
      await checkedPass();
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).toMatchObject({ status: 'PENDING' });
      expect(await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).toMatchObject({ needsReview: true, reviewNote: `Earlier note\n${note}` });
      // Retried on a later pass: still not expired, and the note is not repeated
      await checkedPass();
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).toMatchObject({ status: 'PENDING' });
      expect(await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).toMatchObject({ needsReview: true, reviewNote: `Earlier note\n${note}` });
    } finally {
      r.mockRestore();
    }
    // Once settling works again, a later pass settles it; the note says so, and the earlier note keeps it in review
    await checkedPass();
    expect(await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).toMatchObject({ status: 'SUCCEEDED' });
    const paid = await prisma.order.findUniqueOrThrow({ where: { id: o.body.id }, include: { tickets: true } });
    expect(paid.status).toBe('PAID');
    expect(paid.tickets).toHaveLength(1);
    expect(paid.needsReview).toBe(true);
    expect(paid.reviewNote).toMatch(new RegExp(`^Earlier note\n${note.replace(/[()]/g, '\\$&')}\nsettled later \\(\\d{4}-\\d\\d-\\d\\dT[^)]+\\)$`));
  });

  /** A paid order whose 3-hour-old payment the wallet reports as paid (callback lost); the hold long expired. */
  async function stuckPaid(title: string) {
    const ev = await standing(title, 2, 1);
    const P = await consumer();
    const o = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const payId = await payFor(P.H, o.body.id);
    await expireHold(prisma, pay, o.body.id);
    await pay.mock.recordState(payId, 'SUCCEEDED');
    await prisma.payment.update({ where: { id: payId }, data: { status: 'PENDING', createdAt: new Date(Date.now() - 3 * 3600e3), lastCheckedAt: null } });
    const checkedPass = async () => {
      await prisma.payment.update({ where: { id: payId }, data: { lastCheckedAt: null } });
      for (let i = 0; i < 50; i++) {
        await pay.sweep();
        if ((await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).lastCheckedAt) return;
      }
      throw new Error('payment was never checked');
    };
    return { orderId: o.body.id as string, payId, checkedPass };
  }

  it('settling a stuck paid order later clears its review when that was the only reason', async () => {
    const { orderId, payId, checkedPass } = await stuckPaid('PaidStuck2');
    const svc = pay as any;
    const apply = svc.applyStatus.bind(pay);
    const r = jest.spyOn(svc, 'applyStatus').mockImplementation((id: unknown, st: unknown, ...rest: unknown[]) =>
      id === payId && st === 'SUCCEEDED' ? Promise.reject(new Error('settle broke')) : apply(id, st, ...rest),
    );
    try {
      await checkedPass();
    } finally {
      r.mockRestore();
    }
    expect(await prisma.order.findUniqueOrThrow({ where: { id: orderId } })).toMatchObject({ needsReview: true });
    await checkedPass();
    const o = await prisma.order.findUniqueOrThrow({ where: { id: orderId } });
    expect(o).toMatchObject({ status: 'PAID', needsReview: false });
    expect(o.reviewNote).toMatch(/^Provider reports paid \(ref mock_[0-9a-f-]+\) but settling failed: check\nsettled later \(.+\)$/);
  });

  it('a stuck-paid flag is not raised when the payment did settle (the error came after)', async () => {
    const { orderId, payId, checkedPass } = await stuckPaid('PaidStuck3');
    const svc = pay as any;
    const apply = svc.applyStatus.bind(pay);
    const r = jest.spyOn(svc, 'applyStatus').mockImplementation(async (id: unknown, st: unknown, ...rest: unknown[]) => {
      await apply(id, st, ...rest);
      if (id === payId && st === 'SUCCEEDED') throw new Error('after the commit');
    });
    try {
      await checkedPass();
    } finally {
      r.mockRestore();
    }
    expect(await prisma.payment.findUniqueOrThrow({ where: { id: payId } })).toMatchObject({ status: 'SUCCEEDED' });
    expect(await prisma.order.findUniqueOrThrow({ where: { id: orderId } })).toMatchObject({ status: 'PAID', needsReview: false, reviewNote: null });
  });

  it('a late payment for sold-out tickets keeps the order\'s earlier review notes', async () => {
    const ev = await standing('LateSoldOut', 1, 1);
    const [P, Q] = [await consumer(), await consumer()];
    const o = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const payId = await payFor(P.H, o.body.id);
    await expireHold(prisma, pay, o.body.id);
    await order(Q.H, ev.id, items(ev.type, 1)).expect(201); // the ticket is gone
    await prisma.order.update({ where: { id: o.body.id }, data: { needsReview: true, reviewNote: 'Earlier note' } });
    const cb = pay.mock.callbackFor(payId, 'SUCCEEDED', 5_000n);
    await http.post('/v1/payments/webhook/mock').set('x-mock-signature', cb.signature).send(cb.body).expect(200);
    expect(await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).toMatchObject({
      status: 'PAID',
      needsReview: true,
      reviewNote: 'Earlier note\nPaid after the hold expired and the tickets sold out: refund the buyer',
    });
  });

  it('the reconciler checks the least recently checked payments first', async () => {
    // 300 due payments checked five minutes ago fill several batches; one never checked must be in the next pass
    // (the fillers are older than it, so by creation time they would come first)
    const fill = await prisma.payment.createManyAndReturn({
      data: Array.from({ length: 300 }, () => ({
        provider: 'MOCK' as const, purpose: 'SUBSCRIPTION', amountMmk: 1n, status: 'PENDING' as const,
        createdAt: new Date(Date.now() - 90 * 60e3), lastCheckedAt: new Date(Date.now() - 300e3),
      })),
      select: { id: true },
    });
    const ev = await standing('Recon', 2, 1);
    const P = await consumer();
    const o = await order(P.H, ev.id, items(ev.type, 1)).expect(201);
    const fresh = await payFor(P.H, o.body.id);
    await prisma.payment.update({ where: { id: fresh }, data: { status: 'PENDING', createdAt: new Date(Date.now() - 30 * 60e3), lastCheckedAt: null } });
    try {
      await pay.sweep();
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: fresh } })).lastCheckedAt).not.toBeNull();
    } finally {
      await prisma.payment.deleteMany({ where: { id: { in: fill.map((f) => f.id) } } });
    }
  });

  it('the per-person limit holds when an earlier order settles between the checks', async () => {
    const ev = await standing('Limit', 10, 2);
    const U = await consumer();
    const a = await order(U.H, ev.id, items(ev.type, 1)).expect(201);
    const payId = await payFor(U.H, a.body.id);
    // Order A settles right after B's checkout has read what the buyer holds (tickets: none yet)
    const original = prisma.$transaction.bind(prisma);
    let fired = false;
    const settleA = async () => {
      if (fired) return;
      fired = true;
      await (pay as any).applyStatus(payId, 'SUCCEEDED');
    };
    const spy = jest.spyOn(prisma, '$transaction').mockImplementationOnce((async (fn: any, opts: any) =>
      (original as any)((tx: any) => {
        const wrapped = new Proxy(tx, {
          get(t, k) {
            if (k === 'ticket') return new Proxy(t.ticket, { get: (tt, m) => (m === 'count' ? async (...a: unknown[]) => { const n = await tt.count(...a); await settleA(); return n; } : tt[m]) });
            if (k === '$queryRaw') return async (...a: any[]) => { const r = await t.$queryRaw(...a); if (String(a[0]?.join?.('') ?? a[0]).includes('tickets')) await settleA(); return r; };
            const v = t[k];
            return typeof v === 'function' ? v.bind(t) : v;
          },
        });
        return fn(wrapped);
      }, opts)) as any);
    try {
      await expect(pay.createOrder(U.id, ev.id, [{ ticketTypeId: ev.type, quantity: 2 }])).rejects.toMatchObject({ status: 409 });
    } finally {
      spy.mockRestore();
    }
    expect(fired).toBe(true);
    expect(await prisma.order.findUniqueOrThrow({ where: { id: a.body.id } })).toMatchObject({ status: 'PAID' });
    expect(await prisma.ticket.count({ where: { holderUserId: U.id, ticketTypeId: ev.type } })).toBe(1);
  });

  it('a join and a settle for the same buyer in parallel do not deadlock', async () => {
    const ev = await standing('JoinSettle', 1, 2);
    const U = await consumer();
    const o = await order(U.H, ev.id, items(ev.type, 1)).expect(201);
    const payId = await payFor(U.H, o.body.id);
    const cb = pay.mock.callbackFor(payId, 'SUCCEEDED', 5_000n);
    // The join takes the buyer row, then waits for the counter row the settle holds; the settle's ticket insert
    // takes a KEY SHARE on the same buyer row through the foreign key
    const [j, s] = await gated(
      prisma,
      (tx) => tx.$queryRaw`SELECT id FROM users WHERE id = ${U.id}::uuid FOR UPDATE`,
      () => join(U.H, ev.type, 1).then((r) => r),
      () => http.post('/v1/payments/webhook/mock').set('x-mock-signature', cb.signature).send(cb.body).then((r) => r),
    );
    expect(s.status).toBe(200);
    expect(j.status).toBe(201);
    expect(await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).toMatchObject({ status: 'PAID' });
    expect(await tt(ev.type)).toMatchObject({ sold: 1, held: 0 });
  });

  it('a join waits for the buyer row (as checkout does) before the counter row', async () => {
    const ev = await standing('JoinLock', 1, 2);
    const [H, W] = [await consumer(), await consumer()];
    await order(H.H, ev.id, items(ev.type, 1)).expect(201);
    const gate = await lockGate(prisma, (tx) => tx.$queryRaw`SELECT id FROM users WHERE id = ${W.id}::uuid FOR UPDATE`);
    let j: Promise<request.Response> | undefined;
    try {
      j = join(W.H, ev.type, 1).then((r) => r);
      await queued(prisma, [gate.pid]);
      // ...and holds no counter-row lock while it waits: the type's row is free
      await prisma.$transaction((tx) => tx.$queryRaw`SELECT id FROM ticket_types WHERE id = ${ev.type}::uuid FOR NO KEY UPDATE NOWAIT`);
    } finally {
      gate.release();
      await gate.done;
    }
    expect((await j!).status).toBe(201);
  });

  it('a late payment for a reopened offer takes the offer\'s reserved stock and marks it purchased', async () => {
    // Standing
    const ev = await standing('LateReopen', 2, 2);
    const [H, W] = [await consumer(), await consumer()];
    const held = await order(H.H, ev.id, items(ev.type, 2)).expect(201);
    const j = await join(W.H, ev.type, 2).expect(201);
    await http.post(`/v1/orders/${held.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    const co = await order(W.H, ev.id, { ...items(ev.type, 2), waitlistEntryId: j.body.entryId }).expect(201);
    const p = await payFor(W.H, co.body.id);
    await http.post(`/v1/orders/${co.body.id}/cancel`).set(W.H).expect(200);
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'OFFERED', offeredQty: 2, orderId: co.body.id });
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 0, offered: 2 });
    await pay.settle(p); // the money arrives anyway
    const paid = await prisma.order.findUniqueOrThrow({ where: { id: co.body.id }, include: { tickets: true } });
    expect(paid).toMatchObject({ status: 'PAID', needsReview: false });
    expect(paid.tickets).toHaveLength(2);
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 2, offered: 0 });
    expect(await entry(j.body.entryId)).toMatchObject({ status: 'PURCHASED', orderId: co.body.id });
    await sweepWaitlist();
    expect(await tt(ev.type)).toMatchObject({ held: 0, sold: 2, offered: 0 });

    // Seated: the entry's WAITLIST_HOLD seats are sold
    const s = await seated('LateReopenSeats');
    const hs = await order(H.H, s.id, { seats: ['V:1:1', 'V:1:2', 'V:1:3', 'V:1:4'] }).expect(201);
    const js = await join(W.H, s.vip, 2).expect(201);
    await http.post(`/v1/orders/${hs.body.id}/cancel`).set(H.H).expect(200);
    await sweepWaitlist();
    const cs = await order(W.H, s.id, { seats: ['V:1:1', 'V:1:2'], waitlistEntryId: js.body.entryId }).expect(201);
    const ps = await payFor(W.H, cs.body.id);
    await http.post(`/v1/orders/${cs.body.id}/cancel`).set(W.H).expect(200);
    expect(await entry(js.body.entryId)).toMatchObject({ status: 'OFFERED', orderId: cs.body.id });
    await pay.settle(ps);
    const seatedPaid = await prisma.order.findUniqueOrThrow({ where: { id: cs.body.id }, include: { tickets: true } });
    expect(seatedPaid).toMatchObject({ status: 'PAID', needsReview: false });
    expect(seatedPaid.tickets).toHaveLength(2);
    expect(await seat(s.id, 'V:1:1')).toMatchObject({ status: 'SOLD', waitlistEntryId: null });
    expect(await seat(s.id, 'V:1:2')).toMatchObject({ status: 'SOLD', waitlistEntryId: null });
    expect(await entry(js.body.entryId)).toMatchObject({ status: 'PURCHASED', orderId: cs.body.id });
    await expectSeatCounters(s.vip);
  });
});
