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

  it.todo('new version does not touch events');

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
