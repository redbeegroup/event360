import type { PrismaClient } from '@prisma/client';

/**
 * Normalises Myanmar mobile numbers to E.164 (+959XXXXXXX..).
 * Accepts: 09xxxxxxxxx, 959xxxxxxxxx, +959xxxxxxxxx, with spaces/dashes.
 * Returns null when the input is not a plausible Myanmar mobile number.
 */
export function normalizeMyanmarPhone(input: string): string | null {
  const digits = input.replace(/[\s\-()]/g, '');
  let national: string;
  if (/^\+959\d+$/.test(digits)) national = digits.slice(4);
  else if (/^959\d+$/.test(digits)) national = digits.slice(3);
  else if (/^09\d+$/.test(digits)) national = digits.slice(2);
  else return null;
  // Myanmar mobile subscriber numbers are 7–10 digits after the leading 9.
  if (national.length < 7 || national.length > 10) return null;
  return `+959${national}`;
}

/** Finds or creates the account for a normalised phone number (shared by ticket transfers and guest tickets). */
export function upsertUserByPhone(db: { user: Pick<PrismaClient['user'], 'upsert'> }, phone: string) {
  return db.user.upsert({
    where: { phone },
    update: {},
    create: { phone, identities: { create: { provider: 'PHONE', subject: phone } } },
  });
}
