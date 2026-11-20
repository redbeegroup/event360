import { applyPromo, PromoLike } from './promo';

const p = (o: Partial<PromoLike> = {}): PromoLike => ({ kind: 'PERCENT', value: 1000, maxUses: null, used: 0, startsAt: null, endsAt: null, ticketTypeIds: [], isActive: true, ...o });
const lines = [
  { ticketTypeId: 'std', unitPriceMmk: 10_000n, quantity: 2 },
  { ticketTypeId: 'vip', unitPriceMmk: 35_000n, quantity: 1 },
  { ticketTypeId: 'kid', unitPriceMmk: 0n, quantity: 1 },
];

describe('promo codes', () => {
  it('percent and fixed discounts, capped at the eligible amount', () => {
    expect(applyPromo(p(), lines)).toEqual({ ok: true, discountMmk: 5_500n });
    expect(applyPromo(p({ value: 10_000 }), lines)).toEqual({ ok: true, discountMmk: 55_000n });
    expect(applyPromo(p({ kind: 'FIXED', value: 3_000 }), lines)).toEqual({ ok: true, discountMmk: 3_000n });
    expect(applyPromo(p({ kind: 'FIXED', value: 99_000 }), lines)).toEqual({ ok: true, discountMmk: 55_000n });
  });
  it('limited to chosen ticket types', () => {
    expect(applyPromo(p({ ticketTypeIds: ['vip'] }), lines)).toEqual({ ok: true, discountMmk: 3_500n });
    expect(applyPromo(p({ ticketTypeIds: ['kid'] }), lines)).toMatchObject({ ok: false });
  });
  it('rejects inactive, early, expired and used-up codes', () => {
    const now = new Date('2026-11-20T00:00:00Z');
    expect(applyPromo(null, lines)).toMatchObject({ ok: false });
    expect(applyPromo(p({ isActive: false }), lines)).toMatchObject({ ok: false });
    expect(applyPromo(p({ startsAt: new Date('2026-12-01') }), lines, now)).toEqual({ ok: false, reason: 'This code is not active yet' });
    expect(applyPromo(p({ endsAt: new Date('2026-11-01') }), lines, now)).toEqual({ ok: false, reason: 'This code has expired' });
    expect(applyPromo(p({ maxUses: 5, used: 5 }), lines)).toEqual({ ok: false, reason: 'This code has been used up' });
  });
});
