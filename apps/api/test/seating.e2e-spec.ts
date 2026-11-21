/**
 * Reserved seating over HTTP against a real PostgreSQL. Skipped when DATABASE_URL is not set.
 */
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import { readFileSync } from 'fs';
import { join } from 'path';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { NotifyService } from '../src/modules/notifications/notify.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';
import { PaymentsService } from '../src/modules/payments/payments.service';
import { TicketsService } from '../src/modules/tickets/tickets.service';
import { EventSeatsService } from '../src/modules/seating/event-seats.service';
import { SeatMapsService } from '../src/modules/seating/seat-maps.service';
import { expandSeats } from '../src/modules/seating/layout';

const run = process.env.DATABASE_URL ? describe : describe.skip;

/** Like Promise.allSettled over `tasks`, with at most `limit` running at once. */
async function settledWithLimit<T>(limit: number, tasks: (() => Promise<T>)[]): Promise<PromiseSettledResult<T>[]> {
  const out: PromiseSettledResult<T>[] = new Array(tasks.length);
  let next = 0;
  const worker = async () => {
    while (next < tasks.length) {
      const i = next++;
      try {
        out[i] = { status: 'fulfilled', value: await tasks[i]() };
      } catch (reason) {
        out[i] = { status: 'rejected', reason };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, tasks.length) }, worker));
  return out;
}
jest.setTimeout(90_000);

run('Seat maps', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const theatre = JSON.parse(readFileSync(join(__dirname, '../src/modules/seating/__fixtures__/theatre.json'), 'utf8'));
  const small = { width: 400, height: 300, sections: [{ key: 'A', name: 'A', kind: 'SEATED', x: 10, y: 10, rows: [{ label: 'A', seats: [{ n: 1 }, { n: 2 }] }] }] };
  let A: Record<string, string>, O: Record<string, string>, orgId: string;

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const newMap = async (name: string) => (await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `${name} ${tag}`, city: 'Yangon' }).expect(201)).body.id as string;

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    const adm = await app.get(AuthService).createInvitation({ email: `adm-s-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Seat Org ${tag}`, slug: `seat-${tag}`, ownerEmail: `own-s-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('admin creates map, saves draft, publishes', async () => {
    const id = await newMap('Theatre');
    const d = await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: theatre }).expect(200);
    expect(d.body).toMatchObject({ version: 1, publishedAt: null });
    const p = await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(200);
    expect(p.body.version).toBe(1);
    expect(p.body.publishedAt).toBeTruthy();
    expect(p.body.seatCount).toBe(expandSeats(theatre).length);
    const detail = await http.get(`/v1/admin/seat-maps/${id}`).set(A).expect(200);
    expect(detail.body.versions).toHaveLength(1);
    expect(detail.body.versions[0].layout).toBeUndefined();
    const v = await http.get(`/v1/admin/seat-maps/${id}/versions/1`).set(A).expect(200);
    expect(v.body.layout.sections.length).toBe(theatre.sections.length);
    expect(await prisma.auditLog.count({ where: { action: 'seatmap.publish', entityId: id } })).toBe(1);
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(409);
  });

  it('invalid layout returns problems', async () => {
    const id = await newMap('Bad');
    const r = await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: { width: 0, sections: [] } }).expect(400);
    expect(r.body.message).toBe('Invalid layout');
    expect(r.body.problems.length).toBeGreaterThan(0);
    await http.post(`/v1/admin/seat-maps/${id}/import`).set(A).send({ layout: 'nope' }).expect(400);
  });

  it('published version is immutable', async () => {
    const id = await newMap('Immutable');
    await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: small }).expect(200);
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(200);
    const d2 = await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: theatre }).expect(200);
    expect(d2.body.version).toBe(2);
    const d3 = await http.post(`/v1/admin/seat-maps/${id}/import`).set(A).send({ layout: small }).expect(200);
    expect(d3.body.version).toBe(2); // replaces the single draft
    const v1 = await http.get(`/v1/admin/seat-maps/${id}/versions/1`).set(A).expect(200);
    expect(v1.body.seatCount).toBe(2);
    expect(v1.body.layout.sections).toHaveLength(1);
    expect(v1.body.layout.sections[0].rows[0].seats).toHaveLength(2);
    expect(await prisma.seatMapVersion.count({ where: { seatMapId: id } })).toBe(2);
  });

  it('saving over a draft that was published meanwhile never touches the published version', async () => {
    const id = await newMap('Race');
    const d1 = await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: small }).expect(200);
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(200);
    // A stale saveDraft still holds the old draft id after publish committed
    const adminId = (await prisma.seatMapVersion.findUniqueOrThrow({ where: { id: d1.body.id } })).createdById;
    const out = await prisma.$transaction((tx) => app.get(SeatMapsService).writeDraft(tx, id, d1.body.id, theatre, 1200, adminId));
    expect(out.version).toBe(2);
    expect(out.publishedAt).toBeNull();
    const v1 = await prisma.seatMapVersion.findUniqueOrThrow({ where: { id: d1.body.id } });
    expect(v1.publishedAt).not.toBeNull();
    expect(v1.seatCount).toBe(2);
    expect((v1.layout as any).sections).toHaveLength(1);
  });

  it('unknown map is 404 for draft; publish without a draft is 409', async () => {
    await http.put('/v1/admin/seat-maps/00000000-0000-4000-8000-000000000000/draft').set(A).send({ layout: small }).expect(404);
    const id = await newMap('NoDraft');
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(409);
  });

  it('new version does not touch events', async () => {
    const id = await newMap('Versions');
    const v1 = (await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: small }).expect(200)).body.id as string;
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(200);
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Versions ${tag}`, format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    await http.put(`/v1/organizations/${orgId}/events/${ev.body.id}/seating/map`).set(O).send({ seatMapVersionId: v1 }).expect(200);
    // A new draft and a published v2 leave the event on v1 with its 2 seats
    await http.put(`/v1/admin/seat-maps/${id}/draft`).set(A).send({ layout: theatre }).expect(200);
    await http.post(`/v1/admin/seat-maps/${id}/publish`).set(A).expect(200);
    const row = await prisma.event.findUniqueOrThrow({ where: { id: ev.body.id } });
    expect(row.seatMapVersionId).toBe(v1);
    expect(await prisma.eventSeat.count({ where: { eventId: ev.body.id } })).toBe(2);
    const detail = await http.get(`/v1/organizations/${orgId}/events/${ev.body.id}`).set(O).expect(200);
    expect(detail.body.seating.seatMapVersionId).toBe(v1);
  });

  it('non-admin gets 403', async () => {
    await http.get('/v1/admin/seat-maps').set(O).expect(403);
    await http.post('/v1/admin/seat-maps').set(O).send({ venueName: 'x', city: 'y' }).expect(403);
    const phone = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    await http.get('/v1/seat-maps').set(bearer(r2.body.accessToken)).expect(403);
  });

  it('organizer list hides maps without a published version', async () => {
    const hidden = await newMap('Hidden');
    await http.put(`/v1/admin/seat-maps/${hidden}/draft`).set(A).send({ layout: small }).expect(200);
    const shown = await newMap('Shown');
    await http.put(`/v1/admin/seat-maps/${shown}/draft`).set(A).send({ layout: small }).expect(200);
    const pub = await http.post(`/v1/admin/seat-maps/${shown}/publish`).set(A).expect(200);
    const off = await newMap('Off');
    await http.put(`/v1/admin/seat-maps/${off}/draft`).set(A).send({ layout: small }).expect(200);
    await http.post(`/v1/admin/seat-maps/${off}/publish`).set(A).expect(200);
    await http.patch(`/v1/admin/seat-maps/${off}`).set(A).send({ isActive: false }).expect(200);

    const r = await http.get('/v1/seat-maps').set(O).expect(200);
    const ids = r.body.map((m: any) => m.id);
    expect(ids).toContain(shown);
    expect(ids).not.toContain(hidden);
    expect(ids).not.toContain(off);
    expect(r.body.find((m: any) => m.id === shown)).toMatchObject({ latestVersionId: pub.body.id, seatCount: 2, city: 'Yangon' });
    const all = await http.get('/v1/admin/seat-maps').set(A).expect(200);
    expect(all.body.find((m: any) => m.id === hidden).latestVersion).toBe(1);
  });
});

