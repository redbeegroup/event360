import type { Prisma } from '@prisma/client';

export interface Line {
  account: string;
  debit?: bigint;
  credit?: bigint;
}

/** Account names (MMK, integer). */
export const ACC = {
  clearing: (provider: string) => `provider_clearing:${provider}`,
  payable: (orgId: string) => `organizer_payable:${orgId}`,
  commission: 'platform_commission',
  refundsPayable: 'refunds_payable',
  unallocated: 'unallocated_receipts',
  payoutsCash: 'payouts_cash',
};

/** Writes one balanced journal (sum of debits = sum of credits; zero lines skipped). */
export async function journal(tx: Prisma.TransactionClient, refType: string, refId: string, lines: Line[]) {
  const rows = lines.filter((l) => (l.debit ?? 0n) !== 0n || (l.credit ?? 0n) !== 0n);
  const d = rows.reduce((s, l) => s + (l.debit ?? 0n), 0n);
  const c = rows.reduce((s, l) => s + (l.credit ?? 0n), 0n);
  if (d !== c) throw new Error(`unbalanced journal ${refType}:${refId} (${d} != ${c})`);
  if (!rows.length) return null;
  const { randomUUID } = await import('crypto');
  const journalId = randomUUID();
  await tx.ledgerEntry.createMany({
    data: rows.map((l) => ({ journalId, account: l.account, debitMmk: l.debit ?? 0n, creditMmk: l.credit ?? 0n, refType, refId })),
  });
  return journalId;
}
