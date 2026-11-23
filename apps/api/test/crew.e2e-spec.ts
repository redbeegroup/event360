/**
 * Phase 3 crew check-in over HTTP against a real PostgreSQL (DATABASE_URL, migrated + seeded).
 * Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { TicketTokenService } from '../src/modules/tickets/ticket-token.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

run('Phase 3: crew check-in', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  const tag = randomBytes(4).toString('hex');
  const phone = () => `09${randomInt(700_000_000, 799_999_999)}`;
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

  async function consumerLogin() {
    const p = phone();
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return r2.body.accessToken as string;
  }

  async function acceptInvite(url: string, password: string, displayName = 'Test') {
    const token = url.split('/invite/')[1];
    const r = await http.post(`/v1/auth/invitations/${token}/accept`).send({ password, displayName }).expect(200);
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
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
  });

  afterAll(() => app?.close());

  /** A published free event of a fresh organization (owner token, ids). */
  async function publishedEvent(A: Record<string, string>, orgId: string, O: Record<string, string>, name: string) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 2 * 36e5);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: cats.body[0].children[0].id,
        title: `${name} ${tag}`,
        format: 'IN_PERSON',
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 4 * 36e5).toISOString(),
        venue: { name: 'Hall', city: 'Yangon' },
      })
      .expect(201);
    const tt = await http
      .post(`/v1/organizations/${orgId}/events/${ev.body.id}/ticket-types`)
      .set(O)
      .send({ name: 'General', priceMmk: 0, quota: 50, maxPerOrder: 4 })
      .expect(201);
    await http.post(`/v1/organizations/${orgId}/events/${ev.body.id}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${ev.body.id}/approve`).set(A).expect(200);
    return { eventId: ev.body.id as string, ttId: tt.body.id as string };
  }

  it('checks tickets in with crew accounts and volunteer event codes', async () => {
    const adminInvite = await app.get(AuthService).createInvitation({ email: `admin-c-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const A = bearer(await acceptInvite(adminInvite.url, 'admin-password-123'));
    const created = await http
      .post('/v1/admin/organizations')
      .set(A)
      .send({ name: `Crew Org ${tag}`, slug: `crew-${tag}`, ownerEmail: `owner-c-${tag}@e2e.test` })
      .expect(201);
    const orgId = created.body.organization.id;
    const O = bearer(await acceptInvite(created.body.inviteUrl, 'owner-password-123'));
    const { eventId, ttId } = await publishedEvent(A, orgId, O, 'Crew Concert');
    const other = await publishedEvent(A, orgId, O, 'Other Show');

    // Owner invites a crew member
    const inv = await http.post(`/v1/organizations/${orgId}/invitations`).set(O).send({ email: `crew-${tag}@e2e.test`, role: 'CREW' }).expect(201);
    const CR = bearer(await acceptInvite(inv.body.inviteUrl, 'crew-password-123', 'Door Aung'));
    // Crew cannot manage the organization or create codes
    await http.get(`/v1/organizations/${orgId}/events`).set(CR).expect(403);
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/crew-codes`).set(CR).send({ label: 'x' }).expect(403);

    const crewEvents = await http.get('/v1/crew/events').set(CR).expect(200);
    expect(crewEvents.body.map((e: any) => e.id)).toEqual(expect.arrayContaining([eventId, other.eventId]));

    // Two attendees register
    const C1 = bearer(await consumerLogin());
    const C2 = bearer(await consumerLogin());
    await http.post(`/v1/events/${eventId}/registrations`).set(C1).send({ ticketTypeId: ttId, quantity: 2 }).expect(201);
    await http.post(`/v1/events/${eventId}/registrations`).set(C2).send({ ticketTypeId: ttId, quantity: 1 }).expect(201);
    await http.post(`/v1/events/${other.eventId}/registrations`).set(C2).send({ ticketTypeId: other.ttId, quantity: 1 }).expect(201);
    const t1 = (await http.get('/v1/me/tickets').set(C1).expect(200)).body;
    const t2 = (await http.get('/v1/me/tickets').set(C2).expect(200)).body;
    const [qrA, qrB] = t1.map((t: any) => t.qr);
    const qrC = t2.find((t: any) => t.event.id === eventId).qr;
    const qrOther = t2.find((t: any) => t.event.id === other.eventId).qr;

    // A consumer cannot scan
    await http.post(`/v1/crew/events/${eventId}/scan`).set(C1).send({ qr: qrA }).expect(403);

    // Accepted, then a second scan is a duplicate with where/when
    const ok = await http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: qrA, gate: 'Main gate', deviceId: 'dev-1' }).expect(200);
    expect(ok.body).toMatchObject({ result: 'ACCEPTED', ticket: { status: 'CHECKED_IN', ticketType: { name: 'General' } } });
    const dup = await http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: qrA, gate: 'VIP' }).expect(200);
    expect(dup.body).toMatchObject({ result: 'ALREADY_CHECKED_IN', ticket: { checkedIn: { gate: 'Main gate', by: 'Door Aung' } } });

    // Wrong event, tampered QR
    const wrong = await http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: qrOther }).expect(200);
    expect(wrong.body).toMatchObject({ result: 'WRONG_EVENT', otherEvent: { title: `Other Show ${tag}` } });
    const [p, s] = qrB.split('.');
    const tampered = `${p}.${s.slice(0, -4)}AAAA`;
    expect((await http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: tampered }).expect(200)).body.result).toBe('INVALID');
    const forged = app.get(TicketTokenService).sign({ tid: t1[1].id, eid: eventId, tt: ttId, v: 2 }); // stale QR version
    expect((await http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: forged }).expect(200)).body).toMatchObject({ result: 'INVALID', reason: 'outdated_qr' });

    // Two gates scanning the same ticket at once: exactly one wins
    const race = await Promise.all([
      http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: qrB, gate: 'A' }),
      http.post(`/v1/crew/events/${eventId}/scan`).set(CR).send({ qr: qrB, gate: 'B' }),
    ]);
    expect(race.map((r) => r.body.result).sort()).toEqual(['ACCEPTED', 'ALREADY_CHECKED_IN']);

    // Volunteer event code: created by the owner, redeemed by a device, scoped to this event only
    const code = await http.post(`/v1/organizations/${orgId}/events/${eventId}/crew-codes`).set(O).send({ label: 'Volunteers', gate: 'Side door' }).expect(201);
    expect(code.body.code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
    await http.post('/v1/crew/redeem').send({ code: 'ZZZZ-ZZZZ', deviceName: 'x' }).expect(401);
    const red = await http.post('/v1/crew/redeem').send({ code: code.body.code.toLowerCase().replace('-', ' '), deviceName: 'Side phone' }).expect(200);
    expect(red.body).toMatchObject({ gate: 'Side door', event: { id: eventId } });
    const V = bearer(red.body.accessToken);
    await http.get('/v1/auth/me').set(V).expect(401); // crew sessions only work on check-in routes
    await http.get(`/v1/crew/events/${other.eventId}/stats`).set(V).expect(403);
    expect((await http.get('/v1/crew/events').set(V).expect(200)).body.map((e: any) => e.id)).toEqual([eventId]);

    // Manual lookup by phone digits / ticket code, then manual check-in by the volunteer
    const byCode = await http.get(`/v1/crew/events/${eventId}/search`).query({ q: t2.find((t: any) => t.event.id === eventId).id.slice(0, 8) }).set(V).expect(200);
    const target = byCode.body.find((t: any) => t.status === 'VALID');
    expect(target).toBeTruthy();
    const manual = await http.post(`/v1/crew/events/${eventId}/tickets/${target.id}/checkin`).set(V).send({ gate: 'Side door' }).expect(200);
    expect(manual.body).toMatchObject({ result: 'ACCEPTED', ticket: { checkedIn: { by: 'Side phone' } } });
    expect((await http.post(`/v1/crew/events/${eventId}/scan`).set(V).send({ qr: qrC }).expect(200)).body.result).toBe('ALREADY_CHECKED_IN');

    // Undo, then offline sync: the device saw it twice while offline → one accepted, one duplicate
    await http.post(`/v1/crew/events/${eventId}/tickets/${target.id}/undo`).set(V).expect(200);
    const notIn = await http.post(`/v1/crew/events/${eventId}/tickets/${target.id}/undo`).set(V).expect(409);
    expect(notIn.body).toMatchObject({ message: 'This ticket is not checked in', reasonCode: 'NOT_CHECKED_IN' });
    const now = Date.now();
    const sync = await http
      .post(`/v1/crew/events/${eventId}/sync`)
      .set(V)
      .send({
        scans: [
          { clientId: 'b', qr: qrC, gate: 'Side door', scannedAt: new Date(now - 30_000).toISOString() },
          { clientId: 'a', qr: qrC, gate: 'Side door', scannedAt: new Date(now - 60_000).toISOString() },
          { clientId: 'c', ticketId: target.id, method: 'MANUAL', scannedAt: new Date(now - 10_000).toISOString() },
        ],
      })
      .expect(200);
    const byId = Object.fromEntries(sync.body.results.map((r: any) => [r.clientId, r.result]));
    expect(byId).toEqual({ a: 'ACCEPTED', b: 'ALREADY_CHECKED_IN', c: 'ALREADY_CHECKED_IN' });

    // Manifest for offline use and stats
    const man = await http.get(`/v1/crew/events/${eventId}/manifest`).set(V).expect(200);
    expect(man.body.tickets).toHaveLength(3);
    expect(Buffer.from(man.body.publicKey, 'base64')).toHaveLength(32);
    const stats = await http.get(`/v1/crew/events/${eventId}/stats`).set(CR).expect(200);
    expect(stats.body).toMatchObject({ registered: 3, checkedIn: 3, byTicketType: [{ registered: 3, checkedIn: 3 }] });
    expect(stats.body.byGate.map((g: any) => g.gate)).toEqual(expect.arrayContaining(['Main gate', 'Side door']));
    expect(stats.body.recent.some((r: any) => r.undone)).toBe(true);
    const att = await http.get(`/v1/organizations/${orgId}/events/${eventId}/attendance`).set(O).expect(200);
    expect(att.body.checkedIn).toBe(3);

    // Revoking the code ends the volunteer session
    const codes = await http.get(`/v1/organizations/${orgId}/events/${eventId}/crew-codes`).set(O).expect(200);
    expect(codes.body[0]).toMatchObject({ label: 'Volunteers', devices: 1, active: true });
    await http.delete(`/v1/organizations/${orgId}/events/${eventId}/crew-codes/${codes.body[0].id}`).set(O).expect(200);
    await http.get(`/v1/crew/events/${eventId}/stats`).set(V).expect(401);
    await http.post('/v1/crew/redeem').send({ code: code.body.code, deviceName: 'again' }).expect(401);
  });
});
