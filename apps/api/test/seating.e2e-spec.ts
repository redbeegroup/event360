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
import { EventSeatsService } from '../src/modules/seating/event-seats.service';
import { SeatMapsService } from '../src/modules/seating/seat-maps.service';
import { expandSeats } from '../src/modules/seating/layout';

const run = process.env.DATABASE_URL ? describe : describe.skip;
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
