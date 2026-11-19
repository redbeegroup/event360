/** Platform commission (organizer absorbs it): the most specific active rule wins (EVENT > ORGANIZATION > CATEGORY > GLOBAL). */
export interface FeeRuleLike {
  scope: 'GLOBAL' | 'CATEGORY' | 'ORGANIZATION' | 'EVENT';
  scopeId: string | null;
  percentBp: number;
  fixedMmk: bigint;
  minMmk: bigint | null;
  maxMmk: bigint | null;
  isActive: boolean;
}

const RANK = { EVENT: 0, ORGANIZATION: 1, CATEGORY: 2, GLOBAL: 3 } as const;

export function pickRule<T extends FeeRuleLike>(rules: T[], ctx: { eventId: string; organizationId: string; categoryId: string | null; parentCategoryId?: string | null }): T | null {
  const matches = rules.filter(
    (r) =>
      r.isActive &&
      ((r.scope === 'GLOBAL' && !r.scopeId) ||
        (r.scope === 'EVENT' && r.scopeId === ctx.eventId) ||
        (r.scope === 'ORGANIZATION' && r.scopeId === ctx.organizationId) ||
        (r.scope === 'CATEGORY' && !!r.scopeId && (r.scopeId === ctx.categoryId || r.scopeId === ctx.parentCategoryId))),
  );
  matches.sort((a, b) => RANK[a.scope] - RANK[b.scope]);
  return matches[0] ?? null;
}

/** Commission in whole MMK for a subtotal; never more than the subtotal, 0 for free orders. */
export function commission(rule: FeeRuleLike | null, subtotal: bigint): bigint {
  if (!rule || subtotal <= 0n) return 0n;
  let c = (subtotal * BigInt(rule.percentBp) + 5000n) / 10000n + rule.fixedMmk; // round half up
  if (rule.minMmk != null && c < rule.minMmk) c = rule.minMmk;
  if (rule.maxMmk != null && c > rule.maxMmk) c = rule.maxMmk;
  if (c > subtotal) c = subtotal;
  return c < 0n ? 0n : c;
}
