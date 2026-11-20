import { randomBytes, scrypt as _scrypt, timingSafeEqual } from 'crypto';
import { promisify } from 'util';

/** URL slug from an English title plus a short random suffix (titles need not be unique). */
export function makeSlug(title: string): string {
  const base = title
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
  return `${base || 'event'}-${randomBytes(3).toString('hex')}`;
}

const scrypt = promisify(_scrypt) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;

/** `scrypt$<salt b64>$<hash b64>` — Node built-in, no native deps. */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('base64')}$${hash.toString('base64')}`;
}

// Checked when there is no stored hash, so a missing account takes as long as a wrong password
const DUMMY_HASH = 'scrypt$' + Buffer.alloc(16).toString('base64') + '$' + Buffer.alloc(64).toString('base64');

export async function verifyPassword(password: string, stored: string | null | undefined): Promise<boolean> {
  if (!stored?.startsWith('scrypt$')) {
    if (stored !== DUMMY_HASH) await verifyPassword(password, DUMMY_HASH);
    return false;
  }
  const [, saltB64, hashB64] = stored.split('$');
  const expected = Buffer.from(hashB64, 'base64');
  const actual = await scrypt(password, Buffer.from(saltB64, 'base64'), expected.length);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/** JSON-safe conversion of Prisma BigInt money fields. */
export function mmk(v: bigint | number | null | undefined): number {
  return v == null ? 0 : Number(v);
}
