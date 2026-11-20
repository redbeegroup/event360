/** Promo code rules (pure, unit-tested). Discounts apply to paid orders only. */
export interface PromoLike {
  kind: 'PERCENT' | 'FIXED';
  value: number; // PERCENT: basis points (1000 = 10%); FIXED: MMK off the order
  maxUses: number | null;
  used: number;
  startsAt: Date | null;
  endsAt: Date | null;
  ticketTypeIds: string[]; // empty = all
  isActive: boolean;
}

export interface Line {
  ticketTypeId: string;
  unitPriceMmk: bigint;
  quantity: number;
}

export type PromoResult = { ok: true; discountMmk: bigint } | { ok: false; reason: string };

export const normalizeCode = (c: string) => c.trim().toUpperCase();
export const CODE_RE = /^[A-Z0-9_-]{3,24}$/;

export function applyPromo(p: PromoLike | null, lines: Line[], now = new Date()): PromoResult {
  if (!p || !p.isActive) return { ok: false, reason: 'This code is not valid' };
  if (p.startsAt && p.startsAt > now) return { ok: false, reason: 'This code is not active yet' };
  if (p.endsAt && p.endsAt < now) return { ok: false, reason: 'This code has expired' };
  if (p.maxUses != null && p.used >= p.maxUses) return { ok: false, reason: 'This code has been used up' };
  const eligible = lines.filter((l) => l.unitPriceMmk > 0n && (!p.ticketTypeIds.length || p.ticketTypeIds.includes(l.ticketTypeId)));
  const base = eligible.reduce((s, l) => s + l.unitPriceMmk * BigInt(l.quantity), 0n);
  if (base <= 0n) return { ok: false, reason: 'This code does not apply to these tickets' };
  let d = p.kind === 'PERCENT' ? (base * BigInt(p.value) + 5000n) / 10000n : BigInt(p.value);
  if (d > base) d = base;
  if (d <= 0n) return { ok: false, reason: 'This code is not valid' };
  return { ok: true, discountMmk: d };
}
