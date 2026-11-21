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
  async function newEvent(name: string) {
    const start = new Date(Date.now() + 7 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: catId, title: `${name} ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    const eventId = ev.body.id as string;
    const base = `/v1/organizations/${orgId}/events/${eventId}`;
    const add = (b: object) => http.post(`${base}/ticket-types`).set(O).send(b).expect(201);
    const paid = (await add({ name: 'Standard', priceMmk: 10_000, quota: 20, maxPerOrder: 4 })).body.id as string;
    const free = (await add({ name: 'Kids', priceMmk: 0, quota: 20, maxPerOrder: 4 })).body.id as string;
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
});
