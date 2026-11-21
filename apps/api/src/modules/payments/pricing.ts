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

