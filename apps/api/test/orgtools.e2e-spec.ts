/**
 * Organizer tools over HTTP against a real PostgreSQL: promo codes at checkout, ticket transfers,
 * attendee CSV (masked phones) and the event dashboard. Skipped when DATABASE_URL is not set.
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

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Organizer tools', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  let payments: PaymentsService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

  async function consumer() {
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return { h: bearer(r2.body.accessToken as string), phone };
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }

  let A: Record<string, string>, O: Record<string, string>, orgId: string, eventId: string, slug: string, ttStd: string, ttVip: string, ttFree: string;
  const base = () => `/v1/organizations/${orgId}/events/${eventId}`;

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
    payments = app.get(PaymentsService);

    const adm = await app.get(AuthService).createInvitation({ email: `adm-o-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Tools Org ${tag}`, slug: `tools-${tag}`, ownerEmail: `own-o-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    await http.patch(`/v1/admin/organizations/${orgId}/kyc`).set(A).send({ status: 'APPROVED' }).expect(200);
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Tools Gala ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    eventId = ev.body.id;
    slug = ev.body.slug;
    const add = (b: object) => http.post(`${base()}/ticket-types`).set(O).send(b).expect(201);
    ttStd = (await add({ name: 'Standard', priceMmk: 10_000, quota: 50, maxPerOrder: 4 })).body.id;
    ttVip = (await add({ name: 'VIP', priceMmk: 40_000, quota: 10, maxPerOrder: 2 })).body.id;
    ttFree = (await add({ name: '=Kids', priceMmk: 0, quota: 20, maxPerOrder: 2 })).body.id;
    await http.post(`${base()}/submit`).set(O).expect(200);
    await prisma.feeRule.create({ data: { scope: 'EVENT', scopeId: eventId, percentBp: 500 } });
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('promo codes: create, preview, apply at checkout, limits, release on cancel', async () => {
    const outsider = await consumer();
    await http.post(`${base()}/promo-codes`).set(outsider.h).send({ code: 'NOPE', kind: 'PERCENT', value: 10 }).expect(403);
    let list = await http.post(`${base()}/promo-codes`).set(O).send({ code: 'early20', kind: 'PERCENT', value: 20, maxUses: 2 }).expect(201);
    expect(list.body[0]).toMatchObject({ code: 'EARLY20', kind: 'PERCENT', value: 20, maxUses: 2, used: 0 });
    await http.post(`${base()}/promo-codes`).set(O).send({ code: 'EARLY20', kind: 'FIXED', value: 1000 }).expect(409);
    await http.post(`${base()}/promo-codes`).set(O).send({ code: 'VIPONLY', kind: 'FIXED', value: 5000, ticketTypeIds: [ttVip] }).expect(201);
    list = await http.post(`${base()}/promo-codes`).set(O).send({ code: 'COMP', kind: 'PERCENT', value: 100, maxUses: 1 }).expect(201);
    await http.post(`${base()}/promo-codes`).set(O).send({ code: 'BAD', kind: 'PERCENT', value: 150 }).expect(400);

    const B = await consumer();
    const pv = await http.post(`/v1/events/${eventId}/promo-check`).set(B.h).send({ code: 'early20', items: [{ ticketTypeId: ttStd, quantity: 2 }] }).expect(200);
    expect(pv.body).toMatchObject({ valid: true, subtotalMmk: 20_000, discountMmk: 4_000, totalMmk: 16_000 });
    const bad = await http.post(`/v1/events/${eventId}/promo-check`).set(B.h).send({ code: 'VIPONLY', items: [{ ticketTypeId: ttStd, quantity: 1 }] }).expect(200);
    expect(bad.body).toMatchObject({ valid: false, reason: 'This code does not apply to these tickets' });

    // Order with the code: discounted total, commission on the discounted amount
    const o1 = await http.post(`/v1/events/${eventId}/orders`).set(B.h).send({ items: [{ ticketTypeId: ttStd, quantity: 2 }], promoCode: 'Early20' }).expect(201);
    expect(o1.body).toMatchObject({ status: 'PENDING_PAYMENT', subtotalMmk: 20_000, discountMmk: 4_000, totalMmk: 16_000 });
    expect((await prisma.order.findUniqueOrThrow({ where: { id: o1.body.id } })).commissionMmk).toBe(800n);
    // Cancel gives the use back
    await http.post(`/v1/orders/${o1.body.id}/cancel`).set(B.h).expect(200);
    expect((await prisma.promoCode.findFirstOrThrow({ where: { eventId, code: 'EARLY20' } })).used).toBe(0);

    // Use it twice, third time it is used up
    const C = await consumer();
    const D = await consumer();
    await http.post(`/v1/events/${eventId}/orders`).set(B.h).send({ items: [{ ticketTypeId: ttStd, quantity: 1 }], promoCode: 'EARLY20' }).expect(201);
    const oc = await http.post(`/v1/events/${eventId}/orders`).set(C.h).send({ items: [{ ticketTypeId: ttStd, quantity: 1 }], promoCode: 'EARLY20' }).expect(201);
    const used = await http.post(`/v1/events/${eventId}/orders`).set(D.h).send({ items: [{ ticketTypeId: ttStd, quantity: 1 }], promoCode: 'EARLY20' }).expect(400);
    expect(used.body.message).toBe('This code has been used up');
    // Pay C's order through the mock wallet → promo stats count it
    const p = await http.post(`/v1/orders/${oc.body.id}/pay`).set(C.h).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(p.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t') }).expect(201);
    await app.get(NotifyService).idle();

    // 100% code: free order, tickets right away, no payment
    const comp = await http.post(`/v1/events/${eventId}/orders`).set(D.h).send({ items: [{ ticketTypeId: ttVip, quantity: 1 }], promoCode: 'comp' }).expect(201);
    expect(comp.body).toMatchObject({ status: 'CONFIRMED', totalMmk: 0, discountMmk: 40_000 });
    expect(comp.body.ticketIds).toHaveLength(1);

    list = await http.get(`${base()}/promo-codes`).set(O).expect(200);
    const early = list.body.find((x: any) => x.code === 'EARLY20');
    expect(early).toMatchObject({ used: 2, orders: 1, discountGivenMmk: 2_000, revenueMmk: 8_000 });
    // Used codes are switched off rather than deleted; unused ones are deleted
    list = await http.delete(`${base()}/promo-codes/${early.id}`).set(O).expect(200);
    expect(list.body.find((x: any) => x.code === 'EARLY20').isActive).toBe(false);
    const vipOnly = list.body.find((x: any) => x.code === 'VIPONLY');
    list = await http.delete(`${base()}/promo-codes/${vipOnly.id}`).set(O).expect(200);
    expect(list.body.find((x: any) => x.code === 'VIPONLY')).toBeUndefined();
    await http.post(`/v1/events/${eventId}/orders`).set(D.h).send({ items: [{ ticketTypeId: ttStd, quantity: 1 }], promoCode: 'EARLY20' }).expect(400);
  });

  it('ticket transfer: new holder gets the ticket and a new QR; limits apply', async () => {
    const S = await consumer();
    const R = await consumer();
    const o = await http.post(`/v1/events/${eventId}/orders`).set(S.h).send({ items: [{ ticketTypeId: ttFree, quantity: 2 }] }).expect(201);
    const [t1, t2] = o.body.ticketIds as string[];
    const before = (await http.get(`/v1/me/tickets/${t1}`).set(S.h).expect(200)).body;
    expect(before.canTransfer).toBe(true);

    await http.post(`/v1/me/tickets/${t1}/transfer`).set(S.h).send({ phone: S.phone }).expect(400); // to self
    await http.post(`/v1/me/tickets/${t1}/transfer`).set(S.h).send({ phone: '12345' }).expect(400);
    const tr = await http.post(`/v1/me/tickets/${t1}/transfer`).set(S.h).send({ phone: R.phone }).expect(200);
    expect(tr.body.ok).toBe(true);
    await http.get(`/v1/me/tickets/${t1}`).set(S.h).expect(404);
    const mine = (await http.get(`/v1/me/tickets/${t1}`).set(R.h).expect(200)).body;
    expect(mine.qr).not.toBe(before.qr); // old QR no longer matches (qrVersion bumped)
    await app.get(NotifyService).idle();
    const inbox = (await http.get('/v1/me/notifications').set(R.h).expect(200)).body;
    expect(inbox.items[0]).toMatchObject({ kind: 'ticket_received', link: '/tickets' });

    // Someone else's ticket: 404
    await http.post(`/v1/me/tickets/${t2}/transfer`).set(R.h).send({ phone: S.phone }).expect(404);
    // Recipient who never signed in: account is created for the number
    const newPhone = `09${randomInt(800_000_000, 899_999_999)}`;
    await http.post(`/v1/me/tickets/${t2}/transfer`).set(S.h).send({ phone: newPhone }).expect(200);
    expect(await prisma.user.count({ where: { phone: `+95${newPhone.slice(1)}` } })).toBe(1);

    // Max 3 moves per ticket
    const X = await consumer();
    await http.post(`/v1/me/tickets/${t1}/transfer`).set(R.h).send({ phone: X.phone }).expect(200);
    await http.post(`/v1/me/tickets/${t1}/transfer`).set(X.h).send({ phone: R.phone }).expect(200);
    const tooMany = await http.post(`/v1/me/tickets/${t1}/transfer`).set(R.h).send({ phone: X.phone }).expect(409);
    expect(tooMany.body.message).toContain('at most 3');

    // Organizer switches transfers off / cutoff
    const o2 = await http.post(`/v1/events/${eventId}/orders`).set(X.h).send({ items: [{ ticketTypeId: ttFree, quantity: 1 }] }).expect(201);
    await http.patch(base()).set(O).send({ transfersEnabled: false }).expect(200);
    await http.post(`/v1/me/tickets/${o2.body.ticketIds[0]}/transfer`).set(X.h).send({ phone: R.phone }).expect(403);
    await http.patch(base()).set(O).send({ transfersEnabled: true, transferCutoffHours: 168 }).expect(200);
    const late = await http.post(`/v1/me/tickets/${o2.body.ticketIds[0]}/transfer`).set(X.h).send({ phone: R.phone }).expect(409);
    expect(late.body.message).toContain('168 hour');
    expect((await http.get(`/v1/me/tickets/${o2.body.ticketIds[0]}`).set(X.h)).body.canTransfer).toBe(false);
    await http.patch(base()).set(O).send({ transferCutoffHours: 2 }).expect(200);
  });

  it('attendee CSV: masked phones, safe cells; organizers only', async () => {
    const outsider = await consumer();
    await http.get(`${base()}/attendees.csv`).set(outsider.h).expect(403);
    const r = await http.get(`${base()}/attendees.csv`).set(O).expect(200);
    expect(r.headers['content-type']).toContain('text/csv');
    expect(r.headers['content-disposition']).toContain(`${slug}-attendees.csv`);
    const lines = r.text.replace(/^﻿/, '').split('\r\n');
    expect(lines[0]).toBe('ticket,holder,phone,ticket_type,price_mmk,status,order,order_status,promo_code,purchased_at_mmt,checked_in_at_mmt,gate,transfers');
    expect(lines.length).toBeGreaterThan(5);
    expect(r.text).not.toMatch(/\+959\d{7,9}/); // no full numbers
    expect(r.text).toMatch(/"09\d\d•••\d{3}"/);
    expect(r.text).toContain(`"'=Kids"`); // formula-looking names neutralised
    expect(r.text).toContain('"EARLY20"');
  });

  it('dashboard: totals, daily series with page views, conversion', async () => {
    await http.get(`/v1/events/${slug}`).expect(200);
    await http.get(`/v1/events/${slug}`).expect(200);
    const d = await http.get(`${base()}/dashboard`).set(O).expect(200);
    expect(d.body.totals.views).toBeGreaterThanOrEqual(2);
    expect(d.body.totals.orders).toBeGreaterThanOrEqual(4);
    expect(d.body.totals.revenueMmk).toBe(8_000);
    expect(d.body.totals.discountMmk).toBe(42_000);
    expect(d.body.totals.conversion).toBeGreaterThan(0);
    const today = d.body.daily[d.body.daily.length - 1];
    expect(today.views).toBeGreaterThanOrEqual(2);
    expect(today.orders).toBeGreaterThanOrEqual(4);
    expect(d.body.ticketTypes.map((t: any) => t.name)).toEqual(['=Kids', 'Standard', 'VIP']);
    const outsider = await consumer();
    await http.get(`${base()}/dashboard`).set(outsider.h).expect(403);
    void payments;
  });
});
