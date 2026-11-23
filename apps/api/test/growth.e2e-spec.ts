/**
 * Organizer growth tools over HTTP against a real PostgreSQL (mock pay provider). Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { NotifyService } from '../src/modules/notifications/notify.service';
import { PaymentsService } from '../src/modules/payments/payments.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';
import { expireHold } from './expire-hold';
import { lockGate } from './lock-gate';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Organizer growth', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  let svc: PaymentsService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  let A: Record<string, string>, O: Record<string, string>, orgId: string, catId: string;

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
  /** A published event with one paid type (10,000) and one free type. */
  async function newEvent(name: string, maxPer = 4) {
    const start = new Date(Date.now() + 7 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: catId, title: `${name} ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    const eventId = ev.body.id as string;
    const base = `/v1/organizations/${orgId}/events/${eventId}`;
    const add = (b: object) => http.post(`${base}/ticket-types`).set(O).send(b).expect(201);
    const paid = (await add({ name: 'Standard', priceMmk: 10_000, quota: 40, maxPerOrder: maxPer })).body.id as string;
    const free = (await add({ name: 'Kids', priceMmk: 0, quota: 40, maxPerOrder: maxPer })).body.id as string;
    await http.post(`${base}/submit`).set(O).expect(200);
    return { eventId, base, paid, free, slug: ev.body.slug as string };
  }
  const payMock = async (h: Record<string, string>, orderId: string) => {
    const p = await http.post(`/v1/orders/${orderId}/pay`).set(h).send({ provider: 'MOCK' }).expect(200);
    return new URL(p.body.payment.action.url);
  };
  const confirm = (url: URL) => http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t') }).expect(201);
  const inHours = (h: number) => new Date(Date.now() + h * 3600e3).toISOString();

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.PUBLIC_API_URL = 'https://api.example';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    svc = app.get(PaymentsService);

    const adm = await app.get(AuthService).createInvitation({ email: `adm-g-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Growth Org ${tag}`, slug: `growth-${tag}`, ownerEmail: `own-g-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    await http.patch(`/v1/admin/organizations/${orgId}/kyc`).set(A).send({ status: 'APPROVED' }).expect(200);
    catId = (await http.get('/v1/categories').expect(200)).body[0].children[0].id;
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('price steps change the public price and the order price', async () => {
    const e = await newEvent('Steps');
    await http.post(`/v1/organizations/${orgId}/events/${e.eventId}/promo-codes`).set(O).send({ code: 'TEN', kind: 'PERCENT', value: 10 }).expect(201);
    const t1 = inHours(1);
    const t2 = inHours(48);
    const put = await http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [{ startsAt: t2, priceMmk: 18_000 }, { startsAt: t1, priceMmk: 14_000 }] }).expect(200);
    expect(put.body.steps.map((s: any) => s.priceMmk)).toEqual([14_000, 18_000]);

    const std = (body: any) => body.ticketTypes.find((t: any) => t.id === e.paid);
    let pub = await http.get(`/v1/events/${e.slug}`).expect(200);
    expect(std(pub.body)).toMatchObject({ priceMmk: 10_000, basePriceMmk: 10_000, nextPrice: { priceMmk: 14_000 } });
    expect(new Date(std(pub.body).nextPrice.startsAt).toISOString()).toBe(t1);
    expect(pub.body.minPriceMmk).toBe(0);

    const buyer = await consumer();
    const before = await http.post(`/v1/events/${e.eventId}/orders`).set(buyer).send({ items: [{ ticketTypeId: e.paid, quantity: 2 }] }).expect(201);
    expect(before.body).toMatchObject({ subtotalMmk: 20_000, totalMmk: 20_000 });

    // The first step starts now (history moved in the DB; the API only accepts future dates)
    await prisma.ticketPriceStep.updateMany({ where: { ticketTypeId: e.paid, startsAt: new Date(t1) }, data: { startsAt: new Date(Date.now() - 1000) } });
    pub = await http.get(`/v1/events/${e.slug}`).expect(200);
    expect(std(pub.body)).toMatchObject({ priceMmk: 14_000, basePriceMmk: 10_000, nextPrice: { priceMmk: 18_000 } });
    const list = await http.get('/v1/events').query({ q: `Steps ${tag}` }).expect(200);
    expect(std(list.body.items[0])).toMatchObject({ priceMmk: 14_000 });
    const pv = await http.post(`/v1/events/${e.eventId}/promo-check`).set(buyer).send({ code: 'TEN', items: [{ ticketTypeId: e.paid, quantity: 2 }] }).expect(200);
    expect(pv.body).toMatchObject({ valid: true, subtotalMmk: 28_000, discountMmk: 2_800, totalMmk: 25_200 });
    const after = await http.post(`/v1/events/${e.eventId}/orders`).set(buyer).send({ items: [{ ticketTypeId: e.paid, quantity: 2 }], promoCode: 'TEN' }).expect(201);
    expect(after.body).toMatchObject({ subtotalMmk: 28_000, discountMmk: 2_800, totalMmk: 25_200 });
    expect((await prisma.orderItem.findFirstOrThrow({ where: { orderId: after.body.id } })).unitPriceMmk).toBe(14_000n);

    // Seat colours stay by the base price: the type list is still ordered by it
    expect((await prisma.ticketType.findUniqueOrThrow({ where: { id: e.paid } })).priceMmk).toBe(10_000n);
  });

  it('price is frozen for an order created before a step, also on late payment', async () => {
    const e = await newEvent('Frozen');
    const t1 = inHours(1);
    await http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [{ startsAt: t1, priceMmk: 25_000 }] }).expect(200);
    const buyer = await consumer();
    const o = await http.post(`/v1/events/${e.eventId}/orders`).set(buyer).send({ items: [{ ticketTypeId: e.paid, quantity: 1 }] }).expect(201);
    expect(o.body.totalMmk).toBe(10_000);
    const url = await payMock(buyer, o.body.id);
    // The step passes during the hold, then the hold expires; the money arrives late
    await prisma.ticketPriceStep.updateMany({ where: { ticketTypeId: e.paid }, data: { startsAt: new Date(Date.now() - 5000) } });
    await expireHold(prisma, svc, o.body.id);
    expect((await http.get(`/v1/orders/${o.body.id}`).set(buyer)).body.status).toBe('EXPIRED');
    await confirm(url);
    const done = await prisma.order.findUniqueOrThrow({ where: { id: o.body.id }, include: { items: true, tickets: true } });
    expect(done).toMatchObject({ status: 'PAID', subtotalMmk: 10_000n, totalMmk: 10_000n });
    expect(done.items[0].unitPriceMmk).toBe(10_000n);
    expect(done.tickets).toHaveLength(1);
    // A new order now pays the step price
    const o2 = await http.post(`/v1/events/${e.eventId}/orders`).set(buyer).send({ items: [{ ticketTypeId: e.paid, quantity: 1 }] }).expect(201);
    expect(o2.body.totalMmk).toBe(25_000);
  });

  it('price-steps endpoint rejects past dates, free types, and removing a step in effect', async () => {
    const e = await newEvent('Reject');
    const url = `${e.base}/ticket-types/${e.paid}/price-steps`;
    const buyer = await consumer();
    await http.put(url).set(buyer).send({ steps: [] }).expect(403);
    await http.put(url).set(O).send({ steps: [{ startsAt: inHours(-1), priceMmk: 12_000 }] }).expect(400);
    await http.put(url).set(O).send({ steps: [{ startsAt: inHours(2), priceMmk: 12_000 }, { startsAt: inHours(2), priceMmk: 13_000 }] }).expect(400);
    await http.put(url).set(O).send({ steps: [{ startsAt: inHours(2), priceMmk: 0 }] }).expect(400);
    await http.put(`${e.base}/ticket-types/${e.free}/price-steps`).set(O).send({ steps: [{ startsAt: inHours(2), priceMmk: 5_000 }] }).expect(400);
    expect(await prisma.ticketPriceStep.count({ where: { ticketTypeId: { in: [e.paid, e.free] } } })).toBe(0);

    // Future steps are replaced as a whole
    const a = inHours(2), b = inHours(5), c = inHours(9);
    await http.put(url).set(O).send({ steps: [{ startsAt: a, priceMmk: 12_000 }, { startsAt: b, priceMmk: 15_000 }] }).expect(200);
    const r = await http.put(url).set(O).send({ steps: [{ startsAt: a, priceMmk: 12_500 }, { startsAt: c, priceMmk: 20_000 }] }).expect(200);
    expect(r.body.steps.map((s: any) => s.priceMmk)).toEqual([12_500, 20_000]);
    await http.put(url).set(O).send({ steps: [] }).expect(200);
    expect(await prisma.ticketPriceStep.count({ where: { ticketTypeId: e.paid } })).toBe(0);

    // A step in effect stays: it can't be dropped, changed or re-dated, but it may be sent back unchanged
    await http.put(url).set(O).send({ steps: [{ startsAt: a, priceMmk: 12_000 }, { startsAt: c, priceMmk: 20_000 }] }).expect(200);
    const started = new Date(Date.now() - 60_000);
    await prisma.ticketPriceStep.updateMany({ where: { ticketTypeId: e.paid, startsAt: new Date(a) }, data: { startsAt: started } });
    await http.put(url).set(O).send({ steps: [{ startsAt: c, priceMmk: 20_000 }] }).expect(400);
    await http.put(url).set(O).send({ steps: [] }).expect(400);
    await http.put(url).set(O).send({ steps: [{ startsAt: started.toISOString(), priceMmk: 11_000 }] }).expect(400);
    const keep = await http.put(url).set(O).send({ steps: [{ startsAt: started.toISOString(), priceMmk: 12_000 }, { startsAt: inHours(30), priceMmk: 22_000 }] }).expect(200);
    expect(keep.body.steps.map((s: any) => s.priceMmk)).toEqual([12_000, 22_000]);
    // and a type with steps can't be made free
    await http.patch(`${e.base}/ticket-types/${e.paid}`).set(O).send({ priceMmk: 0 }).expect(400);
  });

  it('reports use the price actually charged: dashboard, attendee CSV, ticket view, organizer type list', async () => {
    const e = await newEvent('Reports');
    await http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [{ startsAt: inHours(1), priceMmk: 14_000 }] }).expect(200);
    const b1 = await consumer();
    const b2 = await consumer();
    const buy = async (h: Record<string, string>) => {
      const o = await http.post(`/v1/events/${e.eventId}/orders`).set(h).send({ items: [{ ticketTypeId: e.paid, quantity: 1 }] }).expect(201);
      await confirm(await payMock(h, o.body.id));
      return o.body.id as string;
    };
    await buy(b1);
    await prisma.ticketPriceStep.updateMany({ where: { ticketTypeId: e.paid }, data: { startsAt: new Date(Date.now() - 1000) } });
    await buy(b2);
    await http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [] }).expect(400); // in effect now
    await http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [{ startsAt: (await prisma.ticketPriceStep.findFirstOrThrow({ where: { ticketTypeId: e.paid } })).startsAt.toISOString(), priceMmk: 14_000 }, { startsAt: inHours(30), priceMmk: 20_000 }] }).expect(200);

    const d = await http.get(`${e.base}/dashboard`).set(O).expect(200);
    expect(d.body.ticketTypes.find((t: any) => t.id === e.paid)).toMatchObject({ priceMmk: 14_000, basePriceMmk: 10_000, nextPrice: { priceMmk: 20_000 } });
    const sales = await http.get(`${e.base}/sales`).set(O).expect(200);
    expect(sales.body.ticketTypes.find((t: any) => t.id === e.paid)).toMatchObject({ priceMmk: 14_000, basePriceMmk: 10_000, revenueMmk: 24_000, nameMy: null });
    await prisma.ticketType.update({ where: { id: e.paid }, data: { nameMy: 'သာမန်' } });
    expect((await http.get(`${e.base}/sales`).set(O).expect(200)).body.ticketTypes.find((t: any) => t.id === e.paid)).toMatchObject({ nameMy: 'သာမန်' });
    const csv = await http.get(`${e.base}/attendees.csv`).set(O).expect(200);
    const prices = csv.text.replace(/^\uFEFF/, '').split('\r\n').slice(1).filter(Boolean).map((l: string) => l.replace(/"/g, '').split(',')[4]).sort();
    expect(prices).toEqual(['10000', '14000']);
    const t1 = (await http.get('/v1/me/tickets').set(b1).expect(200)).body[0];
    const t2 = (await http.get('/v1/me/tickets').set(b2).expect(200)).body[0];
    expect(t1.ticketType.priceMmk).toBe(10_000);
    expect(t2.ticketType.priceMmk).toBe(14_000);
  });

  it('parallel price-steps updates never leave duplicate or in-effect-violating state', async () => {
    const e = await newEvent('Race');
    const url = `${e.base}/ticket-types/${e.paid}/price-steps`;
    const at = inHours(3);
    const rs = await Promise.all([1, 2, 3, 4].map((i) => http.put(url).set(O).send({ steps: [{ startsAt: at, priceMmk: 11_000 + i }] })));
    expect(rs.every((r) => r.status === 200 || r.status === 409)).toBe(true);
    expect(rs.some((r) => r.status === 200)).toBe(true);
    expect(await prisma.ticketPriceStep.count({ where: { ticketTypeId: e.paid } })).toBe(1);
  });

  it('a price-steps edit does not wait for checkouts that only key-share the type row', async () => {
    const e = await newEvent('StepLock');
    // A checkout inserting an order item holds KEY SHARE on the type row (its foreign key) until it commits
    const gate = await lockGate(prisma, (tx) => tx.$queryRaw`SELECT id FROM ticket_types WHERE id = ${e.paid}::uuid FOR KEY SHARE`);
    try {
      const put = http.put(`${e.base}/ticket-types/${e.paid}/price-steps`).set(O).send({ steps: [{ startsAt: inHours(5), priceMmk: 12_000 }] }).then((r) => r.status);
      const slow = new Promise((r) => setTimeout(() => r('blocked'), 3000));
      expect(await Promise.race([put, slow])).toBe(200);
    } finally {
      gate.release();
      await gate.done;
    }
  });

  // ───────────── group discounts ─────────────

  const tiersOf = (e: { base: string }, tiers: { minQuantity: number; percentBp: number }[]) => http.put(`${e.base}/group-discounts`).set(O).send({ tiers });
  const order = (h: Record<string, string>, e: { eventId: string }, items: { ticketTypeId: string; quantity: number }[], promoCode?: string) =>
    http.post(`/v1/events/${e.eventId}/orders`).set(h).send({ items, ...(promoCode ? { promoCode } : {}) });
  const promoFor = (e: { base: string }, body: object) => http.post(`${e.base}/promo-codes`).set(O).send(body).expect(201);
  const promoUsed = async (eventId: string, code: string) => (await prisma.promoCode.findUniqueOrThrow({ where: { eventId_code: { eventId, code } } })).used;

  it('group discount applies on paid quantity', async () => {
    const e = await newEvent('Group', 20);
    // tier management: replace all, validated, public
    expect((await http.get(`${e.base}/group-discounts`).set(O).expect(200)).body).toEqual({ tiers: [] });
    await tiersOf(e, [{ minQuantity: 1, percentBp: 1000 }]).expect(400);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 9500 }]).expect(400);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 99 }]).expect(400);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }, { minQuantity: 5, percentBp: 1500 }]).expect(400);
    await tiersOf(e, [{ minQuantity: 10, percentBp: 1500 }, { minQuantity: 5, percentBp: 1000 }]).expect(200);
    const put = await tiersOf(e, [{ minQuantity: 10, percentBp: 1500 }, { minQuantity: 5, percentBp: 1000 }]).expect(200);
    expect(put.body.tiers).toEqual([{ minQuantity: 5, percentBp: 1000 }, { minQuantity: 10, percentBp: 1500 }]);
    await http.put(`${e.base}/group-discounts`).set(await consumer()).send({ tiers: [] }).expect(403);
    expect((await http.get(`/v1/events/${e.slug}`).expect(200)).body.groupDiscounts).toEqual(put.body.tiers);

    // 3 paid + 2 free = 5 tickets, but only 3 count: no discount
    const b1 = await consumer();
    const low = await order(b1, e, [{ ticketTypeId: e.paid, quantity: 3 }, { ticketTypeId: e.free, quantity: 2 }]).expect(201);
    expect(low.body).toMatchObject({ subtotalMmk: 30_000, discountMmk: 0, totalMmk: 30_000, discountSource: null });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: low.body.id } })).groupDiscountBp).toBeNull();

    // 5 paid → 10%; 10 paid → 15% (the best tier wins)
    const b2 = await consumer();
    const five = await order(b2, e, [{ ticketTypeId: e.paid, quantity: 5 }]).expect(201);
    expect(five.body).toMatchObject({ subtotalMmk: 50_000, discountMmk: 5_000, totalMmk: 45_000, discountSource: 'GROUP', groupDiscountBp: 1000 });
    const row = await prisma.order.findUniqueOrThrow({ where: { id: five.body.id } });
    expect(row).toMatchObject({ groupDiscountBp: 1000, discountMmk: 5_000n, promoCodeId: null, totalMmk: 45_000n });
    const ten = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 10 }, { ticketTypeId: e.free, quantity: 3 }]).expect(201);
    expect(ten.body).toMatchObject({ subtotalMmk: 100_000, discountMmk: 15_000, totalMmk: 85_000, discountSource: 'GROUP', groupDiscountBp: 1500 });

    // the preview with a valid code that does not beat it reports the group discount
    await promoFor(e, { code: 'PREV', kind: 'PERCENT', value: 5 });
    const pv = await http.post(`/v1/events/${e.eventId}/promo-check`).set(await consumer()).send({ code: 'PREV', items: [{ ticketTypeId: e.paid, quantity: 5 }] }).expect(200);
    expect(pv.body).toMatchObject({ valid: true, discountMmk: 5_000, totalMmk: 45_000, discountSource: 'GROUP', promoApplied: false });
    // replacing the tiers removes the discount for new orders; existing orders keep theirs
    await tiersOf(e, []).expect(200);
    const none = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 5 }]).expect(201);
    expect(none.body).toMatchObject({ discountMmk: 0, discountSource: null });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: five.body.id } })).discountMmk).toBe(5_000n);
  });

  it('larger of group and promo wins; promo use only taken when promo wins', async () => {
    const e = await newEvent('Versus', 20);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);
    for (const [code, value] of [['BIG', 20], ['SMALL', 5], ['TIE', 10]] as const) await promoFor(e, { code, kind: 'PERCENT', value });
    const items = [{ ticketTypeId: e.paid, quantity: 5 }];

    // promo larger → promo wins, its use is taken, the group discount is not recorded
    const big = await order(await consumer(), e, items, 'BIG').expect(201);
    expect(big.body).toMatchObject({ discountMmk: 10_000, totalMmk: 40_000, discountSource: 'PROMO', groupDiscountBp: null });
    expect(await prisma.order.findUniqueOrThrow({ where: { id: big.body.id } })).toMatchObject({ groupDiscountBp: null, promoCodeId: (await prisma.promoCode.findFirstOrThrow({ where: { eventId: e.eventId, code: 'BIG' } })).id });
    expect(await promoUsed(e.eventId, 'BIG')).toBe(1);

    // group larger → group wins, no promo use, no promo on the order
    const small = await order(await consumer(), e, items, 'SMALL').expect(201);
    expect(small.body).toMatchObject({ discountMmk: 5_000, totalMmk: 45_000, discountSource: 'GROUP', groupDiscountBp: 1000 });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: small.body.id } })).promoCodeId).toBeNull();
    expect(await promoUsed(e.eventId, 'SMALL')).toBe(0);

    // tie → the group discount wins and the promo is not applied
    const tie = await order(await consumer(), e, items, 'TIE').expect(201);
    expect(tie.body).toMatchObject({ discountMmk: 5_000, discountSource: 'GROUP' });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: tie.body.id } })).promoCodeId).toBeNull();
    expect(await promoUsed(e.eventId, 'TIE')).toBe(0);

    // previews: valid but not applied (small, tie), applied (big); below the tier the promo applies
    const check = async (code: string, quantity: number) => (await http.post(`/v1/events/${e.eventId}/promo-check`).set(await consumer()).send({ code, items: [{ ticketTypeId: e.paid, quantity }] }).expect(200)).body;
    expect(await check('SMALL', 5)).toMatchObject({ valid: true, discountSource: 'GROUP', promoApplied: false, discountMmk: 5_000 });
    expect(await check('TIE', 5)).toMatchObject({ valid: true, discountSource: 'GROUP', promoApplied: false, discountMmk: 5_000 });
    expect(await check('BIG', 5)).toMatchObject({ valid: true, discountSource: 'PROMO', promoApplied: true, discountMmk: 10_000 });
    expect(await check('SMALL', 4)).toMatchObject({ valid: true, discountSource: 'PROMO', promoApplied: true, discountMmk: 2_000 });
    expect(await check('NOPE', 5)).toMatchObject({ valid: false, discountSource: null, promoApplied: false });
    const below = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 4 }], 'SMALL').expect(201);
    expect(below.body).toMatchObject({ discountMmk: 2_000, discountSource: 'PROMO' });
    expect(await promoUsed(e.eventId, 'SMALL')).toBe(1);

    // a promo capped at one use that loses to the group discount is not consumed, so it is still available
    await promoFor(e, { code: 'ONCE', kind: 'PERCENT', value: 5, maxUses: 1 });
    await order(await consumer(), e, items, 'ONCE').expect(201);
    expect(await promoUsed(e.eventId, 'ONCE')).toBe(0);
    await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 2 }], 'ONCE').expect(201);
    expect(await promoUsed(e.eventId, 'ONCE')).toBe(1);
  });

  it('commission is computed on the discounted subtotal', async () => {
    const e = await newEvent('Fee', 20);
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: e.eventId, percentBp: 500 } });
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);
    const o = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 5 }]).expect(201);
    expect(o.body).toMatchObject({ subtotalMmk: 50_000, discountMmk: 5_000, totalMmk: 45_000 });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).commissionMmk).toBe(2_250n); // 5% of 45,000, not of 50,000
  });

  it('group discount never applies to comps', async () => {
    const hall = { width: 600, height: 400, sections: [{ key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }, { n: 3 }] }] }] };
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Growth Hall ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    const versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id as string;
    const e = await newEvent('Comp', 20);
    await http.put(`${e.base}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${e.base}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: e.paid }] }).expect(200);
    await tiersOf(e, [{ minQuantity: 2, percentBp: 5000 }]).expect(200);
    const seats = ['A:1:1', 'A:1:2', 'A:1:3'];
    await http.post(`${e.base}/seating/hold`).set(O).send({ seats, label: 'Sponsor' }).expect(201);
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    await http.post(`${e.base}/seating/comps`).set(O).send({ seats, guestName: 'Daw Mya', phone }).expect(201);
    const comps = await prisma.order.findMany({ where: { eventId: e.eventId, channel: 'COMP' } });
    expect(comps).toHaveLength(1);
    expect(comps[0]).toMatchObject({ discountMmk: 0n, groupDiscountBp: null, promoCodeId: null, totalMmk: 0n, commissionMmk: 0n });
  });

  // ───────────── group discounts: round 2 ─────────────

  const lateConfirm = async (h: Record<string, string>, orderId: string, url: string) => {
    const u = new URL(url);
    await http.post(`${u.pathname}/pay`).type('form').send({ t: u.searchParams.get('t') }).expect(201);
    return prisma.order.findUniqueOrThrow({ where: { id: orderId } });
  };
  const payUrl = async (h: Record<string, string>, orderId: string) => (await http.post(`/v1/orders/${orderId}/pay`).set(h).send({ provider: 'MOCK' }).expect(200)).body.payment.action.url as string;

  it('hold expiry and late payment keep promo uses right for group-win and promo-win orders', async () => {
    const e = await newEvent('Expiry', 20);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);
    for (const [code, value] of [['BIG', 20], ['SMALL', 5], ['TIE', 10]] as const) await promoFor(e, { code, kind: 'PERCENT', value });
    const items = [{ ticketTypeId: e.paid, quantity: 5 }];
    const used = async () => [await promoUsed(e.eventId, 'BIG'), await promoUsed(e.eventId, 'SMALL'), await promoUsed(e.eventId, 'TIE')];

    // Group wins over SMALL and TIE: no use is taken, expiry gives none back, late payment takes none
    for (const code of ['SMALL', 'TIE']) {
      const h = await consumer();
      const o = await order(h, e, items, code).expect(201);
      const url = await payUrl(h, o.body.id);
      expect(await used()).toEqual([0, 0, 0]);
      await expireHold(prisma, svc, o.body.id);
      expect(await used()).toEqual([0, 0, 0]);
      const late = await lateConfirm(h, o.body.id, url);
      expect(late).toMatchObject({ status: 'PAID', totalMmk: 45_000n, promoCodeId: null, groupDiscountBp: 1000 });
      expect(await used()).toEqual([0, 0, 0]);
    }

    // Promo wins: the use is given back on expiry and taken again by the late payment
    const h = await consumer();
    const o = await order(h, e, items, 'BIG').expect(201);
    const url = await payUrl(h, o.body.id);
    expect(await used()).toEqual([1, 0, 0]);
    await expireHold(prisma, svc, o.body.id);
    expect(await used()).toEqual([0, 0, 0]);
    const late = await lateConfirm(h, o.body.id, url);
    expect(late).toMatchObject({ status: 'PAID', totalMmk: 40_000n, groupDiscountBp: null });
    expect(await used()).toEqual([1, 0, 0]);
  });

  it('seated paid orders, and seated plus standing, get the group discount', async () => {
    const hall = { width: 600, height: 400, sections: [{ key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [{ label: '1', seats: Array.from({ length: 12 }, (_, i) => ({ n: i + 1 })) }] }] };
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Growth Hall2 ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    const versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id as string;
    const e = await newEvent('Seated', 20);
    await http.put(`${e.base}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${e.base}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: e.paid }] }).expect(200);
    const floor = (await http.post(`${e.base}/ticket-types`).set(O).send({ name: 'Floor', priceMmk: 10_000, quota: 10, maxPerOrder: 20 }).expect(201)).body.id as string;
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);

    const seatOrder = (h: Record<string, string>, seats: string[], items: object[] = []) => http.post(`/v1/events/${e.eventId}/orders`).set(h).send({ seats, items });
    const four = await seatOrder(await consumer(), ['A:1:1', 'A:1:2', 'A:1:3', 'A:1:4']).expect(201);
    expect(four.body).toMatchObject({ subtotalMmk: 40_000, discountMmk: 0, discountSource: null });
    const five = await seatOrder(await consumer(), ['A:1:5', 'A:1:6', 'A:1:7', 'A:1:8', 'A:1:9']).expect(201);
    expect(five.body).toMatchObject({ subtotalMmk: 50_000, discountMmk: 5_000, totalMmk: 45_000, discountSource: 'GROUP', groupDiscountBp: 1000 });
    const mix = await seatOrder(await consumer(), ['A:1:10', 'A:1:11', 'A:1:12'], [{ ticketTypeId: floor, quantity: 2 }]).expect(201);
    expect(mix.body).toMatchObject({ subtotalMmk: 50_000, discountMmk: 5_000, totalMmk: 45_000, discountSource: 'GROUP', groupDiscountBp: 1000 });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: mix.body.id } })).groupDiscountBp).toBe(1000);
  });

  it('a group-discounted order books and refunds the discounted amount and commission', async () => {
    const e = await newEvent('Ledger', 20);
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: e.eventId, percentBp: 500 } });
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);
    const h = await consumer();
    const o = await order(h, e, [{ ticketTypeId: e.paid, quantity: 5 }]).expect(201);
    await confirm(await payMock(h, o.body.id));
    expect((await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).status).toBe('PAID');
    const lines = await prisma.ledgerEntry.findMany({ where: { refType: 'order', refId: o.body.id } });
    const by = (a: string) => lines.find((l) => l.account === a)!;
    expect(by('provider_clearing:MOCK').debitMmk).toBe(45_000n);
    expect(by('platform_commission').creditMmk).toBe(2_250n);
    expect(by(`organizer_payable:${orgId}`).creditMmk).toBe(42_750n);

    const r = await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'Buyer request' }).expect(200);
    expect(r.body.refunds[0]).toMatchObject({ status: 'SUCCEEDED', amountMmk: 45_000 });
    const refundIds = (await prisma.refund.findMany({ where: { orderId: o.body.id }, select: { id: true } })).map((x) => x.id);
    const rev = await prisma.ledgerEntry.findMany({ where: { refType: 'refund_order', refId: o.body.id } });
    const debit = (a: string) => rev.filter((l) => l.account === a).reduce((s, l) => s + l.debitMmk, 0n);
    expect(debit('platform_commission')).toBe(2_250n);
    expect(debit(`organizer_payable:${orgId}`)).toBe(42_750n);
    expect(rev.find((l) => l.account === 'refunds_payable')!.creditMmk).toBe(45_000n);
    const paidOut = await prisma.ledgerEntry.findMany({ where: { refType: 'refund', refId: { in: refundIds } } });
    expect(paidOut.find((l) => l.account === 'provider_clearing:MOCK')!.creditMmk).toBe(45_000n);
  });

  it('parallel group-discount replacements leave exactly one request\'s tiers', async () => {
    const e = await newEvent('TierRace', 20);
    const sets = [1, 2, 3, 4, 5, 6].map((i) => [{ minQuantity: 2, percentBp: 100 * i }, { minQuantity: 6, percentBp: 100 * i + 50 }]);
    const rs = await Promise.all(sets.map((tiers) => tiersOf(e, tiers)));
    expect(rs.map((r) => r.status)).toEqual([200, 200, 200, 200, 200, 200]);
    const now = (await http.get(`${e.base}/group-discounts`).set(O).expect(200)).body.tiers;
    expect(sets).toContainEqual(now);
    expect(await prisma.groupDiscount.count({ where: { eventId: e.eventId } })).toBe(2);
  });

  it('attendee CSV shows the discount: GROUP %, the promo code, or nothing', async () => {
    const e = await newEvent('Csv', 20);
    await tiersOf(e, [{ minQuantity: 5, percentBp: 1000 }]).expect(200);
    await promoFor(e, { code: 'CSVBIG', kind: 'PERCENT', value: 20 });
    const g = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 5 }]).expect(201);
    const p = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 5 }], 'CSVBIG').expect(201);
    const n = await order(await consumer(), e, [{ ticketTypeId: e.paid, quantity: 1 }]).expect(201);
    for (const o of [g, p, n]) await prisma.order.update({ where: { id: o.body.id }, data: { status: 'PAID' } }), await prisma.ticket.createMany({ data: [{ orderId: o.body.id, ticketTypeId: e.paid, holderUserId: (await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).userId }] });
    const csv = await http.get(`${e.base}/attendees.csv`).set(O).expect(200);
    const rows = csv.text.replace(/^\uFEFF/, '').split('\r\n').filter(Boolean).map((l: string) => l.replace(/"/g, '').split(','));
    const col = rows[0].indexOf('discount');
    expect(col).toBe(rows[0].indexOf('promo_code') + 1);
    const byOrder = (o: { body: { id: string } }) => rows.find((r: string[]) => r[6] === o.body.id.slice(0, 8))![col];
    expect(byOrder(g)).toBe('GROUP 10%');
    expect(byOrder(p)).toBe('CSVBIG');
    expect(byOrder(n)).toBe('');
  });
});
