import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { PayoutMethod, Prisma } from '@prisma/client';
import { mmk } from '../../common/util';
import { PrismaService } from '../prisma/prisma.service';
import { ACC, journal } from './ledger';

export const PAYOUT_METHODS: PayoutMethod[] = ['BANK', 'KBZPAY', 'WAVEPAY', 'CASH', 'OTHER'];
const PAYOUT_REFS = ['payout', 'payout_void'];

export interface EventFigures {
  eventId: string;
  title: string;
  orders: number;
  grossMmk: bigint;
  discountMmk: bigint;
  commissionMmk: bigint;
  refundsMmk: bigint;
  netMmk: bigint;
}

export interface OrgFigures {
  organizationId: string;
  orders: number;
  grossMmk: bigint;
  refundedMmk: bigint;
  commissionMmk: bigint;
  /** Net after commission and refunds, from the ledger (payable account, payouts excluded). */
  earnedMmk: bigint;
  paidOutMmk: bigint;
  /** earned − paid out; negative means the organizer was paid more than they earned. */
  owedMmk: bigint;
  events: EventFigures[];
}

/**
 * The one source of per-organization money figures, used by BOTH the admin balances report and the organizer
 * payouts summary so they can never disagree.
 * - earned / paid out / owed come from the `organizer_payable:<org>` ledger account (voids reverse payouts).
 * - the per-event breakdown uses PAID + REFUNDED orders, COMP excluded, refunds as the sale reversal and
 *   commission net of refunds. `discountMmk` is promo + group discount (both live on `orders.discount_mmk`).
 * Pass `orgId` for one organization, omit for every organization with a payable ledger account.
 */
export async function orgFigures(prisma: PrismaService | Prisma.TransactionClient, orgId?: string): Promise<Map<string, OrgFigures>> {
  const ledger = await prisma.ledgerEntry.groupBy({
    by: ['account', 'refType'],
    where: orgId ? { account: ACC.payable(orgId) } : { account: { startsWith: 'organizer_payable:' } },
    _sum: { creditMmk: true, debitMmk: true },
  });
  const out = new Map<string, OrgFigures>();
  const get = (id: string) => {
    let f = out.get(id);
    if (!f) out.set(id, (f = { organizationId: id, orders: 0, grossMmk: 0n, refundedMmk: 0n, commissionMmk: 0n, earnedMmk: 0n, paidOutMmk: 0n, owedMmk: 0n, events: [] }));
    return f;
  };
  for (const l of ledger) {
    const f = get(l.account.split(':')[1]);
    const cr = l._sum.creditMmk ?? 0n;
    const dr = l._sum.debitMmk ?? 0n;
    if (PAYOUT_REFS.includes(l.refType)) f.paidOutMmk += dr - cr;
    else f.earnedMmk += cr - dr;
  }
  for (const f of out.values()) f.owedMmk = f.earnedMmk - f.paidOutMmk;

  const evWhere: Prisma.EventWhereInput = orgId ? { organizationId: orgId } : { organizationId: { in: [...out.keys()] } };
  const events = await prisma.event.findMany({ where: evWhere, select: { id: true, title: true, organizationId: true } });
  const eventIds = events.map((e) => e.id);
  const base = { eventId: { in: eventIds }, totalMmk: { gt: 0n }, channel: { not: 'COMP' } } as const;
  const sales = await prisma.order.groupBy({
    by: ['eventId'],
    where: { ...base, status: { in: ['PAID', 'REFUNDED'] } },
    _sum: { totalMmk: true, commissionMmk: true, discountMmk: true },
    _count: true,
  });
  const refunded = await prisma.order.groupBy({ by: ['eventId'], where: { ...base, status: 'REFUNDED' }, _sum: { totalMmk: true, commissionMmk: true } });
  const refOf = new Map(refunded.map((r) => [r.eventId, r._sum]));
  const evById = new Map(events.map((e) => [e.id, e]));
  for (const s of sales) {
    const ev = evById.get(s.eventId)!;
    const r = refOf.get(s.eventId);
    const gross = s._sum.totalMmk ?? 0n;
    const refunds = r?.totalMmk ?? 0n;
    const commission = (s._sum.commissionMmk ?? 0n) - (r?.commissionMmk ?? 0n);
    const f = get(ev.organizationId);
    f.orders += s._count;
    f.grossMmk += gross;
    f.refundedMmk += refunds;
    f.commissionMmk += commission;
    f.events.push({ eventId: ev.id, title: ev.title, orders: s._count, grossMmk: gross, discountMmk: s._sum.discountMmk ?? 0n, commissionMmk: commission, refundsMmk: refunds, netMmk: gross - refunds - commission });
  }
  for (const f of out.values()) f.events.sort((a, b) => a.title.localeCompare(b.title));
  return out;
}