run('Seated events', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  const mixed = {
    width: 600,
    height: 400,
    sections: [
      { key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }, { n: 3 }] }, { label: '2', seats: [{ n: 1 }, { n: 2 }, { n: 3 }] }] },
      { key: 'B', name: 'Balcony', kind: 'SEATED', x: 10, y: 200, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }] }] },
      { key: 'F', name: 'Floor', kind: 'STANDING', x: 300, y: 10, capacity: 100, w: 100, h: 100 },
    ],
  };
  let A: Record<string, string>, O: Record<string, string>, orgId: string, versionId: string, otherVersionId: string;

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const base = (eventId: string) => `/v1/organizations/${orgId}/events/${eventId}`;
  async function publishMap(name: string, layout: unknown, venue: object = {}) {
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `${name} ${tag}`, city: 'Mandalay', address: '1 Stage Rd', latitude: 21.9, longitude: 96.1, ...venue }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout }).expect(200);
    return (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id as string;
  }
  async function newEvent(title: string, withVenue = false) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({
        categoryId: cats.body[0].children[0].id,
        title: `${title} ${tag}`,
        format: 'IN_PERSON',
        ...(withVenue ? { venue: { name: 'Old Hall', city: 'Yangon' } } : {}),
        startsAt: start.toISOString(),
        endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString(),
      })
      .expect(201);
    return ev.body as { id: string; slug: string };
  }
  const addType = async (eventId: string, b: object) => (await http.post(`${base(eventId)}/ticket-types`).set(O).send(b).expect(201)).body.id as string;
  const seatsOf = (eventId: string) => prisma.eventSeat.findMany({ where: { eventId }, orderBy: { seatKey: 'asc' } });
  const seat = async (eventId: string, key: string) => prisma.eventSeat.findUniqueOrThrow({ where: { eventId_seatKey: { eventId, seatKey: key } } });
  const ttRow = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    const adm = await app.get(AuthService).createInvitation({ email: `adm-se-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Seated Org ${tag}`, slug: `seated-${tag}`, ownerEmail: `own-se-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    versionId = await publishMap('Mixed', mixed);
    otherVersionId = await publishMap('Other', mixed, { city: 'Bagan' });
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('picking a map creates seats and copies venue', async () => {
    const ev = await newEvent('Pick', true);
    const r = await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    expect(r.body.seating).toMatchObject({ seatMapVersionId: versionId, venueName: `Mixed ${tag}` });
    const seats = await seatsOf(ev.id);
    expect(seats).toHaveLength(expandSeats(mixed as any).length);
    expect(seats.every((s) => s.status === 'UNSOLD' && s.ticketTypeId === null)).toBe(true);
    const a = seats.find((s) => s.seatKey === 'A:1:2')!;
    expect(a.label).toBe('Stalls · Row 1 · Seat 2');
    // venue row is reused (updated), not duplicated
    const row = await prisma.event.findUniqueOrThrow({ where: { id: ev.id }, include: { venue: true } });
    expect(row.venue).toMatchObject({ name: `Mixed ${tag}`, city: 'Mandalay', address: '1 Stage Rd', latitude: 21.9, longitude: 96.1 });
    const noVenue = await newEvent('Pick2');
    await http.put(`${base(noVenue.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    expect((await prisma.event.findUniqueOrThrow({ where: { id: noVenue.id }, include: { venue: true } })).venue?.name).toBe(`Mixed ${tag}`);
    // picking another map recreates the seats and drops the old rules
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: otherVersionId }).expect(200);
    expect((await prisma.event.findUniqueOrThrow({ where: { id: ev.id }, include: { venue: true } })).venue?.city).toBe('Bagan');
    expect(await prisma.eventSeat.count({ where: { eventId: ev.id } })).toBe(8);
    // unpublished or unknown versions are refused
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: '00000000-0000-4000-8000-000000000000' }).expect(404);
    // no token
    await http.put(`${base(ev.id)}/seating/map`).send({ seatMapVersionId: versionId }).expect(401);
  });

  it('another organization cannot touch the event seating', async () => {
    const ev = await newEvent('Foreign');
    const org2 = await http.post('/v1/admin/organizations').set(A).send({ name: `Other Org ${tag}`, slug: `other-${tag}`, ownerEmail: `own2-se-${tag}@e2e.test` }).expect(201);
    const O2 = await acceptInvite(org2.body.inviteUrl);
    await http.get(`${base(ev.id)}/seating`).set(O2).expect(403);
    await http.put(`${base(ev.id)}/seating/map`).set(O2).send({ seatMapVersionId: versionId }).expect(403);
    await http.put(`${base(ev.id)}/seating/assignments`).set(O2).send({ rules: [] }).expect(403);
    await http.delete(`${base(ev.id)}/seating/map`).set(O2).expect(403);
  });

  it('seated types cannot be given a quota, and types with sales cannot become seated', async () => {
    const ev = await newEvent('Guards');
    const seatedT = await addType(ev.id, { name: 'Seated', priceMmk: 10_000, quota: 5 });
    const sold = await addType(ev.id, { name: 'Sold', priceMmk: 10_000, quota: 5 });
    await prisma.ticketType.update({ where: { id: sold }, data: { sold: 2 } });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    const r = await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: sold }] }).expect(409);
    expect(r.body.message).toBe('Sold already has tickets sold without seats; create a new ticket type for seats');
    expect(await ttRow(sold)).toMatchObject({ quota: 5, sold: 2 });
    // standing sections may use a type with sales
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'F', ticketTypeId: sold }, { sectionKey: 'A', ticketTypeId: seatedT }] }).expect(200);
    await http.patch(`${base(ev.id)}/ticket-types/${seatedT}`).set(O).send({ quota: 50 }).expect(400);
    await http.patch(`${base(ev.id)}/ticket-types/${seatedT}`).set(O).send({ name: 'Renamed', color: '#010203' }).expect(200);
    expect(await ttRow(seatedT)).toMatchObject({ name: 'Renamed', color: '#010203', quota: 6 });
    await http.patch(`${base(ev.id)}/ticket-types/${sold}`).set(O).send({ quota: 9 }).expect(200);
  });

  it('seat labels carry Myanmar text', async () => {
    const ev = await newEvent('LabelMy');
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ label: 'Stalls · Row 1 · Seat 2', labelMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 2' });
    expect((await seat(ev.id, 'B:1:1')).labelMy).toBe('Balcony · အတန်း 1 · ခုံ 1');
  });

  it('row rule beats section rule', async () => {
    const ev = await newEvent('Rules');
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    const vip = await addType(ev.id, { name: 'VIP', priceMmk: 30_000, quota: 1, color: '#112233' });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http
      .put(`${base(ev.id)}/seating/assignments`)
      .set(O)
      .send({ rules: [{ sectionKey: 'A', ticketTypeId: std }, { sectionKey: 'A', rowLabel: '1', ticketTypeId: vip }, { sectionKey: 'B', ticketTypeId: std }] })
      .expect(200);
    expect((await seat(ev.id, 'A:1:1')).ticketTypeId).toBe(vip);
    expect((await seat(ev.id, 'A:2:3')).ticketTypeId).toBe(std);
    expect((await seat(ev.id, 'B:1:2')).ticketTypeId).toBe(std);
    expect((await seat(ev.id, 'A:1:1')).status).toBe('AVAILABLE');
    expect((await ttRow(vip)).color).toBe('#112233');
    // validation
    const bad = (rules: object[]) => http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules });
    await bad([{ sectionKey: 'ZZ', ticketTypeId: std }]).expect(400);
    await bad([{ sectionKey: 'A', rowLabel: '9', ticketTypeId: std }]).expect(400);
    await bad([{ sectionKey: 'F', rowLabel: '1', ticketTypeId: std }]).expect(400);
    await bad([{ sectionKey: 'A', ticketTypeId: '00000000-0000-4000-8000-000000000000' }]).expect(400);
    await bad([{ sectionKey: 'A', ticketTypeId: std }, { sectionKey: 'A', ticketTypeId: vip }]).expect(400);
    const g = await http.get(`${base(ev.id)}/seating`).set(O).expect(200);
    expect(g.body.rules).toHaveLength(3);
    expect(g.body.versionId).toBe(versionId);
    expect(g.body.layout.sections).toHaveLength(3);
    expect(g.body.counts[vip]).toEqual({ available: 3, held: 0, guest: 0, sold: 0, comp: 0 });
    expect(g.body.counts[std]).toEqual({ available: 5, held: 0, guest: 0, sold: 0, comp: 0 });
    expect(g.body.seats).toHaveLength(8);
    expect(g.body.seats[0]).toMatchObject({ seatKey: expect.any(String), status: expect.any(String) });
  });

  it('unassigned seats are UNSOLD and not on sale', async () => {
    const ev = await newEvent('Unassigned');
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: std }] }).expect(200);
    expect((await seat(ev.id, 'B:1:1')).status).toBe('UNSOLD');
    expect((await seat(ev.id, 'B:1:1')).ticketTypeId).toBeNull();
    expect((await seat(ev.id, 'A:1:1')).status).toBe('AVAILABLE');
    // removing the rule takes the seats off sale again
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [] }).expect(200);
    expect((await seatsOf(ev.id)).every((s) => s.status === 'UNSOLD' && s.ticketTypeId === null)).toBe(true);
    expect((await ttRow(std)).quota).toBe(0); // was seated, now has no seats: counters follow
  });

  it('seated ticket type quota equals assigned seats', async () => {
    const ev = await newEvent('Quota');
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 999 });
    const vip = await addType(ev.id, { name: 'VIP', priceMmk: 30_000, quota: 999 });
    const floor = await addType(ev.id, { name: 'Floor', priceMmk: 5_000, quota: 77 });
    const plain = await addType(ev.id, { name: 'Plain', priceMmk: 1_000, quota: 12 });
    await prisma.ticketType.update({ where: { id: floor }, data: { sold: 5, held: 2 } });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http
      .put(`${base(ev.id)}/seating/assignments`)
      .set(O)
      .send({ rules: [{ sectionKey: 'A', ticketTypeId: std }, { sectionKey: 'B', ticketTypeId: vip }, { sectionKey: 'F', ticketTypeId: floor }] })
      .expect(200);
    expect(await ttRow(std)).toMatchObject({ quota: 6, held: 0, sold: 0 });
    expect(await ttRow(vip)).toMatchObject({ quota: 2 });
    // standing and unseated types keep the organizer's quota and counters
    expect(await ttRow(floor)).toMatchObject({ quota: 77, sold: 5, held: 2 });
    expect(await ttRow(plain)).toMatchObject({ quota: 12 });
    // states move the counters: hold, sold, guest hold, comp
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:1' } }, data: { status: 'CHECKOUT_HOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:2' } }, data: { status: 'SOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:3' } }, data: { status: 'GUEST_HOLD' } });
    await app.get(EventSeatsService).recountTicketTypes(prisma as any, ev.id);
    expect(await ttRow(std)).toMatchObject({ quota: 5, held: 1, sold: 1 });
    const g = await http.get(`${base(ev.id)}/seating`).set(O).expect(200);
    expect(g.body.counts[std]).toEqual({ available: 3, held: 1, guest: 1, sold: 1, comp: 0 });
  });

  it('reassign keeps sold seats', async () => {
    const ev = await newEvent('Reassign');
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    const vip = await addType(ev.id, { name: 'VIP', priceMmk: 30_000, quota: 1 });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: std }] }).expect(200);
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:1' } }, data: { status: 'SOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:2' } }, data: { status: 'CHECKOUT_HOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:3' } }, data: { status: 'GUEST_HOLD', holdLabel: 'Press' } });
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: vip }] }).expect(200);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'SOLD', ticketTypeId: std });
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ status: 'CHECKOUT_HOLD', ticketTypeId: std });
    expect(await seat(ev.id, 'A:1:3')).toMatchObject({ status: 'GUEST_HOLD', ticketTypeId: vip, holdLabel: 'Press' });
    expect(await seat(ev.id, 'A:2:1')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: vip });
    expect(await ttRow(std)).toMatchObject({ quota: 2, held: 1, sold: 1 });
    expect(await ttRow(vip)).toMatchObject({ quota: 3, held: 0, sold: 0 });
  });

  it('cannot change map once a seat is sold', async () => {
    const ev = await newEvent('Locked');
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: std }] }).expect(200);
    for (const status of ['SOLD', 'CHECKOUT_HOLD', 'GUEST_HOLD'] as const) {
      await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:1' } }, data: { status } });
      await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: otherVersionId }).expect(409);
      await http.delete(`${base(ev.id)}/seating/map`).set(O).expect(409);
      expect(await prisma.eventSeat.count({ where: { eventId: ev.id } })).toBe(8);
      expect((await prisma.event.findUniqueOrThrow({ where: { id: ev.id } })).seatMapVersionId).toBe(versionId);
    }
    // once nothing is sold or held the event can go back to unseated
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:1' } }, data: { status: 'AVAILABLE' } });
    const del = await http.delete(`${base(ev.id)}/seating/map`).set(O).expect(200);
    expect(del.body.seating).toBeNull();
    expect(await prisma.eventSeat.count({ where: { eventId: ev.id } })).toBe(0);
    expect(await prisma.eventSection.count({ where: { eventId: ev.id } })).toBe(0);
  });

  it('public seats endpoint encodes types and status', async () => {
    const ev = await newEvent('Public');
    const vip = await addType(ev.id, { name: 'VIP', nameMy: 'ဗစ်ပ်', priceMmk: 30_000, quota: 1, color: '#abcdef' });
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    await addType(ev.id, { name: 'Unused', priceMmk: 1, quota: 1 });
    await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: vip }, { sectionKey: 'A', rowLabel: '2', ticketTypeId: std }] }).expect(200);
    await http.get(`/v1/events/${ev.id}/seats`).expect(404); // draft is not public
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:1' } }, data: { status: 'SOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:2' } }, data: { status: 'CHECKOUT_HOLD' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:1:3' } }, data: { status: 'GUEST_HOLD' } });
    const r = await http.get(`/v1/events/${ev.slug}/seats`).expect(200);
    const n = expandSeats(mixed as any).length;
    expect(r.body.versionId).toBe(versionId);
    expect(r.body.layout.sections).toHaveLength(3);
    expect(r.body.seatTypes).toHaveLength(n);
    expect(r.body.status).toHaveLength(n);
    // price ascending: Std = 0, VIP = 1; Std has no colour so takes the palette entry for its price rank
    expect(r.body.types.map((t: any) => t.id)).toEqual([std, vip]);
    expect(r.body.types[0]).toMatchObject({ name: 'Std', priceMmk: 10000, color: '#f2b632' });
    expect(r.body.types[1]).toMatchObject({ name: 'VIP', nameMy: 'ဗစ်ပ်', priceMmk: 30000, color: '#abcdef' });
    // layout order: A row1 (3 seats), A row2 (3), B (2)
    expect(r.body.seatTypes).toBe('111000--');
    expect(r.body.status).toBe('TTGAAAUU');
    // the portal colours seated types like the buyer apps; a type without seats continues the palette
    const ov = await http.get(`${base(ev.id)}/seating`).set(O).expect(200);
    expect(ov.body.colors[std]).toBe(r.body.types[0].color);
    expect(ov.body.colors[vip]).toBe(r.body.types[1].color);
    expect(Object.values(ov.body.colors)).toEqual(expect.arrayContaining(['#3b6fd8']));
  });

  describe('Best available', () => {
    it('suggests seats without holding them; 409 when not enough; 400 on bad input', async () => {
      const ev = await newEvent('Best');
      const vip = await addType(ev.id, { name: 'VIP', priceMmk: 30_000, quota: 1 });
      const plain = await addType(ev.id, { name: 'Plain', priceMmk: 1_000, quota: 5 });
      await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
      await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: vip }] }).expect(200);
      const url = `/v1/events/${ev.id}/seats/best`;
      await http.post(url).send({ ticketTypeId: vip, quantity: 2 }).expect(404); // draft is not public
      await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
      const ok = await http.post(url).send({ ticketTypeId: vip, quantity: 2 }).expect(200);
      expect(ok.body.seats).toHaveLength(2);
      expect(ok.body.seats.every((k: string) => k.startsWith('A:1:'))).toBe(true); // nearest the stage (no stage: top edge)
      expect((await seat(ev.id, ok.body.seats[0])).status).toBe('AVAILABLE'); // nothing held
      await http.post(url).send({ ticketTypeId: vip, quantity: 7 }).expect(409).expect((r) => expect(r.body).toMatchObject({ message: 'Not enough seats together', seats: [] }));
      await http.post(url).send({ ticketTypeId: plain, quantity: 1 }).expect(404); // not a seated type
      await http.post(url).send({ ticketTypeId: vip, quantity: 0 }).expect(400);
      await http.post(url).send({ ticketTypeId: vip, quantity: 21 }).expect(400);
      await http.post(url).send({ ticketTypeId: vip }).expect(400);
      await http.post(url).send({ ticketTypeId: 'nope', quantity: 1 }).expect(400);
    });
  });

  it('unseated event unchanged', async () => {
    const ev = await newEvent('Plain', true);
    await addType(ev.id, { name: 'GA', priceMmk: 1000, quota: 5 });
    const d = await http.get(base(ev.id)).set(O).expect(200);
    expect(d.body.seating).toBeNull();
    expect(d.body.ticketTypes[0]).toMatchObject({ seated: false, color: null, quota: 5 });
    const list = await http.get(`/v1/organizations/${orgId}/events`).set(O).expect(200);
    expect(list.body.find((e: any) => e.id === ev.id).seating).toBeNull();
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    const pub = await http.get(`/v1/events/${ev.slug}`).expect(200);
    expect(pub.body.seating).toBeNull();
    await http.get(`/v1/events/${ev.slug}/seats`).expect(404);
    await http.get(`${base(ev.id)}/seating`).set(O).expect(200);
  });

  it('map change on a published event of an unverified org goes back to review; assignments do not', async () => {
    const ev = await newEvent('Review', true);
    const std = await addType(ev.id, { name: 'Std', priceMmk: 10_000, quota: 1 });
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    const r = await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    expect(r.body).toMatchObject({ status: 'SUBMITTED', reReviewRequired: true });
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED' } });
    const a = await http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: std }] }).expect(200);
    expect(a.body.reReviewRequired).toBe(false);
    expect((await prisma.event.findUniqueOrThrow({ where: { id: ev.id } })).status).toBe('PUBLISHED');
    const d = await http.delete(`${base(ev.id)}/seating/map`).set(O).expect(200);
    expect(d.body).toMatchObject({ status: 'SUBMITTED', reReviewRequired: true });
    // a verified organizer's change goes straight through
    await http.patch(`/v1/admin/organizations/${orgId}/kyc`).set(A).send({ status: 'APPROVED' }).expect(200);
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED' } });
    const v = await http.put(`${base(ev.id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    expect(v.body).toMatchObject({ status: 'PUBLISHED', reReviewRequired: false });
  });
});

run('Seated checkout', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  let svc: PaymentsService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  // Hall: section A has 6 rows of 10 seats (A:<row>:<n>), section B one row of 4, plus a standing floor
  const hall = {
    width: 800,
    height: 600,
    sections: [
      { key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [1, 2, 3, 4, 5, 6].map((r) => ({ label: String(r), seats: Array.from({ length: 10 }, (_, i) => ({ n: i + 1 })) })) },
      { key: 'B', name: 'Balcony', kind: 'SEATED', x: 10, y: 400, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }, { n: 3 }, { n: 4 }] }] },
      { key: 'F', name: 'Floor', kind: 'STANDING', x: 500, y: 10, capacity: 100, w: 100, h: 100 },
    ],
  };
  let A: Record<string, string>, O: Record<string, string>, orgId: string, versionId: string;

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
  const base = (eventId: string) => `/v1/organizations/${orgId}/events/${eventId}`;
  const tokenOf = (url: string) => new URL(url).searchParams.get('t')!;
  const pathOf = (url: string) => new URL(url).pathname;
  const seat = (eventId: string, key: string) => prisma.eventSeat.findUniqueOrThrow({ where: { eventId_seatKey: { eventId, seatKey: key } } });
  const ttRow = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });

  /** Published event on the hall map: A rows 1-5 = Std (10,000), A row 6 = Free, B = VIP (30,000), F = Floor (standing, 5,000). */
  async function seatedEvent(title: string, maxPerOrder = 4) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `${title} ${tag}`, format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    const id = ev.body.id as string;
    const add = async (b: object) => (await http.post(`${base(id)}/ticket-types`).set(O).send(b).expect(201)).body.id as string;
    const std = await add({ name: 'Std', priceMmk: 10_000, quota: 1, maxPerOrder });
    const free = await add({ name: 'Free', priceMmk: 0, quota: 1, maxPerOrder });
    const vip = await add({ name: 'VIP', priceMmk: 30_000, quota: 1, maxPerOrder });
    const floor = await add({ name: 'Floor', priceMmk: 5_000, quota: 100, maxPerOrder });
    await http.put(`${base(id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http
      .put(`${base(id)}/seating/assignments`)
      .set(O)
      .send({ rules: [{ sectionKey: 'A', ticketTypeId: std }, { sectionKey: 'A', rowLabel: '6', ticketTypeId: free }, { sectionKey: 'B', ticketTypeId: vip }, { sectionKey: 'F', ticketTypeId: floor }] })
      .expect(200);
    await prisma.event.update({ where: { id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    return { id, std, free, vip, floor };
  }
  const order = (B: Record<string, string>, eventId: string, body: object) => http.post(`/v1/events/${eventId}/orders`).set(B).send(body);
  async function payWithMock(B: Record<string, string>, orderId: string) {
    const p = await http.post(`/v1/orders/${orderId}/pay`).set(B).send({ provider: 'MOCK' }).expect(200);
    return p.body.payment.action.url as string;
  }
  const mockPay = (url: string) => http.post(`${pathOf(url)}/pay`).type('form').send({ t: tokenOf(url) }).expect(201);
  /** Seat-derived counters always match event_seats. */
  async function expectCountersMatch(typeId: string) {
    const [t, held, sold] = await Promise.all([
      ttRow(typeId),
      prisma.eventSeat.count({ where: { ticketTypeId: typeId, status: 'CHECKOUT_HOLD' } }),
      prisma.eventSeat.count({ where: { ticketTypeId: typeId, status: 'SOLD' } }),
    ]);
    expect({ held: t.held, sold: t.sold }).toEqual({ held, sold });
  }

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    svc = app.get(PaymentsService);
    const adm = await app.get(AuthService).createInvitation({ email: `adm-sc-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Checkout Org ${tag}`, slug: `seatco-${tag}`, ownerEmail: `own-sc-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Hall ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id;
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('free seated order issues tickets with seat labels', async () => {
    const ev = await seatedEvent('Free');
    const B = await consumer();
    const r = await order(B, ev.id, { seats: ['A:6:1', 'A:6:2'] }).expect(201);
    expect(r.body).toMatchObject({ status: 'CONFIRMED', totalMmk: 0 });
    expect(r.body.ticketIds).toHaveLength(2);
    expect(r.body.items[0]).toMatchObject({ ticketTypeId: ev.free, quantity: 2 });
    expect(r.body.items[0].seats.map((s: any) => s.seatKey)).toEqual(['A:6:1', 'A:6:2']);
    const tickets = await prisma.ticket.findMany({ where: { orderId: r.body.id }, orderBy: { seatKey: 'asc' } });
    expect(tickets.map((t) => [t.seatKey, t.seatLabel, t.seatLabelMy])).toEqual([
      ['A:6:1', 'Stalls · Row 6 · Seat 1', 'ရှေ့ခန်း · အတန်း 6 · ခုံ 1'],
      ['A:6:2', 'Stalls · Row 6 · Seat 2', 'ရှေ့ခန်း · အတန်း 6 · ခုံ 2'],
    ]);
    for (const t of tickets) expect(await seat(ev.id, t.seatKey!)).toMatchObject({ status: 'SOLD', orderId: r.body.id, ticketId: t.id });
    expect(await ttRow(ev.free)).toMatchObject({ quota: 10, sold: 2, held: 0 });
    // the older free-registration route cannot sell a seated type without a seat
    await http.post(`/v1/events/${ev.id}/registrations`).set(B).send({ ticketTypeId: ev.free, quantity: 1 }).expect(400);
    expect(await ttRow(ev.free)).toMatchObject({ sold: 2 });
  });

  it('paid seated order holds then settles', async () => {
    const ev = await seatedEvent('Paid');
    const B = await consumer();
    const r = await order(B, ev.id, { seats: ['A:1:1', 'A:1:2', 'B:1:1'] }).expect(201);
    expect(r.body).toMatchObject({ status: 'PENDING_PAYMENT', totalMmk: 50_000 });
    for (const k of ['A:1:1', 'A:1:2', 'B:1:1']) expect(await seat(ev.id, k)).toMatchObject({ status: 'CHECKOUT_HOLD', orderId: r.body.id, heldUntil: new Date(r.body.holdExpiresAt) });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 50, held: 2, sold: 0 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 4, held: 1, sold: 0 });
    // the public map shows them taken
    const pub = await http.get(`/v1/events/${ev.id}/seats`).expect(200);
    expect(pub.body.status[0]).toBe('T');

    await mockPay(await payWithMock(B, r.body.id));
    const paid = await http.get(`/v1/orders/${r.body.id}`).set(B).expect(200);
    expect(paid.body.status).toBe('PAID');
    expect(paid.body.ticketIds).toHaveLength(3);
    const tickets = await prisma.ticket.findMany({ where: { orderId: r.body.id } });
    expect(tickets.map((t) => t.seatLabel).sort()).toEqual(['Balcony · Row 1 · Seat 1', 'Stalls · Row 1 · Seat 1', 'Stalls · Row 1 · Seat 2']);
    expect(tickets.find((t) => t.seatKey === 'B:1:1')).toMatchObject({ ticketTypeId: ev.vip, seatLabelMy: 'Balcony · အတန်း 1 · ခုံ 1' });
    for (const t of tickets) expect(await seat(ev.id, t.seatKey!)).toMatchObject({ status: 'SOLD', ticketId: t.id, orderId: r.body.id });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 50, held: 0, sold: 2 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 4, held: 0, sold: 1 });
  });

  it('taken seat returns 409 naming it and holds nothing', async () => {
    const ev = await seatedEvent('Taken');
    const [B1, B2] = [await consumer(), await consumer()];
    await order(B1, ev.id, { seats: ['A:2:5'] }).expect(201);
    const r = await order(B2, ev.id, { seats: ['A:2:4', 'A:2:5', 'A:2:6'] }).expect(409);
    expect(r.body).toMatchObject({ message: 'Some seats were just taken', takenSeats: ['A:2:5'] });
    expect(await seat(ev.id, 'A:2:4')).toMatchObject({ status: 'AVAILABLE', orderId: null });
    expect(await seat(ev.id, 'A:2:6')).toMatchObject({ status: 'AVAILABLE', orderId: null });
    expect(await ttRow(ev.std)).toMatchObject({ held: 1, sold: 0 });
    // validation: unknown, unassigned, duplicate, seated type via items, empty
    const fresh = await seatedEvent('Taken2');
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: fresh.id, seatKey: 'B:1:4' } }, data: { ticketTypeId: null, status: 'UNSOLD' } });
    await order(B2, fresh.id, { seats: ['Z:9:9'] }).expect(400);
    await order(B2, fresh.id, { seats: ['A:2:5'] }).expect(201); // same key on another event is a different seat
    await order(B2, ev.id, { seats: [] }).expect(400);
    await order(B2, fresh.id, { seats: ['B:1:4'] }).expect(400);
    await order(B2, fresh.id, { seats: ['A:3:1', 'A:3:1'] }).expect(400);
    await order(B2, fresh.id, { items: [{ ticketTypeId: fresh.std, quantity: 1 }] }).expect(400);
    await order(B2, fresh.id, {}).expect(400);
    // an unseated event has no seats to choose
    await prisma.event.update({ where: { id: ev.id }, data: { seatMapVersionId: null } });
    await order(B2, ev.id, { seats: ['A:1:1'] }).expect(400);
  });

  it('50 parallel overlapping claims', async () => {
    const ev = await seatedEvent('Rush');
    const users = await Promise.all(Array.from({ length: 50 }, (_, i) => prisma.user.create({ data: { phone: `0960${tag.slice(0, 4)}${String(i).padStart(3, '0')}`.slice(0, 14) } })));
    const unique = (i: number) => `A:${2 + Math.floor(i / 10)}:${(i % 10) + 1}`; // rows 2-6, 50 distinct seats
    const results = await Promise.allSettled(users.map((u, i) => svc.createOrder(u.id, ev.id, [], undefined, 'APP', undefined, ['A:1:1', 'A:1:2', unique(i)])));
    const won = results.filter((r) => r.status === 'fulfilled');
    const lost = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
    expect(won).toHaveLength(1);
    expect(lost).toHaveLength(49);
    for (const l of lost) {
      expect(l.reason.getStatus?.()).toBe(409);
      expect(l.reason.getResponse()).toMatchObject({ message: 'Some seats were just taken' });
    }
    const winner = (won[0] as PromiseFulfilledResult<{ id: string }>).value.id;
    const held = await prisma.eventSeat.findMany({ where: { eventId: ev.id, status: { not: 'AVAILABLE' }, ticketTypeId: { not: null } } });
    expect(held.every((s) => s.orderId === winner && s.status === 'CHECKOUT_HOLD')).toBe(true); // the shared seats make every order a paid one
    expect(held).toHaveLength(3);
    expect(await prisma.order.count({ where: { eventId: ev.id } })).toBe(1);
    const holdCount = await prisma.eventSeat.count({ where: { ticketTypeId: ev.std, status: 'CHECKOUT_HOLD' } });
    expect((await ttRow(ev.std)).held).toBe(holdCount);
    await expectCountersMatch(ev.std);
    await expectCountersMatch(ev.free);
  });

  it('200 parallel claims on distinct seats all succeed and counters add up', async () => {
    const arena = { width: 800, height: 800, sections: [{ key: 'R', name: 'Ring', kind: 'SEATED', x: 10, y: 10, rows: Array.from({ length: 20 }, (_, r) => ({ label: String(r + 1), seats: Array.from({ length: 10 }, (_, i) => ({ n: i + 1 })) })) }] };
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Arena ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: arena }).expect(200);
    const arenaVersion = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id;
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = (await http.post(`/v1/organizations/${orgId}/events`).set(O).send({ categoryId: cats.body[0].children[0].id, title: `Arena ${tag}`, format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() }).expect(201)).body.id as string;
    const ring = (await http.post(`${base(ev)}/ticket-types`).set(O).send({ name: 'Ring', priceMmk: 10_000, quota: 1, maxPerOrder: 1 }).expect(201)).body.id as string;
    await http.put(`${base(ev)}/seating/map`).set(O).send({ seatMapVersionId: arenaVersion }).expect(200);
    await http.put(`${base(ev)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'R', ticketTypeId: ring }] }).expect(200);
    await prisma.event.update({ where: { id: ev }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    const users = await prisma.$transaction(Array.from({ length: 200 }, (_, i) => prisma.user.create({ data: { phone: `0961${tag.slice(0, 4)}${String(i).padStart(3, '0')}` } })));
    // Bounded concurrency: 16 claims in flight at once (more than the Prisma pool, so they still contend for
    // connections, the event row and the counter row), so a busy full `jest` run can't starve them past maxWait.
    const results = await settledWithLimit(16, users.map((u, i) => () => svc.createOrder(u.id, ev, [], undefined, 'APP', undefined, [`R:${Math.floor(i / 10) + 1}:${(i % 10) + 1}`])));
    const failed = results.filter((r): r is PromiseRejectedResult => r.status === 'rejected');
    expect(failed.map((f) => String(f.reason?.message ?? f.reason))).toEqual([]);
    expect(await prisma.eventSeat.count({ where: { eventId: ev, status: 'CHECKOUT_HOLD' } })).toBe(200);
    expect(await ttRow(ring)).toMatchObject({ quota: 200, held: 200, sold: 0 }); // no lost recounts
    // Parallel cancels give every seat back (and leave no pending orders for other suites' sweeps)
    const ids = results.map((r) => (r as PromiseFulfilledResult<{ id: string }>).value.id);
    const cancels = await settledWithLimit(16, ids.map((id, i) => () => svc.cancel(users[i].id, id)));
    expect(cancels.filter((r) => r.status === 'rejected')).toEqual([]);
    expect(await prisma.eventSeat.count({ where: { eventId: ev, status: 'AVAILABLE' } })).toBe(200);
    expect(await ttRow(ring)).toMatchObject({ quota: 200, held: 0, sold: 0 });
  });

  it('a type that becomes seated mid-checkout is never sold as a quantity line', async () => {
    const ev = await seatedEvent('Race');
    const extra = (await http.post(`${base(ev.id)}/ticket-types`).set(O).send({ name: 'Extra', priceMmk: 2_000, quota: 10 }).expect(201)).body.id as string;
    const freebie = (await http.post(`${base(ev.id)}/ticket-types`).set(O).send({ name: 'Freebie', priceMmk: 0, quota: 10 }).expect(201)).body.id as string;
    const rules = (b: string) => [
      { sectionKey: 'A', ticketTypeId: ev.std },
      { sectionKey: 'A', rowLabel: '6', ticketTypeId: ev.free },
      { sectionKey: 'B', ticketTypeId: b },
      { sectionKey: 'F', ticketTypeId: ev.floor },
    ];
    const seating = app.get(EventSeatsService);
    const tickets = app.get(TicketsService);
    // The organizer's assignment commits after the buyer's pre-checks passed and before the buyer's transaction
    const original = prisma.$transaction.bind(prisma);
    const between = (fn: () => Promise<unknown>) =>
      jest.spyOn(prisma, '$transaction').mockImplementationOnce((async (...args: any[]) => {
        await fn();
        return (original as any)(...args);
      }) as any);
    const buyer = await prisma.user.create({ data: { phone: `0962${tag.slice(0, 4)}001` } });

    between(() => seating.setAssignments(orgId, ev.id, rules(extra)));
    await expect(svc.createOrder(buyer.id, ev.id, [{ ticketTypeId: extra, quantity: 1 }])).rejects.toMatchObject({ status: 400 });
    expect(await ttRow(extra)).toMatchObject({ quota: 4, held: 0, sold: 0 });
    expect(await prisma.order.count({ where: { eventId: ev.id } })).toBe(0);

    between(() => seating.setAssignments(orgId, ev.id, rules(freebie)));
    await expect(tickets.registerFree(buyer.id, ev.id, freebie, 1)).rejects.toMatchObject({ status: 400 });
    expect(await ttRow(freebie)).toMatchObject({ quota: 4, held: 0, sold: 0 });
    jest.restoreAllMocks();

    // Late payment for a quantity line whose type became seated after the hold expired: flagged, not sold seatless
    await seating.setAssignments(orgId, ev.id, rules(ev.vip));
    await http.patch(`${base(ev.id)}/ticket-types/${extra}`).set(O).send({ quota: 10 }).expect(200); // unseated again
    const B = await consumer();
    const o = await order(B, ev.id, { items: [{ ticketTypeId: extra, quantity: 1 }] }).expect(201);
    const url = await payWithMock(B, o.body.id);
    await prisma.order.update({ where: { id: o.body.id }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
    await svc.sweep();
    await seating.setAssignments(orgId, ev.id, rules(extra));
    await mockPay(url);
    const late = await prisma.order.findUniqueOrThrow({ where: { id: o.body.id }, include: { tickets: true } });
    expect(late).toMatchObject({ status: 'PAID', needsReview: true });
    expect(late.tickets).toHaveLength(0);
    expect(await ttRow(extra)).toMatchObject({ quota: 4, held: 0, sold: 0 });
  });

  it('expired hold frees seats', async () => {
    const ev = await seatedEvent('Expire');
    const B = await consumer();
    const r = await order(B, ev.id, { seats: ['A:1:3', 'A:1:4'] }).expect(201);
    expect(await ttRow(ev.std)).toMatchObject({ held: 2 });
    await prisma.order.update({ where: { id: r.body.id }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
    await svc.sweep();
    expect((await http.get(`/v1/orders/${r.body.id}`).set(B).expect(200)).body.status).toBe('EXPIRED');
    for (const k of ['A:1:3', 'A:1:4']) expect(await seat(ev.id, k)).toMatchObject({ status: 'AVAILABLE', orderId: null, heldUntil: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 50, held: 0, sold: 0 });
    // cancel frees them too
    const c = await order(B, ev.id, { seats: ['A:1:3'] }).expect(201);
    await http.post(`/v1/orders/${c.body.id}/cancel`).set(B).expect(200);
    expect(await seat(ev.id, 'A:1:3')).toMatchObject({ status: 'AVAILABLE', orderId: null });
    expect(await ttRow(ev.std)).toMatchObject({ held: 0 });
  });

  it('late payment after seat resold', async () => {
    const ev = await seatedEvent('Late');
    const [B1, B2, B3] = [await consumer(), await consumer(), await consumer()];
    const expire = async (id: string) => {
      await prisma.order.update({ where: { id }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
      await svc.sweep();
    };
    // Seats still free: the late payment re-claims them
    const ok = await order(B3, ev.id, { seats: ['A:5:1', 'A:5:2'] }).expect(201);
    const okUrl = await payWithMock(B3, ok.body.id);
    await expire(ok.body.id);
    await mockPay(okUrl);
    const okRow = await prisma.order.findUniqueOrThrow({ where: { id: ok.body.id }, include: { tickets: true } });
    expect(okRow).toMatchObject({ status: 'PAID', needsReview: false });
    expect(okRow.tickets.map((t) => t.seatKey).sort()).toEqual(['A:5:1', 'A:5:2']);
    expect(await seat(ev.id, 'A:5:1')).toMatchObject({ status: 'SOLD', orderId: ok.body.id, ticketId: expect.any(String) });

    // One of the seats was taken meanwhile: none are taken, the order is flagged
    const o = await order(B1, ev.id, { seats: ['A:4:1', 'A:4:2'] }).expect(201);
    const url = await payWithMock(B1, o.body.id);
    await expire(o.body.id);
    const other = await order(B2, ev.id, { seats: ['A:4:2'] }).expect(201);
    await mockPay(url);
    const late = await prisma.order.findUniqueOrThrow({ where: { id: o.body.id }, include: { tickets: true } });
    expect(late).toMatchObject({ status: 'PAID', needsReview: true, reviewNote: 'Paid after the hold expired and the tickets sold out: refund the buyer' });
    expect(late.tickets).toHaveLength(0);
    expect(await seat(ev.id, 'A:4:1')).toMatchObject({ status: 'AVAILABLE', orderId: null });
    expect(await seat(ev.id, 'A:4:2')).toMatchObject({ status: 'CHECKOUT_HOLD', orderId: other.body.id });
    await mockPay(await payWithMock(B2, other.body.id));
    const sold = await prisma.ticket.findMany({ where: { ticketType: { eventId: ev.id }, seatKey: 'A:4:2', status: 'VALID' } });
    expect(sold).toHaveLength(1);
    expect(sold[0].orderId).toBe(other.body.id);
    expect(await ttRow(ev.std)).toMatchObject({ held: 0, sold: 3 });
    await expectCountersMatch(ev.std);
    // the flagged order is refunded by an admin without touching B2's seat
    await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'Seat taken before payment arrived' }).expect(200);
    expect(await seat(ev.id, 'A:4:2')).toMatchObject({ status: 'SOLD', orderId: other.body.id });
  });

  it('admin refund frees all seats', async () => {
    const ev = await seatedEvent('Refund');
    const B = await consumer();
    const r = await order(B, ev.id, { seats: ['A:3:1', 'A:3:2', 'B:1:2'], items: [{ ticketTypeId: ev.floor, quantity: 1 }] }).expect(201);
    await mockPay(await payWithMock(B, r.body.id));
    expect(await ttRow(ev.floor)).toMatchObject({ sold: 1, held: 0 });
    const res = await http.post(`/v1/admin/finance/orders/${r.body.id}/refund`).set(A).send({ reason: 'Buyer request' }).expect(200);
    expect(res.body.status).toBe('REFUNDED');
    expect(await prisma.ticket.count({ where: { orderId: r.body.id, status: 'REFUNDED' } })).toBe(4);
    for (const k of ['A:3:1', 'A:3:2', 'B:1:2']) expect(await seat(ev.id, k)).toMatchObject({ status: 'AVAILABLE', orderId: null, ticketId: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 50, held: 0, sold: 0 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 4, held: 0, sold: 0 });
    expect(await ttRow(ev.floor)).toMatchObject({ quota: 100, sold: 0 });
    // the seats can be bought again
    await order(await consumer(), ev.id, { seats: ['A:3:1'] }).expect(201);
  });

  it('a seat back on sale follows the current rules (expiry, cancel, refund)', async () => {
    const ev = await seatedEvent('Rules');
    const B = await consumer();
    const assign = (rules: object[]) => http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules }).expect(200);
    // Std seats in rows 1 and 2 are held while the organizer moves row 1 to VIP and drops the rest of A
    const r = await order(B, ev.id, { seats: ['A:1:1', 'A:1:2', 'A:2:1'] }).expect(201);
    await assign([{ sectionKey: 'A', rowLabel: '1', ticketTypeId: ev.vip }, { sectionKey: 'A', rowLabel: '6', ticketTypeId: ev.free }, { sectionKey: 'B', ticketTypeId: ev.vip }, { sectionKey: 'F', ticketTypeId: ev.floor }]);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'CHECKOUT_HOLD', ticketTypeId: ev.std }); // a hold keeps its type
    expect(await ttRow(ev.std)).toMatchObject({ quota: 3, held: 3, sold: 0 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 12, held: 0 });
    await prisma.order.update({ where: { id: r.body.id }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
    await svc.sweep();
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: ev.vip, orderId: null });
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: ev.vip });
    expect(await seat(ev.id, 'A:2:1')).toMatchObject({ status: 'UNSOLD', ticketTypeId: null, orderId: null, heldUntil: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 0, held: 0, sold: 0 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 14, held: 0, sold: 0 });
    const pub = await http.get(`/v1/events/${ev.id}/seats`).expect(200);
    expect(pub.body.types.map((t: any) => t.id)).not.toContain(ev.std);

    // Cancel: a VIP hold in row 1 comes back as Std after row 1 moves to Std
    const c = await order(B, ev.id, { seats: ['A:1:3'] }).expect(201);
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 14, held: 1 });
    await assign([{ sectionKey: 'A', rowLabel: '1', ticketTypeId: ev.std }, { sectionKey: 'B', ticketTypeId: ev.vip }]);
    await http.post(`/v1/orders/${c.body.id}/cancel`).set(B).expect(200);
    expect(await seat(ev.id, 'A:1:3')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: ev.std, orderId: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 10, held: 0, sold: 0 });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 4, held: 0, sold: 0 });

    // Refund: a sold balcony seat whose section lost its rule becomes UNSOLD
    const p = await order(B, ev.id, { seats: ['B:1:1'] }).expect(201);
    await mockPay(await payWithMock(B, p.body.id));
    await assign([{ sectionKey: 'A', rowLabel: '1', ticketTypeId: ev.std }]);
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 1, sold: 1 });
    await http.post(`/v1/admin/finance/orders/${p.body.id}/refund`).set(A).send({ reason: 'Rules changed' }).expect(200);
    expect(await seat(ev.id, 'B:1:1')).toMatchObject({ status: 'UNSOLD', ticketTypeId: null, orderId: null, ticketId: null });
    expect(await ttRow(ev.vip)).toMatchObject({ quota: 0, held: 0, sold: 0 });
    for (const id of [ev.std, ev.vip]) await expectCountersMatch(id);
  });

  it('per-person limit counts seats', async () => {
    const ev = await seatedEvent('Limit', 2);
    const B = await consumer();
    await order(B, ev.id, { seats: ['A:1:1', 'A:1:2', 'A:1:3'] }).expect(400); // more than maxPerOrder in one order
    await order(B, ev.id, { seats: ['A:1:1'] }).expect(201);
    const r = await order(B, ev.id, { seats: ['A:1:2', 'A:1:3'] }).expect(409); // 1 pending + 2 > 2
    expect(r.body.message).toBe('You already have 1 Std ticket(s); the limit is 2 per person');
    await order(B, ev.id, { seats: ['A:6:1', 'A:6:2'] }).expect(201); // other type, own limit
    const again = await order(B, ev.id, { seats: ['A:6:3'] }).expect(409); // issued free tickets count
    expect(again.body.message).toBe('You already have 2 Free ticket(s); the limit is 2 per person');
    await order(B, ev.id, { seats: ['A:1:2'] }).expect(201);
    expect(await seat(ev.id, 'A:1:3')).toMatchObject({ status: 'AVAILABLE' });
    // sales window applies to seated types
    await prisma.ticketType.update({ where: { id: ev.vip }, data: { salesEndAt: new Date(Date.now() - 1000) } });
    await order(B, ev.id, { seats: ['B:1:1'] }).expect(409);
    expect(await seat(ev.id, 'B:1:1')).toMatchObject({ status: 'AVAILABLE' });
  });

  it('mixed order: seats plus standing quantity', async () => {
    const ev = await seatedEvent('Mixed');
    const B = await consumer();
    const r = await order(B, ev.id, { seats: ['A:2:1'], items: [{ ticketTypeId: ev.floor, quantity: 2 }] }).expect(201);
    expect(r.body).toMatchObject({ status: 'PENDING_PAYMENT', totalMmk: 20_000 });
    expect(r.body.items).toHaveLength(2);
    expect(r.body.items.find((i: any) => i.ticketTypeId === ev.floor)).toMatchObject({ quantity: 2, seats: [] });
    expect(await ttRow(ev.floor)).toMatchObject({ quota: 100, held: 2, sold: 0 });
    expect(await ttRow(ev.std)).toMatchObject({ held: 1 });
    await mockPay(await payWithMock(B, r.body.id));
    const tickets = await prisma.ticket.findMany({ where: { orderId: r.body.id } });
    expect(tickets).toHaveLength(3);
    expect(tickets.filter((t) => t.seatKey === null && t.ticketTypeId === ev.floor)).toHaveLength(2);
    expect(tickets.find((t) => t.seatKey === 'A:2:1')).toMatchObject({ seatLabel: 'Stalls · Row 2 · Seat 1', ticketTypeId: ev.std });
    expect(await ttRow(ev.floor)).toMatchObject({ quota: 100, held: 0, sold: 2 });
    expect(await ttRow(ev.std)).toMatchObject({ held: 0, sold: 1 });
    // a taken seat rolls back the standing hold as well
    const B2 = await consumer();
    await order(B2, ev.id, { seats: ['A:2:1'], items: [{ ticketTypeId: ev.floor, quantity: 1 }] }).expect(409);
    expect(await ttRow(ev.floor)).toMatchObject({ held: 0, sold: 2 });
    // promo codes act on seated lines too
    const owner = await prisma.user.findFirstOrThrow({ where: { email: `own-sc-${tag}@e2e.test` } });
    await prisma.promoCode.create({ data: { eventId: ev.id, code: `HALF${tag}`.toUpperCase(), kind: 'PERCENT', value: 5000, createdById: owner.id } });
    const pre = await http.post(`/v1/events/${ev.id}/promo-check`).set(B2).send({ code: `half${tag}`, seats: ['A:2:2', 'B:1:1'], items: [{ ticketTypeId: ev.floor, quantity: 1 }] }).expect(200);
    expect(pre.body).toMatchObject({ valid: true, subtotalMmk: 45_000, discountMmk: 22_500, totalMmk: 22_500 });
    const seatOnly = await http.post(`/v1/events/${ev.id}/promo-check`).set(B2).send({ code: `half${tag}`, seats: ['A:2:2'] }).expect(200);
    expect(seatOnly.body).toMatchObject({ valid: true, subtotalMmk: 10_000, totalMmk: 5_000 });
    await http.post(`/v1/events/${ev.id}/promo-check`).set(B2).send({ code: `half${tag}`, seats: ['Z:1:1'] }).expect(400);
    await http.post(`/v1/events/${ev.id}/promo-check`).set(B2).send({ code: `half${tag}` }).expect(400);
    expect(await seat(ev.id, 'A:2:2')).toMatchObject({ status: 'AVAILABLE' }); // preview reserves nothing
    const p = await order(B2, ev.id, { seats: ['A:2:2'], promoCode: `half${tag}` }).expect(201);
    expect(p.body).toMatchObject({ subtotalMmk: 10_000, discountMmk: 5_000, totalMmk: 5_000 });
  });
});

