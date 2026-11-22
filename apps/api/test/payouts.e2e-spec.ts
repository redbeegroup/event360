/**
 * Organizer payouts: admin records/voids payouts (ledger journals), organizers read a summary that must match the
 * admin balances. Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Payouts', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  let A: Record<string, string>, O: Record<string, string>, F: Record<string, string>, M: Record<string, string>, C: Record<string, string>;
  let orgId: string, eventId: string, ttId: string, adminId: string;
  let order2: string; // the single-ticket order, refunded later
  const payoutBase = () => `/v1/admin/finance/organizations/${orgId}/payouts`;
  const summary = (h: Record<string, string>) => http.get(`/v1/organizations/${orgId}/payouts/summary`).set(h);
  const record = (amountMmk: number, extra: object = {}) => http.post(payoutBase()).set(A).send({ amountMmk, paidAt: new Date().toISOString(), method: 'BANK', reference: 'TX-1', note: 'test', ...extra });
  const balance = async () => (await http.get('/v1/admin/finance/balances').set(A).expect(200)).body.find((b: any) => b.organizationId === orgId);
  const net = async (account: string) => {
    const rows = await prisma.ledgerEntry.findMany({ where: { account } });
    return rows.reduce((s, l) => s + l.creditMmk - l.debitMmk, 0n);
  };

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  async function consumer() {
    const p = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return bearer(r2.body.accessToken as string);
  }
  async function buy(qty: number) {
    const h = await consumer();
    const o = await http.post(`/v1/events/${eventId}/orders`).set(h).send({ items: [{ ticketTypeId: ttId, quantity: qty }] }).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(h).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(p.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t') }).expect(201);
    return o.body.id as string;
  }

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
    prisma = app.get(PrismaService);

    const adm = await app.get(AuthService).createInvitation({ email: `adm-po-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    adminId = (await prisma.user.findFirstOrThrow({ where: { email: `adm-po-${tag}@e2e.test` } })).id;
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Payout Org ${tag}`, slug: `po-${tag}`, ownerEmail: `own-po-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const member = async (role: string, n: string) => {
      const inv = await http.post(`/v1/organizations/${orgId}/invitations`).set(O).send({ email: `${n}-po-${tag}@e2e.test`, role }).expect(201);
      return acceptInvite(inv.body.inviteUrl);
    };
    F = await member('ORG_FINANCE', 'fin');
    M = await member('ORG_MANAGER', 'mgr');
    C = await member('CREW', 'crew');
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 7 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Payout Show ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    eventId = ev.body.id;
    const base = `/v1/organizations/${orgId}/events/${eventId}`;
    ttId = (await http.post(`${base}/ticket-types`).set(O).send({ name: 'Standard', priceMmk: 10_000, quota: 50, maxPerOrder: 10 }).expect(201)).body.id;
    await http.post(`${base}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: eventId, percentBp: 500 } });
    await http.put(`${base}/group-discounts`).set(O).send({ tiers: [{ minQuantity: 2, percentBp: 1000 }] }).expect(200);
    // 5 tickets: 50,000 − 5,000 group discount = 45,000, commission 2,250; then 1 ticket: 10,000, commission 500
    await buy(5);
    order2 = await buy(1);
  });
  afterAll(() => app?.close());

  it('recording a payout journals payable→payouts_cash and lowers owed', async () => {
    expect((await balance()).owedMmk).toBe(52_250);
    const before = await net('payouts_cash');
    const r = await record(20_000).expect(201);
    expect(r.body).toMatchObject({ amountMmk: 20_000, method: 'BANK', reference: 'TX-1', voidedAt: null, owedMmk: 32_250 });
    const lines = await prisma.ledgerEntry.findMany({ where: { refType: 'payout', refId: r.body.id } });
    expect(lines).toHaveLength(2);
    expect(lines.find((l) => l.account === `organizer_payable:${orgId}`)!.debitMmk).toBe(20_000n);
    expect(lines.find((l) => l.account === 'payouts_cash')!.creditMmk).toBe(20_000n);
    expect((await net('payouts_cash')) - before).toBe(20_000n);
    expect(await balance()).toMatchObject({ paidOutMmk: 20_000, owedMmk: 32_250 });
    expect(await prisma.auditLog.count({ where: { action: 'payout.record', entityId: r.body.id, actorId: adminId } })).toBe(1);
    const list = await http.get(payoutBase()).set(A).expect(200);
    expect(list.body).toHaveLength(1);
    // validation
    await http.get('/v1/admin/finance/organizations/00000000-0000-4000-8000-000000000000/payouts').set(A).expect(404);
    await record(0).expect(400);
    await record(-5).expect(400);
    await record(1.5).expect(400);
    await record(100, { method: 'CHEQUE' }).expect(400);
    await record(100, { paidAt: 'nope' }).expect(400);
    for (const m of ['KBZPAY', 'WAVEPAY', 'CASH', 'OTHER']) {
      // method coverage; each is voided straight away so totals stay put
      const x = await record(1, { method: m }).expect(201);
      await http.post(`/v1/admin/finance/payouts/${x.body.id}/void`).set(A).send({ reason: 'method check' }).expect(200);
    }
  });

  it('voiding reverses it', async () => {
    const r = await record(7_000).expect(201);
    expect((await balance()).owedMmk).toBe(25_250);
    await http.post(`/v1/admin/finance/payouts/${r.body.id}/void`).set(A).send({ reason: 'Wrong amount' }).expect(200);
    expect(await balance()).toMatchObject({ paidOutMmk: 20_000, owedMmk: 32_250 });
    const row = await prisma.payout.findUniqueOrThrow({ where: { id: r.body.id } });
    expect(row.voidedAt).not.toBeNull();
    expect(row.voidReason).toBe('Wrong amount');
    const vl = await prisma.ledgerEntry.findMany({ where: { refType: 'payout_void', refId: r.body.id } });
    expect(vl).toHaveLength(2);
    const vcash = vl.find((l) => l.account === 'payouts_cash')!;
    const vpay = vl.find((l) => l.account === `organizer_payable:${orgId}`)!;
    expect([vcash.debitMmk, vcash.creditMmk]).toEqual([7_000n, 0n]);
    expect([vpay.debitMmk, vpay.creditMmk]).toEqual([0n, 7_000n]);
    expect(vcash.journalId).toBe(vpay.journalId);
    expect(await prisma.auditLog.count({ where: { action: 'payout.void', entityId: r.body.id } })).toBe(1);
    await http.post(`/v1/admin/finance/payouts/${r.body.id}/void`).set(A).send({ reason: 'again' }).expect(409);
    // concurrent voids: exactly one wins
    const c = await record(3_000).expect(201);
    const res = await Promise.all([1, 2, 3].map(() => http.post(`/v1/admin/finance/payouts/${c.body.id}/void`).set(A).send({ reason: 'race' })));
    expect(res.map((x) => x.status).sort()).toEqual([200, 409, 409]);
    expect(await prisma.ledgerEntry.count({ where: { refType: 'payout_void', refId: c.body.id } })).toBe(2);
    expect((await balance()).owedMmk).toBe(32_250);
    await http.post('/v1/admin/finance/payouts/00000000-0000-4000-8000-000000000000/void').set(A).send({ reason: 'missing' }).expect(404);
    await http.post(`/v1/admin/finance/payouts/${r.body.id}/void`).set(A).send({}).expect(400);
  });

  it('organizer summary equals admin balances for the same org', async () => {
    const s = (await summary(O).expect(200)).body;
    const b = await balance();
    expect(s.paidOutMmk).toBe(b.paidOutMmk);
    expect(s.owedMmk).toBe(b.owedMmk);
    expect(s.earnedMmk).toBe(52_250);
    expect(s).toMatchObject({ eventsNetMmk: 52_250, reconciled: true });
    expect(s.payouts[0].createdById).toBeUndefined();
    expect(s.events).toEqual([{ eventId, title: `Payout Show ${tag}`, grossMmk: 55_000, discountMmk: 5_000, commissionMmk: 2_750, refundsMmk: 0, netMmk: 52_250 }]);
    expect(s.events.reduce((t: number, e: any) => t + e.netMmk, 0)).toBe(s.earnedMmk);
    expect(s.payouts.length).toBeGreaterThan(1); // voided ones stay in the history
    expect(s.payouts.filter((p: any) => !p.voidedAt)).toHaveLength(1);
    const csv = await http.get(`/v1/organizations/${orgId}/payouts/summary.csv`).set(F).expect(200);
    expect(csv.headers['content-type']).toContain('text/csv');
    expect(csv.text).toContain(`Payout Show ${tag}`);
    expect(csv.text).toContain('"52250","20000","32250"');
  });

  it('refund after payout makes owed negative', async () => {
    await record(32_250).expect(201); // now fully paid out
    expect((await balance()).owedMmk).toBe(0);
    await http.post(`/v1/admin/finance/orders/${order2}/refund`).set(A).send({ reason: 'Buyer request' }).expect(200);
    const s = (await summary(O).expect(200)).body;
    expect(s).toMatchObject({ earnedMmk: 42_750, paidOutMmk: 52_250, owedMmk: -9_500 });
    expect(s).toMatchObject({ eventsNetMmk: 42_750, reconciled: true });
    const csv = await http.get(`/v1/organizations/${orgId}/payouts/summary.csv`).set(O).expect(200);
    expect(csv.text).toContain('"42750","52250","-9500"');
    expect(csv.text).not.toContain("'-9500");
    expect(s.events[0]).toMatchObject({ grossMmk: 55_000, refundsMmk: 10_000, commissionMmk: 2_250, netMmk: 42_750 });
    expect(await balance()).toMatchObject({ paidOutMmk: 52_250, owedMmk: -9_500 });
    const pj = await prisma.ledgerEntry.findMany({ where: { refType: { in: ['payout', 'payout_void'] } } });
    expect(pj.reduce((t, l) => t + l.debitMmk - l.creditMmk, 0n)).toBe(0n); // every payout journal balances
  });

  it('roles: org FINANCE/OWNER can read; MANAGER/CREW 403; only platform admin can record/void', async () => {
    await summary(O).expect(200);
    await summary(F).expect(200);
    await summary(A).expect(200);
    await summary(M).expect(403);
    await summary(C).expect(403);
    await summary(await consumer()).expect(403);
    await http.get(`/v1/organizations/${orgId}/payouts/summary`).expect(401);
    await http.get(`/v1/organizations/${orgId}/payouts/summary.csv`).set(M).expect(403);
    const pid = (await prisma.payout.findFirstOrThrow({ where: { organizationId: orgId, voidedAt: null } })).id;
    for (const h of [O, F, M, C]) {
      await http.post(payoutBase()).set(h).send({ amountMmk: 1, paidAt: new Date().toISOString(), method: 'CASH' }).expect(403);
      await http.post(`/v1/admin/finance/payouts/${pid}/void`).set(h).send({ reason: 'nope' }).expect(403);
      await http.get(payoutBase()).set(h).expect(403);
    }
    expect((await prisma.payout.findUniqueOrThrow({ where: { id: pid } })).voidedAt).toBeNull();
  });

  it('cross-org scoping: org B cannot read org A, and A excludes B data', async () => {
    const orgB = await http.post('/v1/admin/organizations').set(A).send({ name: `Payout Org B ${tag}`, slug: `pob-${tag}`, ownerEmail: `ownb-po-${tag}@e2e.test` }).expect(201);
    const B = await acceptInvite(orgB.body.inviteUrl);
    const bId = orgB.body.organization.id as string;
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 7 * 86400e3);
    const bBase = `/v1/organizations/${bId}/events`;
    const ev = await http.post(bBase).set(B).send({ categoryId: cats.body[0].children[0].id, title: `B Show ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() }).expect(201);
    const tt = (await http.post(`${bBase}/${ev.body.id}/ticket-types`).set(B).send({ name: 'Std', priceMmk: 4_000, quota: 10, maxPerOrder: 5 }).expect(201)).body.id;
    await http.post(`${bBase}/${ev.body.id}/submit`).set(B).expect(200);
    await http.post(`/v1/admin/events/${ev.body.id}/approve`).set(A).expect(200);
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: ev.body.id, percentBp: 500 } });
    const h = await consumer();
    const o = await http.post(`/v1/events/${ev.body.id}/orders`).set(h).send({ items: [{ ticketTypeId: tt, quantity: 1 }] }).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(h).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(p.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t') }).expect(201);
    await http.post(`/v1/admin/finance/organizations/${bId}/payouts`).set(A).send({ amountMmk: 1_000, paidAt: new Date().toISOString(), method: 'CASH' }).expect(201);

    await http.get(`/v1/organizations/${orgId}/payouts/summary`).set(B).expect(403);
    await http.get(`/v1/organizations/${orgId}/payouts/summary.csv`).set(B).expect(403);
    await http.get(`/v1/organizations/${bId}/payouts/summary`).set(O).expect(403);
    const a = (await summary(O).expect(200)).body;
    expect(a.events.map((e: any) => e.eventId)).toEqual([eventId]);
    expect(a.payouts.every((x: any) => x.organizationId === orgId)).toBe(true);
    expect(a).toMatchObject({ earnedMmk: 42_750, paidOutMmk: 52_250 });
    const b = (await http.get(`/v1/organizations/${bId}/payouts/summary`).set(B).expect(200)).body;
    expect(b).toMatchObject({ earnedMmk: 3_800, paidOutMmk: 1_000, owedMmk: 2_800, reconciled: true });
    expect(b.events.map((e: any) => e.eventId)).toEqual([ev.body.id]);
  });

  it('COMP orders excluded from per-event figures', async () => {
    const before = (await summary(O).expect(200)).body;
    await prisma.order.create({ data: { userId: adminId, eventId, status: 'PAID', subtotalMmk: 99_000n, totalMmk: 99_000n, commissionMmk: 4_950n, discountMmk: 1_000n, channel: 'COMP', paidAt: new Date() } });
    const after = (await summary(O).expect(200)).body;
    expect(after.events).toEqual(before.events);
    expect((await balance()).grossMmk).toBe(55_000);
  });

  it('an organization with no sales yet: admin summary is zeros, a payout can be recorded, non-admins are refused', async () => {
    const fresh = await http.post('/v1/admin/organizations').set(A).send({ name: `Payout Fresh ${tag}`, slug: `pof-${tag}`, ownerEmail: `ownf-po-${tag}@e2e.test` }).expect(201);
    const id = fresh.body.organization.id as string;
    const sum = `/v1/admin/finance/organizations/${id}/summary`;
    expect((await http.get(sum).set(A).expect(200)).body).toMatchObject({ earnedMmk: 0, paidOutMmk: 0, owedMmk: 0, events: [], payouts: [] });
    for (const h of [O, F, M, C, await consumer()]) await http.get(sum).set(h).expect(403);
    await http.get(sum).expect(401);
    await http.get('/v1/admin/finance/organizations/not-a-uuid/summary').set(A).expect(400);
    const r = await http.post(`/v1/admin/finance/organizations/${id}/payouts`).set(A).send({ amountMmk: 5_000, paidAt: new Date().toISOString(), method: 'CASH' }).expect(201);
    expect(r.body.owedMmk).toBe(-5_000); // overpaid: the form warns, the server allows it
    expect((await http.get(sum).set(A).expect(200)).body).toMatchObject({ paidOutMmk: 5_000, owedMmk: -5_000 });
  });
});