export function emptyFigures(organizationId: string): OrgFigures {
  return { organizationId, orders: 0, grossMmk: 0n, refundedMmk: 0n, commissionMmk: 0n, earnedMmk: 0n, paidOutMmk: 0n, owedMmk: 0n, events: [] };
}

export interface RecordPayoutInput {
  amountMmk: number;
  paidAt: string;
  method: PayoutMethod;
  reference?: string;
  note?: string;
}

@Injectable()
export class PayoutsService {
  constructor(private readonly prisma: PrismaService) {}

  private view(p: { id: string; organizationId: string; amountMmk: bigint; paidAt: Date; method: PayoutMethod; reference: string | null; note: string | null; createdById: string; voidedAt: Date | null; voidReason: string | null; createdAt: Date }) {
    return {
      id: p.id,
      organizationId: p.organizationId,
      amountMmk: mmk(p.amountMmk),
      paidAt: p.paidAt,
      method: p.method,
      reference: p.reference,
      note: p.note,
      createdById: p.createdById,
      createdAt: p.createdAt,
      voidedAt: p.voidedAt,
      voidReason: p.voidReason,
    };
  }

  async list(orgId: string) {
    const rows = await this.prisma.payout.findMany({ where: { organizationId: orgId }, orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }] });
    return rows.map((p) => this.view(p));
  }

  async record(orgId: string, input: RecordPayoutInput, actorId: string) {
    const org = await this.prisma.organization.findUnique({ where: { id: orgId }, select: { id: true } });
    if (!org) throw new NotFoundException('Organization not found');
    if (!Number.isSafeInteger(input.amountMmk) || input.amountMmk <= 0) throw new BadRequestException('Amount must be a positive whole number of MMK');
    if (!PAYOUT_METHODS.includes(input.method)) throw new BadRequestException('Unknown payout method');
    const amount = BigInt(input.amountMmk);
    const paidAt = new Date(input.paidAt);
    if (Number.isNaN(paidAt.getTime())) throw new BadRequestException('Invalid paidAt');
    return this.prisma.$transaction(async (tx) => {
      const p = await tx.payout.create({ data: { organizationId: orgId, amountMmk: amount, paidAt, method: input.method, reference: input.reference || null, note: input.note || null, createdById: actorId } });
      await journal(tx, 'payout', p.id, [{ account: ACC.payable(orgId), debit: amount }, { account: ACC.payoutsCash, credit: amount }]);
      await tx.auditLog.create({ data: { actorId, action: 'payout.record', entityType: 'payout', entityId: p.id, data: { organizationId: orgId, amountMmk: input.amountMmk, method: input.method, reference: input.reference ?? null } } });
      return this.view(p);
    });
  }

  async void(id: string, reason: string, actorId: string) {
    return this.prisma.$transaction(async (tx) => {
      // Row lock: two concurrent voids serialize, the second sees voidedAt and gets 409 (no double reversal).
      const locked = await tx.$queryRaw<{ id: string }[]>`SELECT id FROM payouts WHERE id = ${id}::uuid FOR UPDATE`;
      if (!locked.length) throw new NotFoundException('Payout not found');
      const p = await tx.payout.findUniqueOrThrow({ where: { id } });
      if (p.voidedAt) throw new ConflictException('Payout already voided');
      const v = await tx.payout.update({ where: { id }, data: { voidedAt: new Date(), voidReason: reason, voidedById: actorId } });
      await journal(tx, 'payout_void', p.id, [{ account: ACC.payoutsCash, debit: p.amountMmk }, { account: ACC.payable(p.organizationId), credit: p.amountMmk }]);
      await tx.auditLog.create({ data: { actorId, action: 'payout.void', entityType: 'payout', entityId: p.id, data: { organizationId: p.organizationId, amountMmk: mmk(p.amountMmk), reason } } });
      return this.view(v);
    });
  }

  /** Organizer-facing summary; same figures as the admin balances report. */
  async summary(orgId: string) {
    const f = (await orgFigures(this.prisma, orgId)).get(orgId) ?? emptyFigures(orgId);
    return {
      earnedMmk: mmk(f.earnedMmk),
      paidOutMmk: mmk(f.paidOutMmk),
      owedMmk: mmk(f.owedMmk),
      events: f.events.map((e) => ({ eventId: e.eventId, title: e.title, grossMmk: mmk(e.grossMmk), discountMmk: mmk(e.discountMmk), commissionMmk: mmk(e.commissionMmk), refundsMmk: mmk(e.refundsMmk), netMmk: mmk(e.netMmk) })),
      payouts: await this.list(orgId),
    };
  }
}
