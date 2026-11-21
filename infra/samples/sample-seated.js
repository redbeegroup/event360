// Dev only: a demo venue seat map ("Shwe Pyi Theatre", fictional, 490 seats) and one public seated sample event
// (slug sample-seated-gala). Run as a one-off Job with the API image and event360-secrets (see docs/runbook.md, scripts section).
// Re-running recreates both, as long as the event has no orders and no other event uses the map.
process.env.APP_ROLE = 'script';
if (!/[?&]schema=dev(&|$)/.test(process.env.DATABASE_URL ?? '')) { console.error('dev schema only'); process.exit(2); }
require('reflect-metadata');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('/app/dist/app.module');
const { PrismaService } = require('/app/dist/modules/prisma/prisma.service');
const { SeatMapsService } = require('/app/dist/modules/seating/seat-maps.service');
const { EventSeatsService } = require('/app/dist/modules/seating/event-seats.service');
const { GuestsService } = require('/app/dist/modules/seating/guests.service');
const { validateLayout, expandSeats } = require('/app/dist/modules/seating/layout');

const SLUG = 'sample-seated-gala';
const VENUE = 'Shwe Pyi Theatre';
const MY = { ST: 'အောက်ထပ်', CI: 'အပေါ်ထပ်', BL: 'ဘောက်စ် ဘယ်', BR: 'ဘောက်စ် ညာ' };

function centredRow(label, count, widest, aisleAfter = [], attrs = {}) {
  const pad = (widest - count) / 2;
  const seats = [];
  for (let n = 1; n <= count; n++) {
    const s = { n };
    if (n === 1 && pad) s.gapBefore = pad;
    if (aisleAfter.includes(n - 1)) s.gapBefore = (s.gapBefore ?? 0) + 1;
    if (attrs[n]) s.attrs = attrs[n];
    seats.push(s);
  }
  return { label, seats };
}

function layout() {
  // Stalls: rows A–L, 18→29 seats, centre aisle.
  const stalls = [];
  'ABCDEFGHIJKL'.split('').forEach((r, i) => {
    const count = 18 + i;
    const attrs = {};
    if (r === 'A') { attrs[1] = ['RESTRICTED_VIEW']; attrs[count] = ['RESTRICTED_VIEW']; }
    if (r === 'L') { for (const n of [1, 2, count - 1, count]) attrs[n] = ['WHEELCHAIR']; }
    stalls.push(centredRow(r, count, 29, [Math.floor(count / 2)], attrs));
  });
  // Circle: rows M–R, 32 seats, two aisles.
  const circle = 'MNOPQR'.split('').map((r) => centredRow(r, 32, 32, [8, 24]));
  const box = (prefix) => [1, 2].map((r) => ({ label: `${prefix}${r}`, seats: [1, 2, 3, 4].map((n) => ({ n })) }));
  return {
    width: 1040,
    height: 760,
    stage: { x: 320, y: 30, w: 400, h: 50, label: 'Stage' },
    sections: [
      { key: 'ST', name: 'Stalls', nameMy: MY.ST, kind: 'SEATED', x: 520 - 15 * 24, y: 130, curve: 0.12, rows: stalls },
      { key: 'CI', name: 'Circle', nameMy: MY.CI, kind: 'SEATED', x: 520 - 17 * 24, y: 520, curve: 0.1, rows: circle },
      { key: 'BL', name: 'Box Left', nameMy: MY.BL, kind: 'SEATED', x: 100, y: 170, rotation: 90, rows: box('L') },
      { key: 'BR', name: 'Box Right', nameMy: MY.BR, kind: 'SEATED', x: 964, y: 170, rotation: 90, rows: box('R') },
    ],
  };
}

