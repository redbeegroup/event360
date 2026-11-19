import { commission, pickRule, FeeRuleLike } from './fee';

const r = (o: Partial<FeeRuleLike>): FeeRuleLike => ({ scope: 'GLOBAL', scopeId: null, percentBp: 500, fixedMmk: 0n, minMmk: null, maxMmk: null, isActive: true, ...o });

describe('fees', () => {
  it('percent with rounding, min, max and cap at subtotal', () => {
    expect(commission(r({}), 10_000n)).toBe(500n);
    expect(commission(r({ percentBp: 333 }), 1_000n)).toBe(33n);
    expect(commission(r({ percentBp: 250 }), 1_010n)).toBe(25n); // 25.25
    expect(commission(r({ minMmk: 1_000n }), 5_000n)).toBe(1_000n);
    expect(commission(r({ maxMmk: 2_000n }), 1_000_000n)).toBe(2_000n);
    expect(commission(r({ fixedMmk: 300n }), 10_000n)).toBe(800n);
    expect(commission(r({ minMmk: 9_000n }), 5_000n)).toBe(5_000n);
    expect(commission(null, 5_000n)).toBe(0n);
    expect(commission(r({}), 0n)).toBe(0n);
  });
  it('most specific active rule wins', () => {
    const rules = [
      r({ percentBp: 500 }),
      r({ scope: 'CATEGORY', scopeId: 'cat-parent', percentBp: 400 }),
      r({ scope: 'ORGANIZATION', scopeId: 'org', percentBp: 300 }),
      r({ scope: 'EVENT', scopeId: 'ev', percentBp: 200, isActive: false }),
    ];
    const ctx = { eventId: 'ev', organizationId: 'org', categoryId: 'cat', parentCategoryId: 'cat-parent' };
    expect(pickRule(rules, ctx)?.percentBp).toBe(300);
    expect(pickRule(rules, { ...ctx, organizationId: 'x' })?.percentBp).toBe(400);
    expect(pickRule(rules, { ...ctx, organizationId: 'x', parentCategoryId: null })?.percentBp).toBe(500);
    expect(pickRule([], ctx)).toBeNull();
  });
});
