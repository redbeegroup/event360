// Dev only: adds organizer-growth demo data to the existing sample event sample-seated-gala (run sample-seated.js first):
//   - a price step on the VIP ticket type: 45,000 MMK now, 55,000 MMK from 2026-12-15 (Yangon midnight)
//   - one group-discount tier: 5 or more paid tickets get 10% off
// It uses the same services as the organizer API endpoints and does nothing else. Re-running is safe: both calls replace the whole
// list (price steps already in effect are kept by the service). Run it like sample-seated.js (docs/runbook.md §10).
process.env.APP_ROLE = 'script';
if (!/[?&]schema=dev(&|$)/.test(process.env.DATABASE_URL ?? '')) { console.error('dev schema only'); process.exit(2); }
require('reflect-metadata');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('/app/dist/app.module');
const { PrismaService } = require('/app/dist/modules/prisma/prisma.service');
const { EventsService } = require('/app/dist/modules/events/events.service');
const { OrgToolsService } = require('/app/dist/modules/orgtools/orgtools.module');

const SLUG = 'sample-seated-gala';

(async () => {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
  const prisma = app.get(PrismaService);
  const events = app.get(EventsService);
  const tools = app.get(OrgToolsService);
  try {
    const ev = await prisma.event.findUnique({ where: { slug: SLUG }, include: { ticketTypes: true } });
    if (!ev) throw new Error(`${SLUG} not found; run sample-seated.js first`);
    const vip = ev.ticketTypes.find((t) => t.name === 'VIP');
    if (!vip) throw new Error('VIP ticket type not found on ' + SLUG);
    const steps = await events.setPriceSteps(ev.organizationId, ev.id, vip.id, [{ startsAt: '2026-12-15T00:00:00+06:30', priceMmk: 55000 }]);
    const tiers = await tools.setGroupDiscounts(ev.organizationId, ev.id, [{ minQuantity: 5, percentBp: 1000 }]);
    console.log('SAMPLE ' + JSON.stringify({ eventId: ev.id, slug: SLUG, vipPriceSteps: steps.steps, groupTiers: tiers.tiers }));
  } finally {
    await app.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
