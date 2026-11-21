import { currentPrice, nextStep } from './pricing';

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
