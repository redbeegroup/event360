import { bestGroupTier, chooseDiscount, currentPrice, nextStep } from './pricing';

const d = (s: string) => new Date(s);
const steps = [
  { startsAt: d('2026-12-10T00:00:00Z'), priceMmk: 15_000n },
  { startsAt: d('2026-12-01T00:00:00Z'), priceMmk: 12_000n },
];

describe('timed prices', () => {
  it('currentPrice with no steps returns the base', () => {
    expect(currentPrice(10_000n, [], d('2026-12-05T00:00:00Z'))).toBe(10_000n);
  });
  it('just before a step returns the base', () => {
    expect(currentPrice(10_000n, steps, d('2026-11-30T23:59:59.999Z'))).toBe(10_000n);
  });
  it('at the step returns the step price', () => {
    expect(currentPrice(10_000n, steps, d('2026-12-01T00:00:00Z'))).toBe(12_000n);
  });
  it('after two steps returns the latest', () => {
    expect(currentPrice(10_000n, steps, d('2026-12-20T00:00:00Z'))).toBe(15_000n);
  });
  it('nextStep returns the first future step', () => {
    expect(nextStep(steps, d('2026-11-01T00:00:00Z'))).toEqual(steps[1]);
    expect(nextStep(steps, d('2026-12-01T00:00:00Z'))).toEqual(steps[0]);
    expect(nextStep(steps, d('2026-12-10T00:00:00Z'))).toBeNull();
  });
});

describe('bestGroupTier', () => {
  const tiers = [
    { minQuantity: 10, percentBp: 1500 },
    { minQuantity: 5, percentBp: 1000 },
  ];
  it('no tiers gives 0', () => expect(bestGroupTier([], 50)).toBe(0));
  it('below the lowest tier gives 0', () => expect(bestGroupTier(tiers, 4)).toBe(0));
  it('exactly at a tier gives that tier', () => {
    expect(bestGroupTier(tiers, 5)).toBe(1000);
    expect(bestGroupTier(tiers, 10)).toBe(1500);
  });
  it('between tiers gives the lower one reached', () => expect(bestGroupTier(tiers, 9)).toBe(1000));
});

describe('chooseDiscount', () => {
  const tiers = [{ minQuantity: 5, percentBp: 1000 }];
  const lines = [{ unitPriceMmk: 10_000n, quantity: 3 }, { unitPriceMmk: 0n, quantity: 2 }];
  it('free tickets do not count toward a tier', () => expect(chooseDiscount(lines, tiers, null).source).toBeNull());
  it('a tie goes to the group discount', () => {
    const l = [{ unitPriceMmk: 10_000n, quantity: 5 }];
    expect(chooseDiscount(l, tiers, 5_000n)).toMatchObject({ source: 'GROUP', discountMmk: 5_000n, groupBp: 1000, promoApplied: false });
  });
  it('a larger promo wins', () => {
    const l = [{ unitPriceMmk: 10_000n, quantity: 5 }];
    expect(chooseDiscount(l, tiers, 5_001n)).toMatchObject({ source: 'PROMO', discountMmk: 5_001n, groupBp: null, promoApplied: true });
  });
});

describe('group discount rounding', () => {
  const tiers = [{ minQuantity: 5, percentBp: 1000 }, { minQuantity: 10, percentBp: 1500 }];
  it('rounds half up: 16,665 at 10% is 1,666.5 → 1,667', () => {
    expect(chooseDiscount([{ unitPriceMmk: 3_333n, quantity: 5 }], tiers, null)).toMatchObject({ discountMmk: 1_667n, groupBp: 1000 });
  });
  it('rounds a fraction below one half down: 33,330 at 15% is 4,999.5 → 5,000; 3,331 × 10 at 15% is 4,996.5 → 4,997', () => {
    expect(chooseDiscount([{ unitPriceMmk: 3_333n, quantity: 10 }], tiers, null).discountMmk).toBe(5_000n);
    expect(chooseDiscount([{ unitPriceMmk: 3_331n, quantity: 10 }], tiers, null).discountMmk).toBe(4_997n);
  });
  it('rounds below a half down: 3,334 × 5 at 10% is 1,667 exactly; 3,332 × 5 at 10% is 1,666', () => {
    expect(chooseDiscount([{ unitPriceMmk: 3_334n, quantity: 5 }], tiers, null).discountMmk).toBe(1_667n);
    expect(chooseDiscount([{ unitPriceMmk: 3_332n, quantity: 5 }], tiers, null).discountMmk).toBe(1_666n);
  });
});
