import { CATEGORY_SEED } from './category-seed';

describe('CATEGORY_SEED', () => {
  it('matches the agreed category tree', () => {
    expect(CATEGORY_SEED.map((c) => [c.nameEn, c.children.length])).toEqual([
      ['Lifestyle & Social', 4],
      ['Entertainment & Culture', 3],
      ['Conference', 3],
      ['Education & Business', 2],
    ]);
  });

  it('has globally unique slugs', () => {
    const slugs = CATEGORY_SEED.flatMap((c) => [c.slug, ...c.children.map((x) => x.slug)]);
    expect(new Set(slugs).size).toBe(slugs.length);
  });
});
