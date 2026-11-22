import { PrismaClient } from '@prisma/client';
import { seedBaseData } from '../src/seed';

/**
 * Runs once before the suites. The e2e specs read the seeded category tree (and the default fee rule and promo
 * placements), so a database that was just created or migrated, or one whose reference rows were removed, would
 * fail them in unrelated places. The seed is upserts only, so this is a no-op on a seeded database and adds nothing
 * for CI, which seeds before the tests anyway. Skipped, like the suites, when DATABASE_URL is not set.
 */
export default async function globalSetup(): Promise<void> {
  if (!process.env.DATABASE_URL) return;
  const prisma = new PrismaClient();
  try {
    await seedBaseData(prisma);
  } catch (e) {
    // Unit specs need no database: report it and let the suites that do need one fail on their own
    console.warn(`test seed skipped: ${(e as Error).message.split('\n')[0]}`);
  } finally {
    await prisma.$disconnect();
  }
}
