import { mmk } from '../../common/util';

export type PriceStep = { startsAt: Date; priceMmk: bigint };

/** The price of the latest step that has started, or the base price before the first one. */
export function currentPrice(base: bigint, steps: readonly PriceStep[], now: Date): bigint {
  let best: PriceStep | null = null;
  for (const s of steps) if (s.startsAt <= now && (!best || s.startsAt > best.startsAt)) best = s;
  return best ? best.priceMmk : base;
}

/** The first step that has not started yet. */
export function nextStep(steps: readonly PriceStep[], now: Date): PriceStep | null {
  let best: PriceStep | null = null;
  for (const s of steps) if (s.startsAt > now && (!best || s.startsAt < best.startsAt)) best = s;
  return best;
}

/** Same price fields as the public ticket types: current price, base price and the next step. */
export function priceView(t: { priceMmk: bigint; priceSteps: PriceStep[] }, now: Date) {
  const next = nextStep(t.priceSteps, now);
  return {
    priceMmk: mmk(currentPrice(t.priceMmk, t.priceSteps, now)),
    basePriceMmk: mmk(t.priceMmk),
    nextPrice: next ? { priceMmk: mmk(next.priceMmk), startsAt: next.startsAt } : null,
  };
}


export type GroupTier = { minQuantity: number; percentBp: number };

/** The percentage (basis points) of the best tier reached by `paidQty` paid-type tickets; 0 when none is. */
export function bestGroupTier(tiers: readonly GroupTier[], paidQty: number): number {
  let best = 0;
  for (const t of tiers) if (paidQty >= t.minQuantity && t.percentBp > best) best = t.percentBp;
  return best;
}

export type DiscountChoice = { source: 'GROUP' | 'PROMO' | null; discountMmk: bigint; groupBp: number | null; promoApplied: boolean };

/**
 * Group discount vs promo code: the larger one applies and the other is ignored. A tie goes to the group discount,
 * so the promo is not applied and its use is not taken. `promoMmk` is null when no valid code was given.
 */
export function chooseDiscount(lines: readonly { unitPriceMmk: bigint; quantity: number }[], tiers: readonly GroupTier[], promoMmk: bigint | null): DiscountChoice {
  const paid = lines.filter((l) => l.unitPriceMmk > 0n);
  const bp = bestGroupTier(tiers, paid.reduce((n, l) => n + l.quantity, 0));
  const base = paid.reduce((s, l) => s + l.unitPriceMmk * BigInt(l.quantity), 0n);
  const group = bp > 0 ? (base * BigInt(bp) + 5000n) / 10000n : 0n;
  if (group > 0n && group >= (promoMmk ?? 0n)) return { source: 'GROUP', discountMmk: group, groupBp: bp, promoApplied: false };
  if (promoMmk != null) return { source: 'PROMO', discountMmk: promoMmk, groupBp: null, promoApplied: true };
  return { source: null, discountMmk: 0n, groupBp: null, promoApplied: false };
}
