/**
 * Phase 1 end-to-end flow over HTTP against a real PostgreSQL (DATABASE_URL, migrated + seeded).
 * Skipped when DATABASE_URL is not set. Every run uses fresh random emails/phones, so no cleanup is needed.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { TicketTokenService } from '../src/modules/tickets/ticket-token.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(60_000);

run('Phase 1: organizers, events, moderation, free registration, QR', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  const tag = randomBytes(4).toString('hex');
  const phone = () => `09${randomInt(700_000_000, 799_999_999)}`;

  async function consumerLogin() {
    const p = phone();
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return r2.body.accessToken as string;
  }

  async function acceptInvite(url: string, password: string) {
    const token = url.split('/invite/')[1];
    await http.get(`/v1/auth/invitations/${token}`).expect(200);
    const r = await http.post(`/v1/auth/invitations/${token}/accept`).send({ password, displayName: 'Test' }).expect(200);
    return r.body.accessToken as string;
  }

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    // Fresh supertest agent per call (request(server).post(...))
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
  });

  afterAll(() => app?.close());

  it('runs the whole organizer → admin → consumer flow', async () => {
    // Admin via CLI-style invite
    const adminInvite = await app.get(AuthService).createInvitation({ email: `admin-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const admin = await acceptInvite(adminInvite.url, 'admin-password-123');
    const A = { Authorization: `Bearer ${admin}` };

    // Password login works too; wrong password is rejected
    await http.post('/v1/auth/password/login').send({ email: `admin-${tag}@e2e.test`, password: 'admin-password-123' }).expect(200);
    await http.post('/v1/auth/password/login').send({ email: `admin-${tag}@e2e.test`, password: 'nope' }).expect(401);

    // Admin creates an organization; owner accepts the invite
    const created = await http
      .post('/v1/admin/organizations')
      .set(A)
      .send({ name: `E2E Org ${tag}`, slug: `e2e-${tag}`, ownerEmail: `owner-${tag}@e2e.test` })
      .expect(201);
    const orgId = created.body.organization.id;
    const owner = await acceptInvite(created.body.inviteUrl, 'owner-password-123');
    const O = { Authorization: `Bearer ${owner}` };

    const me = await http.get('/v1/auth/me').set(O).expect(200);
    expect(me.body.organizations).toEqual([expect.objectContaining({ id: orgId, role: 'ORG_OWNER' })]);

    // A consumer cannot touch the organization or admin routes
    const consumer = await consumerLogin();
    const C = { Authorization: `Bearer ${consumer}` };
    await http.get(`/v1/organizations/${orgId}/events`).set(C).expect(403);
    await http.get('/v1/admin/organizations').set(C).expect(403);

    // Owner creates a free event (bilingual) with a ticket type of quota 2
    const cats = await http.get('/v1/categories').expect(200);
    const sub = cats.body.find((c: any) => c.slug === 'lifestyle-social').children[0];
    const start = new Date(Date.now() + 7 * 864e5);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: sub.id,
        title: `E2E Food Fair ${tag}`,
        titleMy: 'အစားအသောက်ပွဲ',
        summary: 'Street food',
        format: 'IN_PERSON',
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 4 * 36e5).toISOString(),
        venue: { name: 'People’s Park', city: 'Yangon' },
      })
      .expect(201);
    const eventId = ev.body.id;
    expect(ev.body.status).toBe('DRAFT');

    // Submitting without ticket types fails with a helpful list
    const notReady = await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(400);
    expect(notReady.body.problems).toContain('Add at least one ticket type');

    const tt = await http
      .post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`)
      .set(O)
      .send({ name: 'General', nameMy: 'အထွေထွေ', priceMmk: 0, quota: 2, maxPerOrder: 2 })
      .expect(201);

    // Unverified organizer → goes to review, not public yet
    const submitted = await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    expect(submitted.body.status).toBe('SUBMITTED');
    await http.get(`/v1/events/${eventId}`).expect(404);

    // Admin sees it in the queue and approves
    const queue = await http.get('/v1/admin/events?status=SUBMITTED').set(A).expect(200);
    expect(queue.body.map((e: any) => e.id)).toContain(eventId);
    const approved = await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    expect(approved.body.status).toBe('PUBLISHED');

    // Public list + search (English and Myanmar) + category filter
    const byEn = await http.get(`/v1/events?q=${encodeURIComponent(`Food Fair ${tag}`)}`).expect(200);
    expect(byEn.body.items.map((e: any) => e.id)).toContain(eventId);
    const byMy = await http.get(`/v1/events?q=${encodeURIComponent('အစားအသောက်')}&category=lifestyle-social`).expect(200);
    expect(byMy.body.items.map((e: any) => e.id)).toContain(eventId);
    const detail = await http.get(`/v1/events/${ev.body.slug}`).expect(200);
    expect(detail.body).toMatchObject({ isFree: true, minPriceMmk: 0, soldOut: false });

    // Registration: needs login; respects per-person limit and quota (never oversells)
    await http.post(`/v1/events/${eventId}/registrations`).send({ ticketTypeId: tt.body.id, quantity: 1 }).expect(401);
    await http.post(`/v1/events/${eventId}/registrations`).set(C).send({ ticketTypeId: tt.body.id, quantity: 3 }).expect(400);
    await http.post(`/v1/events/${eventId}/registrations`).set(C).send({ ticketTypeId: tt.body.id, quantity: 1 }).expect(201);

    const others = await Promise.all([consumerLogin(), consumerLogin(), consumerLogin()]);
    const results = await Promise.all(
      others.map((t) => http.post(`/v1/events/${eventId}/registrations`).set({ Authorization: `Bearer ${t}` }).send({ ticketTypeId: tt.body.id, quantity: 1 })),
    );
    expect(results.filter((r) => r.status === 201)).toHaveLength(1); // only 1 seat was left
    expect(results.filter((r) => r.status === 409)).toHaveLength(2);
    const soldOut = await http.get(`/v1/events/${eventId}`).expect(200);
    expect(soldOut.body.soldOut).toBe(true);

    // My tickets carry a QR that verifies with the published key
    const mine = await http.get('/v1/me/tickets').set(C).expect(200);
    expect(mine.body).toHaveLength(1);
    const claims = app.get(TicketTokenService).verify(mine.body[0].qr);
    expect(claims).toMatchObject({ tid: mine.body[0].id, eid: eventId, tt: tt.body.id, v: 1 });
    const key = await http.get('/v1/meta/ticket-public-key').expect(200);
    expect(Buffer.from(key.body.publicKey, 'base64')).toHaveLength(32);

    // Organizer sees attendees; ticket quota cannot drop below issued
    const attendees = await http.get(`/v1/organizations/${orgId}/events/${eventId}/attendees`).set(O).expect(200);
    expect(attendees.body).toHaveLength(2);
    await http.patch(`/v1/organizations/${orgId}/events/${eventId}/ticket-types/${tt.body.id}`).set(O).send({ quota: 1 }).expect(400);

    // Unverified organizer editing a published event → back to review
    const edited = await http.patch(`/v1/organizations/${orgId}/events/${eventId}`).set(O).send({ summary: 'Updated' }).expect(200);
    expect(edited.body).toMatchObject({ status: 'SUBMITTED', reReviewRequired: true });

    // After KYC approval the organizer publishes directly
    await http.patch(`/v1/admin/organizations/${orgId}/kyc`).set(A).send({ status: 'APPROVED' }).expect(200);
    const ev2 = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: sub.id,
        title: `E2E Online Talk ${tag}`,
        format: 'ONLINE',
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 36e5).toISOString(),
      })
      .expect(201);
    await http.post(`/v1/organizations/${orgId}/events/${ev2.body.id}/ticket-types`).set(O).send({ name: 'Free', priceMmk: 0, quota: 100 }).expect(201);
    const direct = await http.post(`/v1/organizations/${orgId}/events/${ev2.body.id}/submit`).set(O).expect(200);
    expect(direct.body.status).toBe('PUBLISHED');

    // Paid tickets are not sold yet in Phase 1
    const paid = await http.post(`/v1/organizations/${orgId}/events/${ev2.body.id}/ticket-types`).set(O).send({ name: 'VIP', priceMmk: 5000, quota: 10 }).expect(201);
    await http.post(`/v1/events/${ev2.body.id}/registrations`).set(C).send({ ticketTypeId: paid.body.id, quantity: 1 }).expect(400);
  });

  it('limits login codes per phone number, not just per IP', async () => {
    const p = phone();
    const svc = app.get(AuthService) as any;
    // Simulate 5 recent challenges for this phone (bypassing the 60s cooldown between requests)
    for (let i = 0; i < 5; i++) {
      await svc.prisma.otpChallenge.create({ data: { phone: `+959${p.slice(2)}`, codeHash: 'x', expiresAt: new Date(Date.now() + 6e4), createdAt: new Date(Date.now() - (i + 2) * 6e4) } });
    }
    const r = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(429);
    expect(r.body.message).toMatch(/this number/);
  });
});
