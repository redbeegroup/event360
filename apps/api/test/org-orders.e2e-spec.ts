/**
 * Organizer order list and detail: scope, filters, search, keyset paging, privacy of the response, roles.
 * Rows are inserted directly so that buyers, phones, timestamps and statuses are exact. Skipped without DATABASE_URL.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt, randomUUID } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(120_000);

run('Organizer orders', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  let A: Record<string, string>, O: Record<string, string>, F: Record<string, string>, M: Record<string, string>, C: Record<string, string>;
  let O2: Record<string, string>, X: Record<string, string>;
  let orgId: string, eventId: string, ttId: string, otherOrgId: string, otherEventId: string;
  let buyer: { id: string; phone: string }, namedBuyer: { id: string; phone: string };
  const url = (ev = eventId, org = orgId) => `/v1/organizations/${org}/events/${ev}/orders`;
  const list = (qs = '', h = O) => http.get(`${url()}${qs}`).set(h);
  const localPhone = (e164: string) => `0${e164.slice(3)}`;

  async function acceptInvite(u: string) {
    const r = await http.post(`/v1/auth/invitations/${u.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  async function makeUser(displayName: string | null) {
    const phone = `+959${randomInt(700_000_000, 799_999_999)}`;
    const u = await prisma.user.create({ data: { phone, displayName } });
    return { id: u.id, phone };
  }
  async function makeOrder(o: { userId?: string; eventId?: string; status?: any; total?: bigint; channel?: string; createdAt?: Date; id?: string; needsReview?: boolean; reviewNote?: string; seatKeys?: string[]; qty?: number } = {}) {
    return prisma.order.create({
      data: {
        ...(o.id ? { id: o.id } : {}),
        userId: o.userId ?? buyer.id,
        eventId: o.eventId ?? eventId,
        status: o.status ?? 'PAID',
        subtotalMmk: o.total ?? 10_000n,
        totalMmk: o.total ?? 10_000n,
        commissionMmk: 500n,
        channel: o.channel ?? 'APP',
        paidAt: o.status === 'PENDING_PAYMENT' ? null : new Date(),
        holdExpiresAt: new Date(Date.now() + 600_000),
        needsReview: o.needsReview ?? false,
        reviewNote: o.reviewNote ?? null,
        ...(o.createdAt ? { createdAt: o.createdAt } : {}),
        items: { create: [{ ticketTypeId: ttId, quantity: o.qty ?? 1, unitPriceMmk: 10_000n, seatKeys: o.seatKeys ?? [] }] },
      },
    });
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

    const adm = await app.get(AuthService).createInvitation({ email: `adm-oo-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const mkOrg = async (n: string) => {
      const org = await http.post('/v1/admin/organizations').set(A).send({ name: `OO Org ${n} ${tag}`, slug: `oo${n}-${tag}`, ownerEmail: `own${n}-oo-${tag}@e2e.test` }).expect(201);
      return { id: org.body.organization.id as string, owner: await acceptInvite(org.body.inviteUrl) };
    };
    const a = await mkOrg('a');
    const b = await mkOrg('b');
    orgId = a.id;
    O = a.owner;
    otherOrgId = b.id;
    O2 = b.owner;
    const member = async (role: string, n: string) => {
      const inv = await http.post(`/v1/organizations/${orgId}/invitations`).set(O).send({ email: `${n}-oo-${tag}@e2e.test`, role }).expect(201);
      return acceptInvite(inv.body.inviteUrl);
    };
    F = await member('ORG_FINANCE', 'fin');
    M = await member('ORG_MANAGER', 'mgr');
    C = await member('CREW', 'crew');
    X = O2; // an owner of another organization
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 7 * 86400e3);
    const mkEvent = async (org: string, h: Record<string, string>, title: string) => {
      const ev = await http
        .post(`/v1/organizations/${org}/events`)
        .set(h)
        .send({ categoryId: cats.body[0].children[0].id, title, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
        .expect(201);
      const tt = await http.post(`/v1/organizations/${org}/events/${ev.body.id}/ticket-types`).set(h).send({ name: 'Standard', priceMmk: 10_000, quota: 500, maxPerOrder: 10 }).expect(201);
      return { id: ev.body.id as string, tt: tt.body.id as string };
    };
    const e1 = await mkEvent(orgId, O, `Orders Show ${tag}`);
    eventId = e1.id;
    ttId = e1.tt;
    otherEventId = (await mkEvent(otherOrgId, O2, `Other Show ${tag}`)).id;
    buyer = await makeUser(null);
    namedBuyer = await makeUser(`Zawgyi Mya ${tag}`);
  });
  afterAll(() => app?.close());

  describe('scope, privacy and roles', () => {
    let paid: string, comp: string, free: string, review: string, pending: string;
    beforeAll(async () => {
      paid = (await makeOrder({ userId: namedBuyer.id, qty: 2, total: 20_000n })).id;
      comp = (await makeOrder({ channel: 'COMP', total: 0n })).id;
      free = (await makeOrder({ status: 'CONFIRMED', total: 0n })).id;
      review = (await makeOrder({ needsReview: true, reviewNote: 'Paid after hold expired SECRET-NOTE' })).id;
      pending = (await makeOrder({ status: 'PENDING_PAYMENT' })).id;
      await prisma.payment.create({ data: { orderId: paid, provider: 'MOCK', providerRef: `PROVREF-SECRET-${tag}`, amountMmk: 20_000n, status: 'SUCCEEDED' } });
    });

    it('lists paid-side orders newest first with number and masked phone, and leaks nothing', async () => {
      const r = await list().expect(200);
      const ids = r.body.orders.map((o: any) => o.id);
      expect(ids).toEqual(expect.arrayContaining([paid, review, pending]));
      expect(ids).not.toContain(comp);
      expect(ids).not.toContain(free);
      const times = r.body.orders.map((o: any) => Date.parse(o.createdAt));
      expect([...times].sort((x, y) => y - x)).toEqual(times);
      const row = r.body.orders.find((o: any) => o.id === paid);
      expect(row).toMatchObject({ number: paid.slice(0, 8).toUpperCase(), status: 'PAID', quantity: 2, totalMmk: 20_000, discountMmk: 0, needsReview: false, holdExpiresAt: null });
      expect(row.buyer.name).toBe(`Zawgyi Mya ${tag}`);
      expect(row.buyer.phone).toMatch(/^09\d{2}•••\d{3}$/);
      const json = JSON.stringify(r.body);
      expect(json).not.toMatch(/reviewNote|providerRef|userId|SECRET/);
      expect(JSON.stringify(r.body.orders.map((o: any) => o.buyer))).not.toMatch(/\d{8}/);
      expect(Object.keys(row).sort()).toEqual(['buyer', 'createdAt', 'discountMmk', 'holdExpiresAt', 'id', 'needsReview', 'number', 'paidAt', 'quantity', 'status', 'totalMmk']);
    });

    it('a pending order carries holdExpiresAt, a paid one does not; needsReview shows without the note', async () => {
      const r = await list().expect(200);
      expect(r.body.orders.find((o: any) => o.id === pending).holdExpiresAt).not.toBeNull();
      expect(r.body.orders.find((o: any) => o.id === paid).holdExpiresAt).toBeNull();
      const rv = r.body.orders.find((o: any) => o.id === review);
      expect(rv.needsReview).toBe(true);
      expect(JSON.stringify(rv)).not.toMatch(/note|SECRET/i);
    });

    it('status filter returns only its statuses; unknown value is 400', async () => {
      await makeOrder({ status: 'REFUNDED' });
      await makeOrder({ status: 'FAILED' });
      await makeOrder({ status: 'EXPIRED' });
      await makeOrder({ status: 'CANCELLED' });
      const only = async (s: string, want: string[]) => {
        const r = await list(`?status=${s}&limit=100`).expect(200);
        const got = new Set(r.body.orders.map((o: any) => o.status));
        expect([...got].sort()).toEqual(want.sort());
      };
      await only('paid', ['PAID']);
      await only('refunded', ['REFUNDED']);
      await only('pending', ['PENDING_PAYMENT']);
      await only('incomplete', ['FAILED', 'EXPIRED', 'CANCELLED']);
      const all = await list('?limit=100').expect(200);
      expect(new Set(all.body.orders.map((o: any) => o.status))).toEqual(new Set(['PAID', 'REFUNDED', 'PENDING_PAYMENT', 'FAILED', 'EXPIRED', 'CANCELLED']));
      await list('?status=bogus').expect(400);
      await list('?limit=0').expect(400);
      await list('?limit=101').expect(400);
      await list(`?q=${'x'.repeat(61)}`).expect(400);
    });

    it('search by display name fragment, case-insensitive', async () => {
      const r = await list(`?q=${encodeURIComponent(`zAWgYi mYa ${tag}`.slice(2, 12 + tag.length))}`).expect(200);
      expect(r.body.orders.map((o: any) => o.id)).toEqual([paid]);
    });

    it('search by the buyer number typed locally, with spaces', async () => {
      const l = localPhone(namedBuyer.phone); // 09 7xx xxx xxx
      const spaced = `${l.slice(0, 2)} ${l.slice(2, 5)} ${l.slice(5, 8)} ${l.slice(8)}`;
      const r = await list(`?q=${encodeURIComponent(spaced)}`).expect(200);
      expect(r.body.orders.map((o: any) => o.id)).toEqual([paid]);
      const e = await list(`?q=${encodeURIComponent(namedBuyer.phone)}`).expect(200);
      expect(e.body.orders.map((o: any) => o.id)).toEqual([paid]);
    });

    it('two digits do not search phones; they only match order-number prefixes', async () => {
      const q = '97'; // every test phone contains 97 or starts +9597 here
      const r = await list(`?q=${q}&limit=100`).expect(200);
      for (const o of r.body.orders) expect(o.id.toLowerCase().startsWith(q)).toBe(true);
    });

    it('search by the first 8 characters of the order id', async () => {
      const r = await list(`?q=${paid.slice(0, 8).toUpperCase()}`).expect(200);
      expect(r.body.orders.map((o: any) => o.id)).toEqual([paid]);
      const shorter = await list(`?q=${paid.slice(0, 5)}`).expect(200);
      expect(shorter.body.orders.map((o: any) => o.id)).toContain(paid);
    });

    it('a LIKE wildcard in q matches nothing instead of everything', async () => {
      for (const q of ['%', '_', '%%%', '\\']) {
        const r = await list(`?q=${encodeURIComponent(q)}`).expect(200);
        expect(r.body.orders).toEqual([]);
      }
    });

    it('a literal % or _ in a display name is found by that text', async () => {
      const u = await makeUser(`Sale 100%_off ${tag}`);
      const o = await makeOrder({ userId: u.id });
      for (const q of ['100%_off', `100%_off ${tag}`]) {
        const r = await list(`?q=${encodeURIComponent(q)}`).expect(200);
        expect(r.body.orders.map((x: any) => x.id)).toEqual([o.id]);
      }
      const none = await list(`?q=${encodeURIComponent('100_')}`).expect(200);
      expect(none.body.orders.map((x: any) => x.id)).toEqual([]);
    });

    it('roles: owner, manager and finance 200; crew and outsider 403', async () => {
      await list('', O).expect(200);
      await list('', M).expect(200);
      await list('', F).expect(200);
      await list('', C).expect(403);
      await list('', X).expect(403);
      await http.get(`${url()}/${paid}`).set(C).expect(403);
      await http.get(`${url()}/${paid}`).set(X).expect(403);
      await http.get(`${url()}/${paid}`).set(M).expect(200);
      await http.get(`${url()}/${paid}`).set(F).expect(200);
    });

    it("another organization's event or order is a 404, never 403", async () => {
      // own orgId, other org's event
      await http.get(url(otherEventId)).set(O).expect(404);
      const foreign = await makeOrder({ eventId: otherEventId });
      await http.get(`${url(otherEventId)}/${foreign.id}`).set(O).expect(404);
      // own orgId and own event, foreign order id
      await http.get(`${url()}/${foreign.id}`).set(O).expect(404);
      // a missing order id looks the same
      await http.get(`${url()}/${randomUUID()}`).set(O).expect(404);
      // comp and free orders have no detail either
      await http.get(`${url()}/${comp}`).set(O).expect(404);
      await http.get(`${url()}/${free}`).set(O).expect(404);
      // the foreign order never appears in the list
      const r = await list('?limit=100').expect(200);
      expect(r.body.orders.map((o: any) => o.id)).not.toContain(foreign.id);
    });
  });

  describe('detail', () => {
    it('a seated order shows seat labels (falling back to the key), tickets and the promo code', async () => {
      await prisma.eventSeat.createMany({
        data: [
          { eventId, seatKey: `S-${tag}-1`, sectionKey: 'S', rowLabel: 'A', seatLabel: '1', label: 'Row A seat 1', labelMy: 'အတန်း A ထိုင်ခုံ 1', ticketTypeId: ttId },
          { eventId, seatKey: `S-${tag}-2`, sectionKey: 'S', rowLabel: 'A', seatLabel: '2', label: 'Row A seat 2', ticketTypeId: ttId },
        ],
      });
      const promo = await prisma.promoCode.create({ data: { eventId, code: `OO${tag}`.toUpperCase(), kind: 'PERCENT', value: 10, createdById: buyer.id } });
      const o = await makeOrder({ seatKeys: [`S-${tag}-1`, `S-${tag}-2`, `NOSEAT-${tag}`], qty: 3, total: 27_000n });
      await prisma.order.update({ where: { id: o.id }, data: { promoCodeId: promo.id, discountMmk: 3_000n } });
      await prisma.ticket.createMany({
        data: [
          { orderId: o.id, ticketTypeId: ttId, holderUserId: buyer.id, status: 'VALID' },
          { orderId: o.id, ticketTypeId: ttId, holderUserId: buyer.id, status: 'CHECKED_IN' },
          { orderId: o.id, ticketTypeId: ttId, holderUserId: buyer.id, status: 'VOID' },
        ],
      });
      const r = await http.get(`${url()}/${o.id}`).set(O).expect(200);
      expect(r.body).toMatchObject({ id: o.id, number: o.id.slice(0, 8).toUpperCase(), subtotalMmk: 27_000, commissionMmk: 500, discountMmk: 3_000, promoCode: promo.code, groupDiscountBp: null, quantity: 3 });
      expect(r.body.items).toHaveLength(1);
      expect(r.body.items[0]).toMatchObject({ ticketTypeId: ttId, name: 'Standard', nameMy: null, quantity: 3, unitPriceMmk: 10_000 });
      expect(r.body.items[0].seats).toEqual([
        { label: 'Row A seat 1', labelMy: 'အတန်း A ထိုင်ခုံ 1' },
        { label: 'Row A seat 2', labelMy: null },
        { label: `NOSEAT-${tag}`, labelMy: null },
      ]);
      expect(r.body.tickets).toEqual({ total: 3, valid: 1, checkedIn: 1, void: 1 });
      expect(r.body.buyer.phone).toMatch(/^09\d{2}•••\d{3}$/);
    });

    it('payments are newest first, refunds are trimmed, and no secrets come back', async () => {
      const o = await makeOrder({ status: 'REFUNDED' });
      const t0 = Date.now() - 60_000;
      await prisma.payment.create({ data: { orderId: o.id, provider: 'MOCK', providerRef: `PREF-SECRET-1-${tag}`, amountMmk: 10_000n, status: 'FAILED', createdAt: new Date(t0) } });
      await prisma.payment.create({ data: { orderId: o.id, provider: 'WAVEPAY', providerRef: `PREF-SECRET-2-${tag}`, amountMmk: 10_000n, status: 'SUCCEEDED', createdAt: new Date(t0 + 30_000) } });
      const pay = await prisma.payment.findFirstOrThrow({ where: { orderId: o.id, status: 'SUCCEEDED' } });
      await prisma.refund.create({
        data: { orderId: o.id, paymentId: pay.id, amountMmk: 10_000n, status: 'SUCCEEDED', reason: 'REASON-SECRET', reference: 'REF-SECRET', error: 'ERR-SECRET', providerRef: 'RP-SECRET', createdById: buyer.id, completedAt: new Date() },
      });
      const r = await http.get(`${url()}/${o.id}`).set(O).expect(200);
      expect(r.body.payments.map((p: any) => [p.provider, p.status])).toEqual([['WAVEPAY', 'SUCCEEDED'], ['MOCK', 'FAILED']]);
      expect(Object.keys(r.body.payments[0]).sort()).toEqual(['createdAt', 'provider', 'status']);
      expect(r.body.refunds).toHaveLength(1);
      expect(r.body.refunds[0]).toMatchObject({ status: 'SUCCEEDED', amountMmk: 10_000 });
      expect(Object.keys(r.body.refunds[0]).sort()).toEqual(['amountMmk', 'completedAt', 'createdAt', 'status']);
      expect(r.body.refunds[0].completedAt).not.toBeNull();
      expect(JSON.stringify(r.body)).not.toMatch(/SECRET|reviewNote|providerRef|userId|reason|error|reference/);
      expect(r.body.status).toBe('REFUNDED');
    });

    it('payments are capped at five', async () => {
      const o = await makeOrder();
      for (let i = 0; i < 7; i++) await prisma.payment.create({ data: { orderId: o.id, provider: 'MOCK', amountMmk: 10_000n, status: 'FAILED', createdAt: new Date(Date.now() - i * 1000) } });
      const r = await http.get(`${url()}/${o.id}`).set(O).expect(200);
      expect(r.body.payments).toHaveLength(5);
    });
  });

  describe('paging', () => {
    let pageEventId: string, pageTt: string;
    const ids: string[] = [];
    beforeAll(async () => {
      const cats = await http.get('/v1/categories').expect(200);
      const start = new Date(Date.now() + 7 * 86400e3);
      const ev = await http
        .post(`/v1/organizations/${orgId}/events`)
        .set(O)
        .send({ categoryId: cats.body[0].children[0].id, title: `Paging Show ${tag}`, format: 'IN_PERSON', venue: { name: 'Hall', city: 'Yangon' }, startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
        .expect(201);
      pageEventId = ev.body.id;
      pageTt = (await http.post(`/v1/organizations/${orgId}/events/${pageEventId}/ticket-types`).set(O).send({ name: 'Std', priceMmk: 10_000, quota: 500, maxPerOrder: 10 }).expect(201)).body.id;
      const base = Date.now() - 7_200_000;
      const tie = new Date(base + 40_500); // lands mid-list, so the tied block straddles the first page boundary
      for (let i = 0; i < 70; i++) {
        const o = await prisma.order.create({
          data: {
            userId: buyer.id,
            eventId: pageEventId,
            status: 'PAID',
            subtotalMmk: 10_000n,
            totalMmk: 10_000n,
            paidAt: new Date(),
            createdAt: i < 10 ? tie : new Date(base + i * 1000),
            items: { create: [{ ticketTypeId: pageTt, quantity: 1, unitPriceMmk: 10_000n }] },
          },
        });
        ids.push(o.id);
      }
    });
    const page = (cursor?: string, limit = 30) => http.get(url(pageEventId)).query({ limit, ...(cursor ? { cursor } : {}) }).set(O);

    it('70 orders with 10 sharing a createdAt page as 30+30+10, no repeats, strict order', async () => {
      const p1 = await page().expect(200);
      expect(p1.body.orders).toHaveLength(30);
      expect(p1.body.nextCursor).toEqual(expect.any(String));
      const p2 = await page(p1.body.nextCursor).expect(200);
      expect(p2.body.orders).toHaveLength(30);
      expect(p2.body.nextCursor).toEqual(expect.any(String));
      const p3 = await page(p2.body.nextCursor).expect(200);
      expect(p3.body.orders).toHaveLength(10);
      expect(p3.body.nextCursor).toBeNull();
      const all = [...p1.body.orders, ...p2.body.orders, ...p3.body.orders];
      expect(new Set(all.map((o: any) => o.id)).size).toBe(70);
      expect(new Set(all.map((o: any) => o.id))).toEqual(new Set(ids));
      for (let i = 1; i < all.length; i++) {
        const a = all[i - 1], b = all[i];
        const ta = Date.parse(a.createdAt), tb = Date.parse(b.createdAt);
        expect(ta > tb || (ta === tb && a.id > b.id)).toBe(true);
      }
      const tied = all.map((o: any, i: number) => [o.createdAt, i]).filter(([c]: any) => c === new Date(Date.parse(all[29].createdAt)).toISOString());
      expect(tied.length).toBe(10); // the ten rows with one createdAt sit across the 30-row boundary
      expect(tied.some(([, i]: any) => i < 30) && tied.some(([, i]: any) => i >= 30)).toBe(true);
    });

    it('a ten-way tie split across pages by a small limit keeps every row once', async () => {
      const seen: string[] = [];
      let cursor: string | undefined;
      do {
        const r = await page(cursor, 7).expect(200);
        seen.push(...r.body.orders.map((o: any) => o.id));
        cursor = r.body.nextCursor ?? undefined;
      } while (cursor);
      expect(seen).toHaveLength(70);
      expect(new Set(seen).size).toBe(70);
    });

    it('a new order between page 1 and page 2 causes no repeat', async () => {
      const p1 = await page().expect(200);
      const fresh = await prisma.order.create({
        data: { userId: buyer.id, eventId: pageEventId, status: 'PAID', subtotalMmk: 10_000n, totalMmk: 10_000n, paidAt: new Date(), items: { create: [{ ticketTypeId: pageTt, quantity: 1, unitPriceMmk: 10_000n }] } },
      });
      const p2 = await page(p1.body.nextCursor).expect(200);
      const first = new Set(p1.body.orders.map((o: any) => o.id));
      for (const o of p2.body.orders) {
        expect(first.has(o.id)).toBe(false);
        expect(o.id).not.toBe(fresh.id);
      }
      expect(p2.body.orders).toHaveLength(30);
    });

    it('a malformed cursor is a 400', async () => {
      for (const c of ['not-a-cursor', Buffer.from('nope').toString('base64url'), Buffer.from('2026-01-01T00:00:00.000Z|not-a-uuid').toString('base64url'), Buffer.from(`garbage|${randomUUID()}`).toString('base64url'), '%%%']) {
        await page(c).expect(400);
      }
    });
  });
});
