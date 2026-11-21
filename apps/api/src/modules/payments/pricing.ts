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
