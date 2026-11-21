// Load test data on dev: a PRIVATE event (not listed anywhere) with two free ticket types and a crew code.
// MODE=cleanup removes the event(s) and every user the test created (phones +95969000xxxx, created after the event).
// MODE=seated creates a second private event (slug loadtest-seated) with a published seat map and 500 assigned seats;
// MODE=seated-check prints the post-run consistency numbers for it. Both need dist/ (the API image's working dir).
const { PrismaClient } = require('@prisma/client');
const { createHash, randomBytes } = require('crypto');
const path = require('path');
const dbUrl = process.env.DATABASE_URL ?? '';
// LOADTEST_ALLOW_LOCAL=1 lifts the schema=dev rule for a local database only (localhost / 127.0.0.1 / ::1).
const localOk = process.env.LOADTEST_ALLOW_LOCAL === '1' && /^postgres(ql)?:\/\/[^/?#]*@(localhost|127\.0\.0\.1|\[::1\])(:\d+)?\//.test(dbUrl);
if (!/[?&]schema=dev(&|$)/.test(dbUrl) && !localOk) {
  console.error('Refusing to run: the load-test data script is for the dev schema only.');
  process.exit(2);
}
const prisma = new PrismaClient();
const SLUG = 'loadtest-event';
const SEATED_SLUG = 'loadtest-seated';
const MAP_NAME = 'loadtest map';
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

async function pickOrg() {
  const sampleOrg = { where: { events: { some: { slug: { startsWith: 'sample-' } } } }, include: { members: true }, orderBy: { createdAt: 'asc' } };
  // The fallback (any org with a member) is for a local database that has no sample data
  return (await prisma.organization.findFirst(sampleOrg)) ?? (localOk ? await prisma.organization.findFirst({ where: { members: { some: {} } }, include: { members: true }, orderBy: { createdAt: 'asc' } }) : null);
}

async function seed() {
  await cleanup(SLUG);
  const org = await pickOrg();
  const creator = org.members[0]?.userId ?? (await prisma.user.findFirst({ where: { platformRoles: { has: 'PLATFORM_ADMIN' } } })).id;
  const cat = await prisma.category.findFirst({ where: { parentId: { not: null } } });
  const start = new Date(Date.now() + 2 * 3600e3);
  const ev = await prisma.event.create({
    data: {
      organizationId: org.id, categoryId: cat.id, title: 'Load test (private, temporary)', slug: SLUG,
      status: 'PUBLISHED', format: 'IN_PERSON', visibility: 'PRIVATE', isFree: true,
      startsAt: start, endsAt: new Date(start.getTime() + 4 * 3600e3), publishedAt: new Date(),
      ticketTypes: { create: [
        { name: 'Rush', quota: 300, maxPerOrder: 1 },
        { name: 'Door', quota: 2000, maxPerOrder: 1 },
      ] },
    },
    include: { ticketTypes: true },
  });
  const code = randomBytes(6).toString('hex').toUpperCase();
  await prisma.eventAccessCode.create({ data: { eventId: ev.id, codeHash: sha256(code), label: 'load test', gate: 'LT', createdById: creator, expiresAt: new Date(start.getTime() + 24 * 3600e3) } });
  const sample = await prisma.event.findFirst({ where: { status: 'PUBLISHED', visibility: 'PUBLIC', slug: { startsWith: 'sample-' } }, select: { slug: true } });
  console.log('LOADTEST ' + JSON.stringify({ eventId: ev.id, rush: ev.ticketTypes.find((t) => t.name === 'Rush').id, door: ev.ticketTypes.find((t) => t.name === 'Door').id, code, sample: sample?.slug }));
}

// Layout built to the same schema as the theatre fixture (that file is not shipped in the API image):
// Stalls 10 rows x 30 = 300 and Circle 8 rows x 25 = 200 are sold; Balcony 4 rows x 25 = 100 stays unassigned.
function seatedLayout() {
  const block = (key, name, nameMy, x, y, curve, rows, perRow) => ({
    key, name, nameMy, kind: 'SEATED', x, y, curve,
    rows: Array.from({ length: rows }, (_, r) => ({ label: String.fromCharCode(65 + r), seats: Array.from({ length: perRow }, (_, i) => ({ n: i + 1 })) })),
  });
  return {
    width: 1400, height: 1000, stage: { x: 420, y: 40, w: 560, h: 60, label: 'Stage' },
    sections: [
      block('S', 'Stalls', 'ရှေ့ခန်း', 320, 160, 0.1, 10, 30),
      block('C', 'Circle', 'ဘောင်းခန်း', 360, 460, 0.12, 8, 25),
      block('B', 'Balcony', 'ဘယ်လ်ကနီ', 360, 720, 0.1, 4, 25),
    ],
  };
}

// Same statement as EventSeatsService.recountTicketTypes (no `only` filter).
async function recount(tx, eventId) {
  await tx.$executeRaw`
    UPDATE ticket_types tt SET quota = c.quota, held = c.held, sold = c.sold
    FROM (
      SELECT tt2.id,
        count(*) FILTER (WHERE s.status IN ('AVAILABLE', 'CHECKOUT_HOLD') OR (s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false)))::int AS quota,
        count(*) FILTER (WHERE s.status = 'CHECKOUT_HOLD')::int AS held,
        count(*) FILTER (WHERE s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false))::int AS sold
      FROM ticket_types tt2
      LEFT JOIN event_seats s ON s.ticket_type_id = tt2.id
      LEFT JOIN tickets t ON t.id = s.ticket_id
      WHERE tt2.event_id = ${eventId}::uuid AND EXISTS (SELECT 1 FROM event_seats x WHERE x.ticket_type_id = tt2.id)
      GROUP BY tt2.id
    ) c
    WHERE tt.id = c.id`;
}

async function seedSeated() {
  await cleanup(SEATED_SLUG);
  const { expandSeats, validateLayout } = require(path.join(process.cwd(), 'dist/modules/seating/layout'));
  const v = validateLayout(seatedLayout());
  if (!v.ok) throw new Error('layout invalid: ' + v.problems.join('; '));
  const layout = v.layout;
  const seats = expandSeats(layout);
  const org = await pickOrg();
  const creator = org.members[0]?.userId ?? (await prisma.user.findFirst({ where: { platformRoles: { has: 'PLATFORM_ADMIN' } } })).id;
  const cat = await prisma.category.findFirst({ where: { parentId: { not: null } } });
  const start = new Date(Date.now() + 2 * 3600e3);
  const ev = await prisma.$transaction(async (tx) => {
    // SeatMapsService.create + saveDraft + publish
    const map = await tx.seatMap.create({ data: { venueName: MAP_NAME, city: 'Yangon' } });
    const version = await tx.seatMapVersion.create({ data: { seatMapId: map.id, version: 1, layout, seatCount: seats.length, createdById: creator, publishedAt: new Date() } });
    const venue = await tx.venue.create({ data: { name: MAP_NAME, city: 'Yangon' } });
    const e = await tx.event.create({
      data: {
        organizationId: org.id, categoryId: cat.id, title: 'Load test seated (private, temporary)', slug: SEATED_SLUG,
        status: 'PUBLISHED', format: 'IN_PERSON', visibility: 'PRIVATE', isFree: true, venueId: venue.id, seatMapVersionId: version.id,
        startsAt: start, endsAt: new Date(start.getTime() + 4 * 3600e3), publishedAt: new Date(),
        ticketTypes: { create: [{ name: 'Seated', quota: 0, maxPerOrder: 4 }] },
      },
      include: { ticketTypes: true },
    });
    const tt = e.ticketTypes[0];
    // EventSeatsService.setMap: one UNSOLD row per seat
    await tx.eventSeat.createMany({ data: seats.map((s) => ({ eventId: e.id, seatKey: s.seatKey, sectionKey: s.sectionKey, rowLabel: s.rowLabel, seatLabel: s.seatLabel, label: s.label, labelMy: s.labelMy })) });
    // EventSeatsService.setAssignments with whole-section rules S and C (300 + 200 = 500)
    const rules = ['S', 'C'].map((sectionKey) => ({ eventId: e.id, sectionKey, rowLabel: null, ticketTypeId: tt.id }));
    await tx.eventSection.createMany({ data: rules });
    await tx.$executeRaw`
      UPDATE event_seats s SET ticket_type_id = r.ticket_type_id FROM event_sections r
      WHERE s.event_id = ${e.id}::uuid AND r.event_id = s.event_id AND r.section_key = s.section_key AND r.row_label IS NULL`;
    await tx.$executeRaw`UPDATE event_seats SET status = 'AVAILABLE'::"SeatStatus" WHERE event_id = ${e.id}::uuid AND ticket_type_id IS NOT NULL`;
    await recount(tx, e.id);
    return e;
  });
  const assigned = await prisma.eventSeat.count({ where: { eventId: ev.id, ticketTypeId: { not: null } } });
  if (assigned !== 500) throw new Error(`expected 500 assigned seats, got ${assigned}`);
  console.log('LOADTEST_SEATED ' + JSON.stringify({ eventId: ev.id, ticketTypeId: ev.ticketTypes[0].id, slug: SEATED_SLUG }));
}

async function seatedCheck() {
  const ev = await prisma.event.findUnique({ where: { slug: SEATED_SLUG }, select: { id: true, ticketTypes: { select: { id: true, sold: true, held: true, quota: true } } } });
  if (!ev) { console.error('no seated event'); process.exit(1); }
  const one = async (q) => Number((await q)[0].n);
  const sold = await one(prisma.$queryRaw`SELECT count(*)::int AS n FROM event_seats WHERE event_id = ${ev.id}::uuid AND status = 'SOLD'`);
  const multi = await one(prisma.$queryRaw`
    SELECT count(*)::int AS n FROM (SELECT seat_key FROM tickets t JOIN ticket_types tt ON tt.id = t.ticket_type_id
      WHERE tt.event_id = ${ev.id}::uuid AND t.status = 'VALID' AND t.seat_key IS NOT NULL GROUP BY seat_key HAVING count(*) > 1) x`);
  const notSold = await one(prisma.$queryRaw`
    SELECT count(*)::int AS n FROM tickets t JOIN ticket_types tt ON tt.id = t.ticket_type_id
    LEFT JOIN event_seats s ON s.event_id = tt.event_id AND s.seat_key = t.seat_key
    WHERE tt.event_id = ${ev.id}::uuid AND t.status IN ('VALID', 'CHECKED_IN') AND t.seat_key IS NOT NULL AND (s.id IS NULL OR s.status <> 'SOLD' OR s.ticket_id IS DISTINCT FROM t.id)`);
  const held = await one(prisma.$queryRaw`SELECT count(*)::int AS n FROM event_seats WHERE event_id = ${ev.id}::uuid AND status = 'CHECKOUT_HOLD'`);
  const tt = ev.ticketTypes[0];
  const out = { soldSeats: sold, seatsWithMultipleValidTickets: multi, ticketsWhoseSeatIsNotSold: notSold, checkoutHoldSeats: held, ticketTypeSold: tt.sold, ticketTypeHeld: tt.held, soldCounterMatches: tt.sold === sold };
  out.ok = sold <= 500 && multi === 0 && notSold === 0 && tt.sold === sold;
  console.log('LOADTEST_SEATED_CHECK ' + JSON.stringify(out));
  if (!out.ok) process.exitCode = 3;
}

// cleanup(): both events and the test users. cleanup(slug): only that event (and, for the free-ticket event, the users, as before).
async function cleanup(only) {
  const evs = await prisma.event.findMany({ where: { slug: only ? only : { in: [SLUG, SEATED_SLUG] } }, select: { id: true, slug: true, createdAt: true, venueId: true, seatMapVersionId: true } });
  const first = evs.reduce((m, e) => (!m || e.createdAt < m ? e.createdAt : m), null);
  const users = only !== SEATED_SLUG && first ? await prisma.user.findMany({ where: { phone: { startsWith: '+95969000' }, createdAt: { gt: first } }, select: { id: true } }) : [];
  const ids = users.map((u) => u.id);
  const steps = [];
  for (const ev of evs) {
    steps.push([`${ev.slug}: checkins`, () => prisma.checkin.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: crew sessions`, () => prisma.crewSession.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: seats`, () => prisma.eventSeat.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: seat rules`, () => prisma.eventSection.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: tickets`, () => prisma.ticket.deleteMany({ where: { ticketType: { eventId: ev.id } } })]);
    steps.push([`${ev.slug}: order items`, () => prisma.orderItem.deleteMany({ where: { order: { eventId: ev.id } } })]);
    steps.push([`${ev.slug}: orders`, () => prisma.order.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: daily stats`, () => prisma.eventDailyStat.deleteMany({ where: { eventId: ev.id } })]);
    steps.push([`${ev.slug}: notifications`, () => prisma.notification.deleteMany({ where: { OR: [{ userId: { in: ids } }, { eventId: ev.id }] } })]);
    steps.push([`${ev.slug}: event`, () => prisma.event.delete({ where: { id: ev.id } })]);
  }
  // The throwaway map (named 'loadtest map'), its versions and the event venue(s), after the events are gone
  if (!only || only === SEATED_SLUG) {
    steps.push(['loadtest map versions', () => prisma.seatMapVersion.deleteMany({ where: { seatMap: { venueName: MAP_NAME }, events: { none: {} } } })]);
    steps.push(['loadtest map', () => prisma.seatMap.deleteMany({ where: { venueName: MAP_NAME, versions: { none: {} } } })]);
    steps.push(['loadtest venues', () => prisma.venue.deleteMany({ where: { name: MAP_NAME, events: { none: {} } } })]);
  }
  if (ids.length) {
    steps.push(['refresh tokens', () => prisma.refreshToken.deleteMany({ where: { userId: { in: ids } } })]);
    steps.push(['identities', () => prisma.userIdentity.deleteMany({ where: { userId: { in: ids } } })]);
    steps.push(['users', () => prisma.user.deleteMany({ where: { id: { in: ids } } })]);
  }
  if (only !== SEATED_SLUG) steps.push(['otp challenges', () => prisma.otpChallenge.deleteMany({ where: { phone: { startsWith: '+95969000' } } })]);
  for (const [name, fn] of steps) {
    try { const r = await fn(); console.log(`deleted ${name}: ${r?.count ?? 1}`); } catch (e) { console.log(`skip ${name}: ${e.message.split('\n').pop()}`); }
  }
}

const mode = process.argv[2] ?? process.env.MODE;
(mode === 'cleanup' ? cleanup() : mode === 'seated' ? seedSeated() : mode === 'seated-check' ? seatedCheck() : seed()).catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
