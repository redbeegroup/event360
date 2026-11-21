/**
 * Paid tickets over HTTP against a real PostgreSQL, using the dev-only Mock pay provider (real webhook path).
 * Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt, randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { PaymentsService } from '../src/modules/payments/payments.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Paid tickets', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let svc: PaymentsService;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

  async function consumer() {
    const p = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return bearer(r2.body.accessToken as string);
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const tokenOf = (url: string) => new URL(url).searchParams.get('t')!;
  const pathOf = (url: string) => new URL(url).pathname;

  let A: Record<string, string>, O: Record<string, string>, orgId: string, eventId: string, ttA: string, ttB: string, ttFree: string;

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    process.env.PUBLIC_API_URL = 'https://api.example';
    process.env.CORS_ORIGINS = 'https://app.example';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    svc = app.get(PaymentsService);
    prisma = app.get(PrismaService);

    const adm = await app.get(AuthService).createInvitation({ email: `adm-p-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Pay Org ${tag}`, slug: `pay-${tag}`, ownerEmail: `own-p-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 7 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Paid Concert ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    eventId = ev.body.id;
    const add = (b: object) => http.post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`).set(O).send(b).expect(201);
    ttA = (await add({ name: 'Standard', priceMmk: 10_000, quota: 3, maxPerOrder: 2 })).body.id;
    ttB = (await add({ name: 'VIP', priceMmk: 5_000, quota: 1, maxPerOrder: 1 })).body.id;
    ttFree = (await add({ name: 'Kids', priceMmk: 0, quota: 10, maxPerOrder: 2 })).body.id;
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    // Fee for this test only: an event-level rule (5%, min 300) so other tests' global settings don't matter
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: eventId, percentBp: 500, minMmk: 300n } });
  });
  afterAll(() => app?.close());

  const tt = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });

  it('checkout → hold → mock pay → tickets + balanced ledger; idempotent webhooks', async () => {
    const methods = await http.get('/v1/payments/methods').expect(200);
    expect(methods.body.map((m: any) => m.code)).toContain('MOCK');

    const B1 = await consumer();
    const key = randomUUID();
    const o1 = await http.post(`/v1/events/${eventId}/orders`).set(B1).send({ items: [{ ticketTypeId: ttA, quantity: 2 }], idempotencyKey: key }).expect(201);
    expect(o1.body).toMatchObject({ status: 'PENDING_PAYMENT', totalMmk: 20_000 });
    expect(new Date(o1.body.holdExpiresAt).getTime()).toBeGreaterThan(Date.now() + 9 * 60e3);
    const again = await http.post(`/v1/events/${eventId}/orders`).set(B1).send({ items: [{ ticketTypeId: ttA, quantity: 2 }], idempotencyKey: key }).expect(201);
    expect(again.body.id).toBe(o1.body.id);
    expect(await tt(ttA)).toMatchObject({ held: 2, sold: 0 });
    // Per-person limit counts pending orders too
    await http.post(`/v1/events/${eventId}/orders`).set(B1).send({ items: [{ ticketTypeId: ttA, quantity: 1 }] }).expect(409);

    const p1 = await http.post(`/v1/orders/${o1.body.id}/pay`).set(B1).send({ provider: 'MOCK', returnUrl: 'https://evil.example/x' }).expect(200);
    const action = p1.body.payment.action;
    expect(action.type).toBe('REDIRECT');
    expect(action.returnUrl).toBeUndefined(); // not one of our sites
    const page = await http.get(`${pathOf(action.url)}?t=${tokenOf(action.url)}`).expect(200);
    expect(page.text).toContain('20,000 MMK');
    await http.get(`${pathOf(action.url)}?t=wrong`).expect(403);
    // Paying the same order again reuses the pending payment
    const p1b = await http.post(`/v1/orders/${o1.body.id}/pay`).set(B1).send({ provider: 'MOCK' }).expect(200);
    expect(p1b.body.payment.id).toBe(p1.body.payment.id);

    await http.post(`${pathOf(action.url)}/pay`).type('form').send({ t: tokenOf(action.url) }).expect(201);
    const paid = await http.get(`/v1/orders/${o1.body.id}`).set(B1).expect(200);
    expect(paid.body.status).toBe('PAID');
    expect(paid.body.ticketIds).toHaveLength(2);
    expect(await tt(ttA)).toMatchObject({ held: 0, sold: 2 });
    const mine = await http.get('/v1/me/tickets').set(B1).expect(200);
    expect(mine.body.filter((t: any) => t.status === 'VALID' && t.qr)).toHaveLength(2);

    // Ledger: 20,000 in, 1,000 commission, 19,000 owed to the organizer
    const lines = await prisma.ledgerEntry.findMany({ where: { refType: 'order', refId: o1.body.id } });
    const by = (a: string) => lines.find((l) => l.account === a)!;
    expect(by('provider_clearing:MOCK').debitMmk).toBe(20_000n);
    expect(by('platform_commission').creditMmk).toBe(1_000n);
    expect(by(`organizer_payable:${orgId}`).creditMmk).toBe(19_000n);

    // Replayed callback: accepted, nothing changes
    const cb = svc.mock.callbackFor(p1.body.payment.id, 'SUCCEEDED', 20_000n);
    await http.post('/v1/payments/webhook/mock').set('x-mock-signature', cb.signature).send(cb.body).expect(200);
    expect(await prisma.ticket.count({ where: { orderId: o1.body.id } })).toBe(2);
    expect(await prisma.ledgerEntry.count({ where: { refType: 'order', refId: o1.body.id } })).toBe(3);
    // Forged callback: 401 and stored unverified
    const before = await prisma.paymentEvent.count({ where: { provider: 'MOCK', verified: false } });
    await http.post('/v1/payments/webhook/mock').set('x-mock-signature', 'f'.repeat(64)).send(cb.body).expect(401);
    expect(await prisma.paymentEvent.count({ where: { provider: 'MOCK', verified: false } })).toBe(before + 1);
  });

  it('quota holds, cancel, lost callback picked up by the reconciler', async () => {
    const B2 = await consumer();
    const B3 = await consumer();
    // 1 Standard left
    await http.post(`/v1/events/${eventId}/orders`).set(B2).send({ items: [{ ticketTypeId: ttA, quantity: 2 }] }).expect(409);
    const c = await http.post(`/v1/events/${eventId}/orders`).set(B3).send({ items: [{ ticketTypeId: ttA, quantity: 1 }] }).expect(201);
    await http.post(`/v1/events/${eventId}/orders`).set(B2).send({ items: [{ ticketTypeId: ttA, quantity: 1 }] }).expect(409); // held by B3
    await http.post(`/v1/orders/${c.body.id}/cancel`).set(B3).expect(200);
    expect(await tt(ttA)).toMatchObject({ held: 0, sold: 2 });

    const o = await http.post(`/v1/events/${eventId}/orders`).set(B2).send({ items: [{ ticketTypeId: ttA, quantity: 1 }] }).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(B2).send({ provider: 'mock' }).expect(200);
    const url = p.body.payment.action.url;
    await http.post(`${pathOf(url)}/silent`).type('form').send({ t: tokenOf(url) }).expect(201);
    expect((await http.get(`/v1/orders/${o.body.id}`).set(B2)).body.status).toBe('PENDING_PAYMENT');
    const pend = await http.get('/v1/me/orders?pending=1').set(B2).expect(200);
    expect(pend.body.map((x: any) => x.id)).toEqual([o.body.id]);

    await svc.sweep(new Date(Date.now() + 120e3)); // a reconcile pass two minutes later
    const done = await http.get(`/v1/orders/${o.body.id}`).set(B2).expect(200);
    expect(done.body.status).toBe('PAID');
    expect(done.body.ticketIds).toHaveLength(1);
    expect(await tt(ttA)).toMatchObject({ held: 0, sold: 3 });
  });

  it('expired hold releases seats; late payment with no seats left is flagged and refunded by an admin', async () => {
    const B4 = await consumer();
    const B5 = await consumer();
    const o = await http.post(`/v1/events/${eventId}/orders`).set(B4).send({ items: [{ ticketTypeId: ttB, quantity: 1 }] }).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(B4).send({ provider: 'MOCK' }).expect(200);
    // Expire only this hold: a sweep with a future clock would also expire other suites' holds running in parallel
    await prisma.order.update({ where: { id: o.body.id }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
    await svc.sweep();
    expect((await http.get(`/v1/orders/${o.body.id}`).set(B4)).body.status).toBe('EXPIRED');
    expect(await tt(ttB)).toMatchObject({ held: 0, sold: 0 });
    await http.post(`/v1/orders/${o.body.id}/pay`).set(B4).send({ provider: 'MOCK' }).expect(409);

    // Someone else takes the seat, then B4's money arrives late
    await http.post(`/v1/events/${eventId}/orders`).set(B5).send({ items: [{ ticketTypeId: ttB, quantity: 1 }] }).expect(201);
    const url = p.body.payment.action.url;
    await http.post(`${pathOf(url)}/pay`).type('form').send({ t: tokenOf(url) }).expect(201);
    const late = await prisma.order.findUniqueOrThrow({ where: { id: o.body.id }, include: { tickets: true } });
    expect(late).toMatchObject({ status: 'PAID', needsReview: true });
    expect(late.tickets).toHaveLength(0);
    expect(await tt(ttB)).toMatchObject({ held: 1, sold: 0 });

    const review = await http.get('/v1/admin/finance/orders?review=1').set(A).expect(200);
    expect(review.body.map((r: any) => r.id)).toContain(o.body.id);
    await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(O).send({ reason: 'sold out' }).expect(403);
    const r = await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'Sold out before payment arrived' }).expect(200);
    expect(r.body).toMatchObject({ status: 'REFUNDED', needsReview: false });
    expect(r.body.refunds[0]).toMatchObject({ status: 'SUCCEEDED', amountMmk: 5_000 });
    await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'again' }).expect(409);
  });

  it('admin refund voids tickets and returns seats; balances, sales and the ledger add up', async () => {
    const paid = await prisma.order.findFirstOrThrow({ where: { eventId, status: 'PAID', needsReview: false, items: { some: { quantity: 2 } } } });
    await http.post(`/v1/admin/finance/orders/${paid.id}/refund`).set(A).send({ reason: 'Buyer request' }).expect(200);
    expect(await prisma.ticket.count({ where: { orderId: paid.id, status: 'REFUNDED' } })).toBe(2);
    expect(await tt(ttA)).toMatchObject({ sold: 1 });

    // Organizer is owed only the remaining sale: 10,000 − 500
    const bal = await http.get('/v1/admin/finance/balances').set(A).expect(200);
    expect(bal.body.find((b: any) => b.organizationId === orgId)).toMatchObject({ owedMmk: 9_500, grossMmk: 35_000, refundedMmk: 25_000, commissionMmk: 500 });
    const csv = await http.get('/v1/admin/finance/balances.csv').set(A).expect(200);
    expect(csv.text).toContain(`Pay Org ${tag}`);
    const sales = await http.get(`/v1/organizations/${orgId}/events/${eventId}/sales`).set(O).expect(200);
    expect(sales.body).toMatchObject({ paidOrders: 1, grossMmk: 10_000, commissionMmk: 500, netMmk: 9_500, refundedOrders: 2 });
    const outsider = await consumer();
    await http.get(`/v1/organizations/${orgId}/events/${eventId}/sales`).set(outsider).expect(403);

    // Every journal for this event's orders balances, and refunds settled the buyer liability
    const orderIds = (await prisma.order.findMany({ where: { eventId }, select: { id: true } })).map((x) => x.id);
    const refundIds = (await prisma.refund.findMany({ where: { orderId: { in: orderIds } }, select: { id: true } })).map((x) => x.id);
    const all = await prisma.ledgerEntry.findMany({ where: { refId: { in: [...orderIds, ...refundIds] } } });
    const sum = (f: (l: (typeof all)[0]) => bigint) => all.reduce((s, l) => s + f(l), 0n);
    expect(sum((l) => l.debitMmk)).toBe(sum((l) => l.creditMmk));
    const net = (acc: string) => all.filter((l) => l.account === acc).reduce((s, l) => s + l.creditMmk - l.debitMmk, 0n);
    expect(net('refunds_payable')).toBe(0n);
    expect(net('platform_commission')).toBe(500n);
  });

  it('free tickets go through the same checkout; paid needs an enabled method', async () => {
    const B = await consumer();
    const f = await http.post(`/v1/events/${eventId}/orders`).set(B).send({ items: [{ ticketTypeId: ttFree, quantity: 2 }] }).expect(201);
    expect(f.body).toMatchObject({ status: 'CONFIRMED', totalMmk: 0 });
    expect(f.body.ticketIds).toHaveLength(2);

    (svc.mock as any).enabled = false;
    try {
      await http.post(`/v1/events/${eventId}/orders`).set(B).send({ items: [{ ticketTypeId: ttA, quantity: 1 }] }).expect(409);
    } finally {
      (svc.mock as any).enabled = true;
    }
  });

  it('payment provider settings keep secrets sealed; fee setting', async () => {
    await http.put('/v1/admin/settings/payments/kbzpay').set(A).send({ enabled: true }).expect(503);
    const secret = `kbz-app-key-${tag}-secret`;
    const v = await http
      .put('/v1/admin/settings/payments/kbzpay')
      .set(A)
      .send({ values: { merchantCode: '200001', appId: 'kp1234', appKey: secret }, mode: 'sandbox' })
      .expect(200);
    expect(JSON.stringify(v.body)).not.toContain(secret);
    expect(v.body.secrets.appKey).toMatchObject({ set: true, hint: `••••${secret.slice(-4)}` });
    await http.put('/v1/admin/settings/payments/kbzpay').set(A).send({ values: { appKey: '' } }).expect(200); // empty keeps it
    const all = await http.get('/v1/admin/settings/payments').set(A).expect(200);
    expect(all.body.find((p: any) => p.provider === 'kbzpay').secrets.appKey.set).toBe(true);
    await http.get('/v1/admin/settings/payments').set(O).expect(403);
    await http.put('/v1/admin/settings/payments/kbzpay').set(A).send({ values: { merchantCode: '', appId: '' } }).expect(200); // leave it unconfigured

    const fee = await http.get('/v1/admin/finance/fee').set(A).expect(200);
    expect(fee.body).toHaveProperty('percentBp');
  });
});
