import { randomBytes } from 'crypto';
import { SecretBox } from './secret-box';

describe('SecretBox', () => {
  const key = randomBytes(32).toString('base64');

  it('round-trips and never stores plain text', () => {
    const box = new SecretBox(key);
    const sealed = box.seal('my-api-secret');
    expect(sealed).toMatch(/^v1:/);
    expect(sealed).not.toContain('my-api-secret');
    expect(box.open(sealed)).toBe('my-api-secret');
    expect(box.seal('x')).not.toBe(box.seal('x')); // random IV
  });

  it('fails with the wrong key or tampered data', () => {
    const sealed = new SecretBox(key).seal('secret');
    expect(() => new SecretBox(randomBytes(32).toString('base64')).open(sealed)).toThrow();
    const tampered = sealed.slice(0, -4) + (sealed.endsWith('AAAA') ? 'BBBB' : 'AAAA');
    expect(() => new SecretBox(key).open(tampered)).toThrow();
  });

  it('rejects a missing or short key', () => {
    expect(() => new SecretBox(undefined)).toThrow();
    expect(() => new SecretBox(randomBytes(16).toString('base64'))).toThrow();
  });
});
