import { hashPassword, makeSlug, verifyPassword } from './util';

describe('makeSlug', () => {
  it('builds a URL-safe slug with a random suffix', () => {
    expect(makeSlug('Yangon Food & Beverage Fair 2027!')).toMatch(/^yangon-food-beverage-fair-2027-[0-9a-f]{6}$/);
    expect(makeSlug('ရန်ကုန်ပွဲ')).toMatch(/^event-[0-9a-f]{6}$/);
    expect(makeSlug('x')).not.toBe(makeSlug('x'));
  });
});

describe('password hashing', () => {
  it('verifies the right password only', async () => {
    const h = await hashPassword('correct horse battery');
    expect(h).toMatch(/^scrypt\$/);
    await expect(verifyPassword('correct horse battery', h)).resolves.toBe(true);
    await expect(verifyPassword('wrong', h)).resolves.toBe(false);
    await expect(verifyPassword('x', null)).resolves.toBe(false);
  });
});