run('Guest seats', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  // Hall: section A has 2 rows of 5 seats (A:<row>:<n>)
  const hall = {
    width: 600,
    height: 400,
    sections: [{ key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [1, 2].map((r) => ({ label: String(r), seats: Array.from({ length: 5 }, (_, i) => ({ n: i + 1 })) })) }],
  };
  let A: Record<string, string>, O: Record<string, string>, orgId: string, versionId: string;

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const newPhone = () => `09${randomInt(700_000_000, 799_999_999)}`;
  async function login(phone: string) {
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return bearer(r2.body.accessToken as string);
  }
  const base = (eventId: string) => `/v1/organizations/${orgId}/events/${eventId}`;
  const seating = (eventId: string) => `${base(eventId)}/seating`;
  const seat = (eventId: string, key: string) => prisma.eventSeat.findUniqueOrThrow({ where: { eventId_seatKey: { eventId, seatKey: key } } });
  const ttRow = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });

  /** Published event on the hall: all 10 seats are Std (10,000, max 2 per person). */
  async function guestEvent(title: string) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 5 * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `${title} ${tag}`, titleMy: 'ဧည့်သည်', format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    const id = ev.body.id as string;
    const std = (await http.post(`${base(id)}/ticket-types`).set(O).send({ name: 'Std', priceMmk: 10_000, quota: 1, maxPerOrder: 2 }).expect(201)).body.id as string;
    await http.put(`${seating(id)}/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${seating(id)}/assignments`).set(O).send({ rules: [{ sectionKey: 'A', ticketTypeId: std }] }).expect(200);
    await prisma.event.update({ where: { id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    return { id, std };
  }
  const hold = (id: string, seats: string[], label = 'Sponsor') => http.post(`${seating(id)}/hold`).set(O).send({ seats, label });
  const comps = (id: string, seats: string[], phone: string, extra: object = {}) => http.post(`${seating(id)}/comps`).set(O).send({ seats, guestName: 'Daw Mya', phone, ...extra });

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    const adm = await app.get(AuthService).createInvitation({ email: `adm-g-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Guest Org ${tag}`, slug: `guest-${tag}`, ownerEmail: `own-g-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Guest Hall ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id;
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('hold rejects non-available seats', async () => {
    const ev = await guestEvent('Hold');
    await hold(ev.id, ['A:1:1']).expect(201);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'GUEST_HOLD', holdLabel: 'Sponsor' });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 9, sold: 0, held: 0 });
    const r = await hold(ev.id, ['A:1:1', 'A:1:2']).expect(409);
    expect(r.body.takenSeats).toEqual(['A:1:1']);
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ status: 'AVAILABLE' }); // all or none
    await hold(ev.id, ['Z:9:9']).expect(409).expect((x) => expect(x.body.takenSeats).toEqual(['Z:9:9']));
    // a buyer cannot take a held seat
    const B = await login(newPhone());
    await http.post(`/v1/events/${ev.id}/orders`).set(B).send({ seats: ['A:1:1'] }).expect(409);
    await hold(ev.id, []).expect(400);
    // strangers cannot hold
    await http.post(`${seating(ev.id)}/hold`).set(B).send({ seats: ['A:1:3'], label: 'x' }).expect(403);
  });

  it('release returns seats to sale', async () => {
    const ev = await guestEvent('Release');
    await hold(ev.id, ['A:1:1', 'A:1:2']).expect(201);
    await http.post(`${seating(ev.id)}/release`).set(O).send({ seats: ['A:1:1', 'A:1:3'] }).expect(409); // A:1:3 is not held; nothing changes
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'GUEST_HOLD' });
    await http.post(`${seating(ev.id)}/release`).set(O).send({ seats: ['A:1:1', 'A:1:2'] }).expect(200);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'AVAILABLE', holdLabel: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 10 });
    await http.post(`/v1/events/${ev.id}/orders`).set(await login(newPhone())).send({ seats: ['A:1:1'] }).expect(201);
  });

  it('released guest seats follow the current rules', async () => {
    const ev = await guestEvent('ReleaseRules');
    await hold(ev.id, ['A:1:1', 'A:2:1']).expect(201);
    // Only row 2 stays on sale (as a new type); row 1 has no rule any more
    const vip = (await http.post(`${base(ev.id)}/ticket-types`).set(O).send({ name: 'VIP', priceMmk: 30_000, quota: 1, maxPerOrder: 2 }).expect(201)).body.id as string;
    await http.put(`${seating(ev.id)}/assignments`).set(O).send({ rules: [{ sectionKey: 'A', rowLabel: '2', ticketTypeId: vip }] }).expect(200);
    await http.post(`${seating(ev.id)}/release`).set(O).send({ seats: ['A:1:1', 'A:2:1'] }).expect(200);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'UNSOLD', ticketTypeId: null, holdLabel: null });
    expect(await seat(ev.id, 'A:2:1')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: vip, holdLabel: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 0, held: 0, sold: 0 });
    expect(await ttRow(vip)).toMatchObject({ quota: 5, held: 0, sold: 0 });
  });

  it('comps issue tickets to a phone and mark seats sold', async () => {
    const ev = await guestEvent('Comp');
    await hold(ev.id, ['A:1:1', 'A:1:2'], 'Press').expect(201);
    const phone = newPhone();
    await comps(ev.id, ['A:1:3'], phone).expect(409); // not held
    await comps(ev.id, ['A:1:1'], '12345').expect(400);
    const r = await comps(ev.id, ['A:1:1', 'A:1:2'], phone, { label: 'VIP guest' }).expect(201);
    expect(r.body.tickets).toHaveLength(2);
    const order = await prisma.order.findFirstOrThrow({ where: { eventId: ev.id, channel: 'COMP' }, include: { items: true, tickets: true } });
    expect(order).toMatchObject({ status: 'CONFIRMED', subtotalMmk: 0n, totalMmk: 0n, commissionMmk: 0n });
    expect(order.items).toHaveLength(1);
    expect(order.items[0]).toMatchObject({ ticketTypeId: ev.std, quantity: 2, unitPriceMmk: 0n });
    expect(order.tickets.every((t) => t.isComplimentary && t.compLabel === 'VIP guest' && t.guestName === 'Daw Mya')).toBe(true);
    for (const t of order.tickets) expect(await seat(ev.id, t.seatKey!)).toMatchObject({ status: 'SOLD', ticketId: t.id, orderId: order.id });
    // comps are outside quota and sold; ledger untouched
    expect(await ttRow(ev.std)).toMatchObject({ quota: 8, sold: 0, held: 0 });
    expect(await prisma.ledgerEntry.count({ where: { refId: order.id } })).toBe(0);
    // the guest signs in with that phone and sees seat + Complimentary
    const G = await login(phone);
    const mine = await http.get('/v1/me/tickets').set(G).expect(200);
    const t1 = mine.body.find((t: any) => t.seatKey === 'A:1:1');
    expect(t1).toMatchObject({ seatLabel: 'Stalls · Row 1 · Seat 1', seatLabelMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1', isComplimentary: true, compLabel: 'VIP guest', canTransfer: false });
    expect(t1.qr).toBeTruthy();
    expect(await prisma.notification.count({ where: { userId: order.userId, kind: 'ticket_received' } })).toBe(1);
    // comps do not count toward the per-person limit: the guest can still buy up to maxPerOrder (2)
    await http.post(`/v1/events/${ev.id}/orders`).set(G).send({ seats: ['A:2:1', 'A:2:2'] }).expect(201);
    await http.post(`/v1/events/${ev.id}/orders`).set(G).send({ seats: ['A:2:3'] }).expect(409);
  });

  it('comps excluded from sales, revenue and milestones', async () => {
    const ev = await guestEvent('Figures');
    await hold(ev.id, ['A:1:1', 'A:1:2']).expect(201);
    const checkSales = jest.spyOn(app.get(NotifyService), 'checkSales');
    await comps(ev.id, ['A:1:1', 'A:1:2'], newPhone()).expect(201);
    expect(checkSales).not.toHaveBeenCalled();
    checkSales.mockRestore();
    const before = (await http.get(`${base(ev.id)}/dashboard`).set(O).expect(200)).body.totals;
    expect(before).toMatchObject({ orders: 0, ticketsSold: 0, revenueMmk: 0 });
    // one real paid order is the only thing counted
    const real = await prisma.user.create({ data: { phone: newPhone() } });
    await prisma.order.create({ data: { userId: real.id, eventId: ev.id, status: 'PAID', subtotalMmk: 10_000n, totalMmk: 10_000n, commissionMmk: 500n, paidAt: new Date() } });
    const after = (await http.get(`${base(ev.id)}/dashboard`).set(O).expect(200)).body;
    expect(after.totals).toMatchObject({ orders: 1, revenueMmk: 10_000 });
    expect(after.daily.reduce((s: number, d: any) => s + d.orders, 0)).toBe(1);
    const sales = await http.get(`${base(ev.id)}/sales`).set(O).expect(200);
    expect(sales.body.paidOrders).toBe(1);
    const csv = await http.get(`${base(ev.id)}/attendees.csv`).set(O).expect(200);
    expect(csv.text.split('\r\n')[0]).toContain('complimentary');
    expect(csv.text).toContain('"yes"');
  });

  it('recountTicketTypes excludes comps from quota and sold', async () => {
    const ev = await guestEvent('Recount');
    await hold(ev.id, ['A:1:1', 'A:1:2']).expect(201);
    await comps(ev.id, ['A:1:1'], newPhone()).expect(201);
    // a buyer's sold seat
    const buyer = await prisma.user.create({ data: { phone: newPhone() } });
    const o = await prisma.order.create({ data: { userId: buyer.id, eventId: ev.id, status: 'PAID', subtotalMmk: 10_000n, totalMmk: 10_000n, paidAt: new Date() } });
    const t = await prisma.ticket.create({ data: { orderId: o.id, ticketTypeId: ev.std, holderUserId: buyer.id, seatKey: 'A:2:1' } });
    await prisma.eventSeat.update({ where: { eventId_seatKey: { eventId: ev.id, seatKey: 'A:2:1' } }, data: { status: 'SOLD', orderId: o.id, ticketId: t.id } });
    await prisma.$transaction((tx) => app.get(EventSeatsService).recountTicketTypes(tx, ev.id));
    // 10 seats - 1 comp - 1 guest hold = 8 sellable (incl. the buyer's); only the buyer's counts as sold
    expect(await ttRow(ev.std)).toMatchObject({ quota: 8, sold: 1, held: 0 });
  });

  it('comp ticket cannot be transferred', async () => {
    const ev = await guestEvent('Transfer');
    await hold(ev.id, ['A:1:1']).expect(201);
    const phone = newPhone();
    await comps(ev.id, ['A:1:1'], phone).expect(201);
    const G = await login(phone);
    const t = (await http.get('/v1/me/tickets').set(G).expect(200)).body.find((x: any) => x.seatKey === 'A:1:1');
    const r = await http.post(`/v1/me/tickets/${t.id}/transfer`).set(G).send({ phone: newPhone() }).expect(409);
    expect(r.body.message).toBe("Guest tickets can't be transferred");
  });

  it('revoking one of several comps returns only that seat to GUEST_HOLD', async () => {
    const ev = await guestEvent('Revoke');
    await hold(ev.id, ['A:1:1', 'A:1:2', 'A:1:3'], 'Sponsor').expect(201);
    await comps(ev.id, ['A:1:1', 'A:1:2', 'A:1:3'], newPhone(), { label: 'Speaker' }).expect(201);
    const list = await http.get(`${seating(ev.id)}/guests`).set(O).expect(200);
    expect(list.body).toHaveLength(3);
    expect(list.body[0]).toMatchObject({ guestName: 'Daw Mya', label: 'Speaker', status: 'VALID', checkedIn: false });
    expect(list.body[0].phone).toMatch(/•••/);
    const [first, ...rest] = list.body as { id: string; seatKey: string }[];
    await http.post(`${seating(ev.id)}/comps/${first.id}/revoke`).set(O).expect(200);
    const t = await prisma.ticket.findUniqueOrThrow({ where: { id: first.id } });
    expect(t.status).toBe('VOID');
    expect(await seat(ev.id, first.seatKey)).toMatchObject({ status: 'GUEST_HOLD', holdLabel: 'Speaker', ticketId: null, orderId: null });
    for (const r of rest) expect(await seat(ev.id, r.seatKey)).toMatchObject({ status: 'SOLD', ticketId: r.id });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 7, sold: 0 });
    const order = () => prisma.order.findUniqueOrThrow({ where: { id: t.orderId } });
    expect((await order()).status).toBe('CONFIRMED');
    await http.post(`${seating(ev.id)}/comps/${first.id}/revoke`).set(O).expect(409); // already void
    for (const r of rest) await http.post(`${seating(ev.id)}/comps/${r.id}/revoke`).set(O).expect(200);
    expect((await order()).status).toBe('CANCELLED');
    // the freed seat can be issued again from its hold
    await comps(ev.id, [first.seatKey], newPhone()).expect(201);
  });

  it('cannot revoke a guest who already checked in; blank names and labels are rejected; comp orders have no paidAt', async () => {
    const ev = await guestEvent('Checked');
    await hold(ev.id, ['A:1:1', 'A:1:2']).expect(201);
    await comps(ev.id, ['A:1:1'], newPhone(), { guestName: '   ' }).expect(400);
    await comps(ev.id, ['A:1:1'], newPhone(), { label: 'x', guestName: '  Daw Mya  ' }).expect(201);
    await http.post(`${seating(ev.id)}/hold`).set(O).send({ seats: ['A:1:3'], label: '   ' }).expect(400);
    const t = await prisma.ticket.findFirstOrThrow({ where: { order: { eventId: ev.id } }, include: { order: true } });
    expect(t.guestName).toBe('Daw Mya');
    expect(t.order.paidAt).toBeNull();
    await prisma.ticket.update({ where: { id: t.id }, data: { status: 'CHECKED_IN' } });
    const r = await http.post(`${seating(ev.id)}/comps/${t.id}/revoke`).set(O).expect(409);
    expect(r.body.message).toBe('This guest has already checked in');
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'SOLD', ticketId: t.id });
    expect((await prisma.ticket.findUniqueOrThrow({ where: { id: t.id } })).status).toBe('CHECKED_IN');
    // checked-in tickets are not printed (only VALID ones), so nothing is left to print
    await http.get(`${seating(ev.id)}/comps.pdf`).set(O).expect(404);
  });

  it('comps.pdf has one page per ticket', async () => {
    const ev = await guestEvent('Pdf');
    await hold(ev.id, ['A:1:1', 'A:1:2', 'A:1:3']).expect(201);
    await comps(ev.id, ['A:1:1', 'A:1:2', 'A:1:3'], newPhone(), { label: 'Press' }).expect(201);
    const get = (q = '') =>
      http
        .get(`${seating(ev.id)}/comps.pdf${q}`)
        .set(O)
        .buffer(true)
        .parse((res: any, cb: any) => {
          const chunks: Buffer[] = [];
          res.on('data', (c: Buffer) => chunks.push(c));
          res.on('end', () => cb(null, Buffer.concat(chunks)));
        });
    const pages = (b: Buffer) => (b.toString('latin1').match(/\/Type \/Page(?!s)/g) ?? []).length;
    const all = await get().expect(200);
    expect(all.headers['content-type']).toContain('application/pdf');
    expect((all.body as Buffer).subarray(0, 4).toString()).toBe('%PDF');
    expect(pages(all.body)).toBe(3);
    const ids = (await prisma.ticket.findMany({ where: { order: { eventId: ev.id } }, select: { id: true }, take: 2 })).map((t) => t.id);
    const two = await get(`?ids=${ids.join(',')}`).expect(200);
    expect(pages(two.body)).toBe(2);
    await get('?ids=nope').expect(400);
    // JSON for the portal print page: signed QR token per VALID comp, editors only
    const data = await http.get(`${seating(ev.id)}/comps/print?ids=${ids.join(',')}`).set(O).expect(200);
    expect(data.body.event.title).toBeTruthy();
    expect(data.body.tickets).toHaveLength(2);
    expect(data.body.tickets[0]).toMatchObject({ seatLabel: expect.any(String), compLabel: 'Press' });
    expect(data.body.tickets[0].token).toMatch(/\./);
    await http.get(`${seating(ev.id)}/comps/print`).expect(401);
    expect((await http.get(`${seating(ev.id)}/comps/print`).set(O).expect(200)).headers['cache-control']).toContain('no-store');
    // a finance member can view the seating but not fetch QR payloads
    const inv = await http.post(`/v1/organizations/${orgId}/invitations`).set(O).send({ email: `fin-${newPhone()}@e2e.test`, role: 'ORG_FINANCE' }).expect(201);
    const F = await acceptInvite(inv.body.inviteUrl);
    await http.get(`${seating(ev.id)}/guests`).set(F).expect(200);
    await http.get(`${seating(ev.id)}/comps/print`).set(F).expect(403);
    // revoked comps drop out of the print payload
    await http.post(`${seating(ev.id)}/comps/${ids[0]}/revoke`).set(O).expect(200);
    const after = await http.get(`${seating(ev.id)}/comps/print`).set(O).expect(200);
    expect(after.body.tickets.map((x: any) => x.id)).not.toContain(ids[0]);
    expect(after.body.tickets).toHaveLength(2);
  });
});

run('Seat everywhere', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  let prisma: PrismaService;
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });
  // Hall: section A has 2 rows of 5 seats; row 1 is Free, row 2 is Std (10,000)
  const hall = {
    width: 600,
    height: 400,
    sections: [{ key: 'A', name: 'Stalls', nameMy: 'ရှေ့ခန်း', kind: 'SEATED', x: 10, y: 10, rows: [1, 2].map((r) => ({ label: String(r), seats: Array.from({ length: 5 }, (_, i) => ({ n: i + 1 })) })) }],
  };
  let A: Record<string, string>, O: Record<string, string>, orgId: string, versionId: string;

  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return bearer(r.body.accessToken as string);
  }
  const newPhone = () => `09${randomInt(700_000_000, 799_999_999)}`;
  async function login(phone = newPhone()) {
    const r1 = await http.post('/v1/auth/otp/request').send({ phone }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone, code: r1.body.devCode }).expect(200);
    return bearer(r2.body.accessToken as string);
  }
  const base = (eventId: string) => `/v1/organizations/${orgId}/events/${eventId}`;
  const seat = (eventId: string, key: string) => prisma.eventSeat.findUniqueOrThrow({ where: { eventId_seatKey: { eventId, seatKey: key } } });
  const ttRow = (id: string) => prisma.ticketType.findUniqueOrThrow({ where: { id } });
  const mine = async (B: Record<string, string>) => (await http.get('/v1/me/tickets').set(B).expect(200)).body as any[];

  async function newEvent(title: string, startsInDays = 5) {
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + startsInDays * 86400e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `${title} ${tag}`, format: 'IN_PERSON', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3 * 3600e3).toISOString() })
      .expect(201);
    return ev.body.id as string;
  }
  const publish = (id: string) => prisma.event.update({ where: { id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
  async function seatedEvent(title: string) {
    const id = await newEvent(title);
    const add = async (b: object) => (await http.post(`${base(id)}/ticket-types`).set(O).send(b).expect(201)).body.id as string;
    const free = await add({ name: 'Free', priceMmk: 0, quota: 1, maxPerOrder: 4 });
    const std = await add({ name: 'Std', priceMmk: 10_000, quota: 1, maxPerOrder: 4 });
    await http.put(`${base(id)}/seating/map`).set(O).send({ seatMapVersionId: versionId }).expect(200);
    await http.put(`${base(id)}/seating/assignments`).set(O).send({ rules: [{ sectionKey: 'A', rowLabel: '1', ticketTypeId: free }, { sectionKey: 'A', rowLabel: '2', ticketTypeId: std }] }).expect(200);
    await publish(id);
    return { id, free, std };
  }
  const order = (B: Record<string, string>, eventId: string, body: object) => http.post(`/v1/events/${eventId}/orders`).set(B).send(body);

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.PAYMENTS_MOCK = 'true';
    process.env.SETTINGS_KEY ??= randomBytes(32).toString('base64');
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    prisma = app.get(PrismaService);
    const adm = await app.get(AuthService).createInvitation({ email: `adm-ev-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    A = await acceptInvite(adm.url);
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Everywhere Org ${tag}`, slug: `every-${tag}`, ownerEmail: `own-ev-${tag}@e2e.test` }).expect(201);
    orgId = org.body.organization.id;
    O = await acceptInvite(org.body.inviteUrl);
    const m = await http.post('/v1/admin/seat-maps').set(A).send({ venueName: `Every Hall ${tag}`, city: 'Yangon' }).expect(201);
    await http.put(`/v1/admin/seat-maps/${m.body.id}/draft`).set(A).send({ layout: hall }).expect(200);
    versionId = (await http.post(`/v1/admin/seat-maps/${m.body.id}/publish`).set(A).expect(200)).body.id;
  });
  afterAll(async () => {
    await app.get(NotifyService).idle();
    await app?.close();
  });

  it('my tickets show seat label', async () => {
    const ev = await seatedEvent('MySeat');
    const B = await login();
    await order(B, ev.id, { seats: ['A:1:1'] }).expect(201);
    const t = (await mine(B)).find((x) => x.seatKey === 'A:1:1');
    expect(t).toMatchObject({ seatLabel: 'Stalls · Row 1 · Seat 1', seatLabelMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1', isComplimentary: false, canCancel: true, canTransfer: true });
  });

  it('crew manifest and scan include seat', async () => {
    const ev = await seatedEvent('Crew');
    const B = await login();
    await order(B, ev.id, { seats: ['A:1:2'] }).expect(201);
    // a guest ticket reads "<guest> · Complimentary · <label>"
    await http.post(`${base(ev.id)}/seating/hold`).set(O).send({ seats: ['A:2:1'], label: 'Press' }).expect(201);
    await http.post(`${base(ev.id)}/seating/comps`).set(O).send({ seats: ['A:2:1'], guestName: 'Daw Mya', phone: newPhone(), label: 'VIP guest' }).expect(201);
    const man = await http.get(`/v1/crew/events/${ev.id}/manifest`).set(O).expect(200);
    const t = man.body.tickets.find((x: any) => x.seat === 'Stalls · Row 1 · Seat 2');
    expect(t).toMatchObject({ seat: 'Stalls · Row 1 · Seat 2', seatMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 2' });
    const comp = man.body.tickets.find((x: any) => x.seat === 'Stalls · Row 2 · Seat 1');
    expect(comp.holderName).toBe('Daw Mya · Complimentary · VIP guest');
    const s = await http.get(`/v1/crew/events/${ev.id}/search`).query({ q: 'Daw' }).set(O).expect(200);
    expect(s.body[0]).toMatchObject({ seat: 'Stalls · Row 2 · Seat 1', holderName: 'Daw Mya · Complimentary · VIP guest' });
    const mt = (await mine(B)).find((x) => x.seatKey === 'A:1:2');
    const qr = mt.qr as string;
    const scan = await http.post(`/v1/crew/events/${ev.id}/scan`).set(O).send({ qr }).expect(200);
    expect(scan.body.ticket).toMatchObject({ seat: 'Stalls · Row 1 · Seat 2', seatMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 2' });
    const st = await http.get(`/v1/crew/events/${ev.id}/stats`).set(O).expect(200);
    expect(st.body.byTicketType.find((x: any) => x.id === ev.std).comp).toBe(1);
    expect(st.body.byTicketType.find((x: any) => x.id === ev.free).comp).toBe(0);
    const dash = await http.get(`${base(ev.id)}/dashboard`).set(O).expect(200);
    expect(dash.body.ticketTypes.find((x: any) => x.id === ev.free).seats).toEqual({ available: 4, held: 0, guest: 0, sold: 1, comp: 0 });
    expect(dash.body.ticketTypes.find((x: any) => x.id === ev.std).seats).toEqual({ available: 4, held: 0, guest: 0, sold: 0, comp: 1 });
  });

  it('attendee CSV has Seat column', async () => {
    const ev = await seatedEvent('Csv');
    const B = await login();
    await order(B, ev.id, { seats: ['A:1:3'] }).expect(201);
    const r = await http.get(`${base(ev.id)}/attendees.csv`).set(O).expect(200);
    const [header, row] = (r.text as string).replace('﻿', '').split('\r\n');
    expect(header.split(',')).toContain('seat');
    expect(row).toContain('"Stalls · Row 1 · Seat 3"');
    // the portal's attendee list carries the seat, the comp flag and the guest name
    await http.post(`${base(ev.id)}/seating/hold`).set(O).send({ seats: ['A:2:2'], label: 'Press' }).expect(201);
    await http.post(`${base(ev.id)}/seating/comps`).set(O).send({ seats: ['A:2:2'], guestName: 'U Ba', phone: newPhone() }).expect(201);
    const list = (await http.get(`${base(ev.id)}/attendees`).set(O).expect(200)).body as any[];
    expect(list.find((x) => x.seatLabel === 'Stalls · Row 1 · Seat 3')).toMatchObject({ seatLabelMy: 'ရှေ့ခန်း · အတန်း 1 · ခုံ 3', isComplimentary: false, guestName: null });
    expect(list.find((x) => x.seatLabel === 'Stalls · Row 2 · Seat 2')).toMatchObject({ isComplimentary: true, guestName: 'U Ba' });
  });

  it('cancel free seated ticket frees the seat', async () => {
    const ev = await seatedEvent('CancelSeated');
    const B = await login();
    const o = await order(B, ev.id, { seats: ['A:1:1', 'A:1:2'] }).expect(201);
    expect(await ttRow(ev.free)).toMatchObject({ sold: 2, quota: 5 });
    const [t1, t2] = await mine(B);
    const first = t1.seatKey === 'A:1:1' ? t1 : t2;
    const other = first === t1 ? t2 : t1;
    await http.post(`/v1/me/tickets/${first.id}/cancel`).set(await login()).expect(404);
    await http.post(`/v1/me/tickets/${first.id}/cancel`).set(B).expect(200, { ok: true });
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'AVAILABLE', ticketId: null, orderId: null });
    expect(await ttRow(ev.free)).toMatchObject({ sold: 1, quota: 5, held: 0 });
    const row = await prisma.ticket.findUniqueOrThrow({ where: { id: first.id } });
    expect(row.status).toBe('VOID');
    expect(row.qrVersion).toBe(2);
    await http.post(`/v1/me/tickets/${first.id}/cancel`).set(B).expect(409); // already void
    expect((await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).status).toBe('CONFIRMED');
    // the seat is for sale again
    await order(await login(), ev.id, { seats: ['A:1:1'] }).expect(201);
    // cancelling the last ticket cancels the order
    await http.post(`/v1/me/tickets/${other.id}/cancel`).set(B).expect(200);
    expect((await prisma.order.findUniqueOrThrow({ where: { id: o.body.id } })).status).toBe('CANCELLED');
    expect(await ttRow(ev.free)).toMatchObject({ sold: 1, quota: 5 });
  });

  it('a cancelled free seat follows the current rules', async () => {
    const ev = await seatedEvent('CancelRules');
    const B = await login();
    await order(B, ev.id, { seats: ['A:1:1', 'A:1:2'] }).expect(201);
    const assign = (rules: object[]) => http.put(`${base(ev.id)}/seating/assignments`).set(O).send({ rules }).expect(200);
    const byKey = new Map((await mine(B)).map((t) => [t.seatKey, t.id]));
    // Row 1 loses its rule: the cancelled seat is not on sale
    await assign([{ sectionKey: 'A', rowLabel: '2', ticketTypeId: ev.std }]);
    expect(await ttRow(ev.free)).toMatchObject({ quota: 2, sold: 2 });
    await http.post(`/v1/me/tickets/${byKey.get('A:1:1')}/cancel`).set(B).expect(200);
    expect(await seat(ev.id, 'A:1:1')).toMatchObject({ status: 'UNSOLD', ticketTypeId: null, ticketId: null, orderId: null });
    expect(await ttRow(ev.free)).toMatchObject({ quota: 1, sold: 1, held: 0 });
    // The whole section goes to Std: the next cancelled seat comes back as Std
    await assign([{ sectionKey: 'A', ticketTypeId: ev.std }]);
    expect(await ttRow(ev.std)).toMatchObject({ quota: 9 });
    await http.post(`/v1/me/tickets/${byKey.get('A:1:2')}/cancel`).set(B).expect(200);
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ status: 'AVAILABLE', ticketTypeId: ev.std, ticketId: null });
    expect(await ttRow(ev.std)).toMatchObject({ quota: 10, sold: 0, held: 0 });
    expect(await ttRow(ev.free)).toMatchObject({ quota: 0, sold: 0, held: 0 });
  });

  it('cancel free unseated ticket returns quota', async () => {
    const id = await newEvent('CancelUnseated');
    const tt = (await http.post(`${base(id)}/ticket-types`).set(O).send({ name: 'Free', priceMmk: 0, quota: 10, maxPerOrder: 4 }).expect(201)).body.id as string;
    await publish(id);
    const B = await login();
    await http.post(`/v1/events/${id}/registrations`).set(B).send({ ticketTypeId: tt, quantity: 2 }).expect(201);
    expect((await ttRow(tt)).sold).toBe(2);
    const [t] = await mine(B);
    expect(t.canCancel).toBe(true);
    await http.post(`/v1/me/tickets/${t.id}/cancel`).set(B).expect(200, { ok: true });
    expect((await ttRow(tt)).sold).toBe(1);
    await http.post(`/v1/me/tickets/${t.id}/cancel`).set(B).expect(409);
    expect((await ttRow(tt)).sold).toBe(1);
  });

  async function promo(eventId: string, value: number, maxUses: number | null) {
    const owner = await prisma.user.findFirstOrThrow({ where: { email: `own-ev-${tag}@e2e.test` } });
    const code = `P${randomBytes(4).toString('hex')}`.toUpperCase();
    const row = await prisma.promoCode.create({ data: { eventId, code, kind: 'PERCENT', value, maxUses, createdById: owner.id } });
    return { code, id: row.id };
  }
  const promoUsed = async (id: string) => (await prisma.promoCode.findUniqueOrThrow({ where: { id } })).used;

  it('cancelling the last ticket of a 100% promo order gives the use back', async () => {
    const ev = await seatedEvent('CancelPromo');
    const pc = await promo(ev.id, 10_000, 1);
    const B = await login();
    const o = await order(B, ev.id, { seats: ['A:2:1'], promoCode: pc.code }).expect(201);
    expect(o.body).toMatchObject({ status: 'CONFIRMED', totalMmk: 0 });
    expect(await promoUsed(pc.id)).toBe(1);
    const B2 = await login();
    const used = await order(B2, ev.id, { seats: ['A:2:2'], promoCode: pc.code });
    expect(used.status).toBe(400);
    expect(JSON.stringify(used.body)).toContain('This code has been used up');
    const t = (await mine(B)).find((x) => x.seatKey === 'A:2:1');
    await http.post(`/v1/me/tickets/${t.id}/cancel`).set(B).expect(200);
    expect(await promoUsed(pc.id)).toBe(0);
    await order(B2, ev.id, { seats: ['A:2:2'], promoCode: pc.code }).expect(201);
    expect(await promoUsed(pc.id)).toBe(1);
  });

  it('partial cancel keeps the use', async () => {
    const ev = await seatedEvent('CancelPromoPartial');
    const pc = await promo(ev.id, 10_000, 5);
    const B = await login();
    await order(B, ev.id, { seats: ['A:2:1', 'A:2:2'], promoCode: pc.code }).expect(201);
    expect(await promoUsed(pc.id)).toBe(1);
    const [t1, t2] = await mine(B);
    await http.post(`/v1/me/tickets/${t1.id}/cancel`).set(B).expect(200);
    expect(await promoUsed(pc.id)).toBe(1);
    await http.post(`/v1/me/tickets/${t2.id}/cancel`).set(B).expect(200);
    expect(await promoUsed(pc.id)).toBe(0);
  });

  it('admin refund keeps the use', async () => {
    const ev = await seatedEvent('RefundPromo');
    const pc = await promo(ev.id, 5_000, 5);
    const B = await login();
    const o = await order(B, ev.id, { seats: ['A:2:1'], promoCode: pc.code }).expect(201);
    expect(o.body).toMatchObject({ totalMmk: 5_000 });
    const pay = await http.post(`/v1/orders/${o.body.id}/pay`).set(B).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(pay.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t')! }).expect(201);
    expect(await promoUsed(pc.id)).toBe(1);
    await http.post(`/v1/admin/finance/orders/${o.body.id}/refund`).set(A).send({ reason: 'Buyer request' }).expect(200);
    expect(await promoUsed(pc.id)).toBe(1);
  });

  it('cannot cancel paid ticket', async () => {
    const ev = await seatedEvent('CancelPaid');
    const B = await login();
    const o = await order(B, ev.id, { seats: ['A:2:1'] }).expect(201);
    const p = await http.post(`/v1/orders/${o.body.id}/pay`).set(B).send({ provider: 'MOCK' }).expect(200);
    const url = new URL(p.body.payment.action.url);
    await http.post(`${url.pathname}/pay`).type('form').send({ t: url.searchParams.get('t')! }).expect(201);
    const t = (await mine(B)).find((x) => x.seatKey === 'A:2:1');
    expect(t.canCancel).toBe(false);
    await http.post(`/v1/me/tickets/${t.id}/cancel`).set(B).expect(409);
    expect(await seat(ev.id, 'A:2:1')).toMatchObject({ status: 'SOLD', ticketId: t.id });
  });

  it('cannot cancel a guest ticket, or after the event starts', async () => {
    const ev = await seatedEvent('CancelGuest');
    await http.post(`${base(ev.id)}/seating/hold`).set(O).send({ seats: ['A:1:1'], label: 'x' }).expect(201);
    const phone = newPhone();
    await http.post(`${base(ev.id)}/seating/comps`).set(O).send({ seats: ['A:1:1'], guestName: 'G', phone }).expect(201);
    const G = await login(phone);
    const g = (await mine(G))[0];
    expect(g.canCancel).toBe(false);
    await http.post(`/v1/me/tickets/${g.id}/cancel`).set(G).expect(409);

    const B = await login();
    await order(B, ev.id, { seats: ['A:1:2'] }).expect(201);
    const t = (await mine(B))[0];
    expect(t.canCancel).toBe(true);
    await prisma.event.update({ where: { id: ev.id }, data: { startsAt: new Date(Date.now() - 3600e3) } });
    expect((await mine(B))[0].canCancel).toBe(false);
    const r = await http.post(`/v1/me/tickets/${t.id}/cancel`).set(B).expect(409);
    expect(r.body.message).toBe('The event has already started');
    expect(await seat(ev.id, 'A:1:2')).toMatchObject({ status: 'SOLD' });
  });

  it('transfer keeps the seat', async () => {
    const ev = await seatedEvent('Transfer');
    const B = await login();
    await order(B, ev.id, { seats: ['A:1:4'] }).expect(201);
    const before = (await mine(B))[0];
    const phone = newPhone();
    await http.post(`/v1/me/tickets/${before.id}/transfer`).set(B).send({ phone }).expect(200);
    const R = await login(phone);
    const after = (await mine(R))[0];
    expect(after).toMatchObject({ id: before.id, seatKey: 'A:1:4', seatLabel: before.seatLabel, seatLabelMy: before.seatLabelMy });
    expect(after.qr).not.toBe(before.qr);
    expect((await prisma.ticket.findUniqueOrThrow({ where: { id: before.id } })).qrVersion).toBe(2); // default 1, bumped by the transfer
    expect(await seat(ev.id, 'A:1:4')).toMatchObject({ status: 'SOLD', ticketId: before.id });
    // the new holder can cancel (their own free ticket); the old one no longer can
    await http.post(`/v1/me/tickets/${before.id}/cancel`).set(B).expect(404);
  });
});