(async () => {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
  const prisma = app.get(PrismaService);
  const maps = app.get(SeatMapsService);
  const seats = app.get(EventSeatsService);
  const guests = app.get(GuestsService);
  try {
    const L = layout();
    const v = validateLayout(L);
    if (!v.ok) throw new Error('Layout problems: ' + v.problems.join('; '));
    console.log('seats in layout:', expandSeats(L).length);

    const admin = await prisma.user.findFirst({ where: { platformRoles: { has: 'PLATFORM_ADMIN' } }, select: { id: true } });
    {
      const old0 = await prisma.event.findUnique({ where: { slug: SLUG }, select: { id: true, _count: { select: { orders: true } } } });
      if (old0 && old0._count.orders === 0) { await prisma.eventSeat.deleteMany({ where: { eventId: old0.id } }); await prisma.event.delete({ where: { id: old0.id } }); }
      const m0 = await prisma.seatMap.findFirst({ where: { venueName: VENUE } });
      if (m0 && !(await prisma.event.count({ where: { seatMapVersion: { seatMapId: m0.id } } }))) { await prisma.seatMapVersion.deleteMany({ where: { seatMapId: m0.id } }); await prisma.seatMap.delete({ where: { id: m0.id } }); console.log('reset map'); }
    }
    let map = await prisma.seatMap.findFirst({ where: { venueName: VENUE } });
    if (!map) {
      map = await maps.create({ venueName: VENUE, venueNameMy: 'ရွှေပြည် ပြဇာတ်ရုံ', city: 'Yangon', address: 'Sample address, Kamaryut, Yangon (demo venue)' });
      await maps.saveDraft(map.id, L, admin.id);
      await maps.publish(map.id, admin.id);
      console.log('created and published map', map.id);
    } else console.log('reusing map', map.id);
    const version = await prisma.seatMapVersion.findFirst({ where: { seatMapId: map.id, publishedAt: { not: null } }, orderBy: { version: 'desc' } });

    const old = await prisma.event.findUnique({ where: { slug: SLUG }, select: { id: true, _count: { select: { orders: true } } } });
    if (old) {
      if (old._count.orders > 0) { console.log('sample event already has orders; leaving it alone', old.id); return; }
      await prisma.eventSeat.deleteMany({ where: { eventId: old.id } });
      await prisma.event.delete({ where: { id: old.id } });
      console.log('removed previous sample event');
    }
    const tmpl = await prisma.event.findUnique({ where: { slug: 'sample-golden-harp-musical' }, select: { organizationId: true, categoryId: true, coverImageUrl: true } });
    const start = new Date('2026-12-31T13:00:00.000Z'); // 19:30 Yangon
    const ev = await prisma.event.create({
      data: {
        organizationId: tmpl.organizationId, categoryId: tmpl.categoryId, slug: SLUG,
        title: 'New Year Gala Night (reserved seating demo)',
        titleMy: 'နှစ်သစ်ကူး ဂါလာညချမ်း (ထိုင်ခုံ ကြိုတင်ရွေးချယ်ခြင်း နမူနာ)',
        description: 'Demo event for reserved seating on dev. Pick your exact seats in the Stalls, Circle or the side boxes. The venue and performers are fictional.',
        descriptionMy: 'Dev ပေါ်ရှိ ထိုင်ခုံရွေးချယ်မှု နမူနာ ပွဲဖြစ်ပါသည်။ ပြဇာတ်ရုံနှင့် ဖျော်ဖြေသူများသည် စိတ်ကူးယဉ်ဖြစ်ပါသည်။',
        status: 'DRAFT', format: 'IN_PERSON', visibility: 'PUBLIC', isFree: false,
        coverImageUrl: tmpl.coverImageUrl,
        startsAt: start, endsAt: new Date(start.getTime() + 3 * 3600e3),
        ticketTypes: { create: [
          { name: 'VIP', nameMy: 'VIP', priceMmk: 45000n, quota: 0, maxPerOrder: 6, color: '#c2410c' },
          { name: 'Stalls', nameMy: 'အောက်ထပ်', priceMmk: 25000n, quota: 0, maxPerOrder: 8, color: '#2563eb' },
          { name: 'Circle', nameMy: 'အပေါ်ထပ်', priceMmk: 15000n, quota: 0, maxPerOrder: 8, color: '#16a34a' },
        ] },
      },
      include: { ticketTypes: true },
    });
    const tt = Object.fromEntries(ev.ticketTypes.map((t) => [t.name, t.id]));
    await seats.setMap(ev.organizationId, ev.id, version.id, true);
    const rules = [
      { sectionKey: 'ST', ticketTypeId: tt.Stalls },
      ...['A', 'B', 'C'].map((r) => ({ sectionKey: 'ST', rowLabel: r, ticketTypeId: tt.VIP })),
      { sectionKey: 'BL', ticketTypeId: tt.VIP },
      { sectionKey: 'BR', ticketTypeId: tt.VIP },
      { sectionKey: 'CI', ticketTypeId: tt.Circle },
    ];
    await seats.setAssignments(ev.organizationId, ev.id, rules);
    // Six centre seats in row C held for guests.
    await guests.hold(ev.organizationId, ev.id, ['ST:C:9', 'ST:C:10', 'ST:C:11', 'ST:C:12', 'ST:C:13', 'ST:C:14'], 'Sponsor');
    await prisma.event.update({ where: { id: ev.id }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
    const counts = await prisma.ticketType.findMany({ where: { eventId: ev.id }, select: { name: true, quota: true, sold: true, held: true } });
    const byStatus = await prisma.eventSeat.groupBy({ by: ['status'], where: { eventId: ev.id }, _count: true });
    console.log('SAMPLE ' + JSON.stringify({ eventId: ev.id, slug: SLUG, mapId: map.id, version: version.version, counts, byStatus: byStatus.map((b) => [b.status, b._count]) }));
  } finally {
    await app.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
