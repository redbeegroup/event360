import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

/**
 * AES-256-GCM for secrets stored in the database (e.g. SMS API credentials).
 * Format: "v1:" + base64(iv[12] | tag[16] | ciphertext). The key is SETTINGS_KEY (base64, 32 bytes).
 */
export class SecretBox {
  private readonly key: Buffer;

  constructor(keyB64: string | undefined) {
    const key = keyB64 ? Buffer.from(keyB64, 'base64') : Buffer.alloc(0);
    if (key.length !== 32) throw new Error('SETTINGS_KEY must be 32 bytes, base64-encoded');
    this.key = key;
  }

  seal(plain: string): string {
    const iv = randomBytes(12);
    const c = createCipheriv('aes-256-gcm', this.key, iv);
    const body = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return `v1:${Buffer.concat([iv, c.getAuthTag(), body]).toString('base64')}`;
  }

  open(sealed: string): string {
    if (!sealed.startsWith('v1:')) throw new Error('Unknown secret format');
    const raw = Buffer.from(sealed.slice(3), 'base64');
    const d = createDecipheriv('aes-256-gcm', this.key, raw.subarray(0, 12));
    d.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([d.update(raw.subarray(28)), d.final()]).toString('utf8');
  }
}
