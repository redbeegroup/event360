import { PrismaClient } from '@prisma/client';
import { CATEGORY_SEED } from './modules/catalog/category-seed';

const prisma = new PrismaClient();

async function main() {
  for (const [i, parent] of CATEGORY_SEED.entries()) {
    const p = await prisma.category.upsert({
      where: { slug: parent.slug },
      update: { nameEn: parent.nameEn, iconKey: parent.iconKey, sortOrder: i },
      create: { slug: parent.slug, nameEn: parent.nameEn, iconKey: parent.iconKey, sortOrder: i },
    });
    for (const [j, child] of parent.children.entries()) {
      await prisma.category.upsert({
        where: { slug: child.slug },
        update: { nameEn: child.nameEn, parentId: p.id, sortOrder: j },
        create: { slug: child.slug, nameEn: child.nameEn, parentId: p.id, sortOrder: j },
      });
    }
  }

  // Default commission: 5% organizer-absorbed (admin-editable)
  const existing = await prisma.feeRule.findFirst({ where: { scope: 'GLOBAL' } });
  if (!existing) {
    await prisma.feeRule.create({ data: { scope: 'GLOBAL', percentBp: 500, fixedMmk: 0n } });
  }

  const placements = [
    { code: 'HOME_HERO', name: 'Home hero carousel', slotsPerDay: 5, pricePerDayMmk: 100_000n },
    { code: 'HOME_FEATURED_ROW', name: 'Home featured row', slotsPerDay: 10, pricePerDayMmk: 50_000n },
    { code: 'CATEGORY_TOP', name: 'Top of category', slotsPerDay: 3, pricePerDayMmk: 30_000n },
    { code: 'SEARCH_BOOST', name: 'Search boost', slotsPerDay: 3, pricePerDayMmk: 20_000n },
    { code: 'CITY_TOP', name: 'Top of city', slotsPerDay: 3, pricePerDayMmk: 30_000n },
    { code: 'PUSH_BLAST', name: 'Push notification blast', slotsPerDay: 1, pricePerDayMmk: 200_000n },
    { code: 'ORGANIZER_SPOTLIGHT', name: 'Organizer spotlight', slotsPerDay: 2, pricePerDayMmk: 40_000n },
  ];
  for (const pl of placements) {
    await prisma.promoPlacement.upsert({ where: { code: pl.code }, update: {}, create: pl });
  }
  console.log('Seed complete');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
