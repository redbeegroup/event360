// Load test data on dev: a PRIVATE event (not listed anywhere) with two free ticket types and a crew code.
// MODE=cleanup removes the event and every user the test created (phones +95969000xxxx, created after the event).
const { PrismaClient } = require('@prisma/client');
const { createHash, randomBytes } = require('crypto');
if (!/[?&]schema=dev(&|$)/.test(process.env.DATABASE_URL ?? '')) {
  console.error('Refusing to run: the load-test data script is for the dev schema only.');
  process.exit(2);
}
const prisma = new PrismaClient();
const SLUG = 'loadtest-event';
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

async function seed() {
  await cleanup();
  const org = await prisma.organization.findFirst({ where: { events: { some: { slug: { startsWith: 'sample-' } } } }, include: { members: true }, orderBy: { createdAt: 'asc' } });
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

async function cleanup() {
  const ev = await prisma.event.findUnique({ where: { slug: SLUG }, select: { id: true, createdAt: true } });
  const users = ev ? await prisma.user.findMany({ where: { phone: { startsWith: '+95969000' }, createdAt: { gt: ev.createdAt } }, select: { id: true } }) : [];
  const ids = users.map((u) => u.id);
  const steps = [];
  if (ev) {
    steps.push(['checkins', () => prisma.checkin.deleteMany({ where: { eventId: ev.id } })]);
    steps.push(['crew sessions', () => prisma.crewSession.deleteMany({ where: { eventId: ev.id } })]);
    steps.push(['tickets', () => prisma.ticket.deleteMany({ where: { ticketType: { eventId: ev.id } } })]);
    steps.push(['order items', () => prisma.orderItem.deleteMany({ where: { order: { eventId: ev.id } } })]);
    steps.push(['orders', () => prisma.order.deleteMany({ where: { eventId: ev.id } })]);
    steps.push(['daily stats', () => prisma.eventDailyStat.deleteMany({ where: { eventId: ev.id } })]);
    steps.push(['notifications', () => prisma.notification.deleteMany({ where: { OR: [{ userId: { in: ids } }, { eventId: ev.id }] } })]);
    steps.push(['event', () => prisma.event.delete({ where: { id: ev.id } })]);
  }
  if (ids.length) {
    steps.push(['refresh tokens', () => prisma.refreshToken.deleteMany({ where: { userId: { in: ids } } })]);
    steps.push(['identities', () => prisma.userIdentity.deleteMany({ where: { userId: { in: ids } } })]);
    steps.push(['users', () => prisma.user.deleteMany({ where: { id: { in: ids } } })]);
  }
  steps.push(['otp challenges', () => prisma.otpChallenge.deleteMany({ where: { phone: { startsWith: '+95969000' } } })]);
  for (const [name, fn] of steps) {
    try { const r = await fn(); console.log(`deleted ${name}: ${r?.count ?? 1}`); } catch (e) { console.log(`skip ${name}: ${e.message.split('\n').pop()}`); }
  }
}

(process.argv[2] === 'cleanup' || process.env.MODE === 'cleanup' ? cleanup() : seed()).catch((e) => { console.error(e); process.exit(1); }).finally(() => prisma.$disconnect());
