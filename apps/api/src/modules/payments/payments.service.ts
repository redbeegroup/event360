import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  GoneException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PaymentProviderCode, Prisma } from '@prisma/client';
import { createHmac, randomUUID } from 'crypto';
import { mmk } from '../../common/util';
import { NotifyService } from '../notifications/notify.service';
import { PaymentSettingsService } from '../notifications/settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { EventSeatsService } from '../seating/event-seats.service';
import { claimSeats, lockEventRow, refundSeats, releaseSeats, sellSeats, unclaimSeats } from '../seating/seat-claims';
import { commission, pickRule } from './fee';
import { applyPromo, normalizeCode } from './promo';
import { ACC, journal } from './ledger';
import { KbzPayProvider } from './providers/kbzpay.provider';
import { MockProvider } from './providers/mock.provider';
import { InvalidSignatureError, PaymentProvider, ProviderStatus } from './providers/provider';
import { WavePayProvider } from './providers/wavepay.provider';

export const HOLD_MINUTES = 10;
const OPEN_ORDER = ['PENDING_PAYMENT'] as const;

export interface OrderItemInput {
  ticketTypeId: string;
  quantity: number;
}

const maskPhone = (p?: string | null) => (p ? `${p.slice(0, 4)}•••${p.slice(-3)}` : null);
/** 409 for a seated checkout: the app refreshes the map and keeps the buyer's other seats. */
const seatsTaken = (takenSeats: string[]) => new ConflictException({ message: 'Some seats were just taken', takenSeats });
type IssueItem = { ticketTypeId: string; quantity: number; seatKeys?: string[] };

@Injectable()
export class PaymentsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PaymentsService.name);
  private timer?: NodeJS.Timeout;
  readonly mock: MockProvider;
  private readonly providers: Map<PaymentProviderCode, PaymentProvider>;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    settings: PaymentSettingsService,
    private readonly notify: NotifyService,
    private readonly seating: EventSeatsService,
  ) {
    const secret = createHmac('sha256', config.get<string>('JWT_ACCESS_SECRET') ?? 'dev-only').update('mock-pay').digest('hex');
    this.mock = new MockProvider(prisma, config.get('PAYMENTS_MOCK') === 'true', secret, this.apiBase);
    this.providers = new Map<PaymentProviderCode, PaymentProvider>([
      ['KBZPAY', new KbzPayProvider(settings)],
      ['WAVEPAY', new WavePayProvider(settings, `${this.apiBase}/v1/payments/done`)],
      ['MOCK', this.mock],
    ]);
  }

  get apiBase() {
    return (this.config.get<string>('PUBLIC_API_URL') ?? 'http://localhost:3000').replace(/\/+$/, '');
  }

  onModuleInit() {
    if ((process.env.APP_ROLE ?? 'api') === 'api' && process.env.NODE_ENV !== 'test') {
      this.timer = setInterval(() => this.sweep().catch((e) => this.logger.warn(`sweep: ${e.message}`)), 30_000);
    }
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  provider(code: string): PaymentProvider {
    const p = this.providers.get(code.toUpperCase() as PaymentProviderCode);
    if (!p) throw new NotFoundException('Unknown payment provider');
    return p;
  }

  /** Providers buyers can choose now. */
  async methods() {
    const out: { code: PaymentProviderCode; label: string }[] = [];
    for (const p of this.providers.values()) if (await p.available().catch(() => false)) out.push({ code: p.code, label: p.label });
    return out;
  }

  // ───────────── checkout ─────────────

  /**
   * Quantity lines (`items`) take from ticket_types counters; seats (`seats`, seated events) are claimed in
   * event_seats, all or none, and each seat is one ticket of the type assigned to it. Both may be in one order.
   */
  async createOrder(
    userId: string,
    eventId: string,
    items: OrderItemInput[],
    idempotencyKey?: string,
    channel: 'APP' | 'WEB' = 'APP',
    promoCode?: string,
    seats: string[] = [],
  ) {
    if (idempotencyKey) {
      const existing = await this.prisma.order.findUnique({ where: { idempotencyKey } });
      if (existing) {
        if (existing.userId !== userId) throw new ConflictException('Idempotency key already used');
        return this.orderView(userId, existing.id);
      }
    }
    const merged = new Map<string, number>();
    for (const i of items) merged.set(i.ticketTypeId, (merged.get(i.ticketTypeId) ?? 0) + i.quantity);
    if (!merged.size && !seats.length) throw new BadRequestException('Choose at least one ticket');
    if (new Set(seats).size !== seats.length) throw new BadRequestException('The same seat is listed more than once');

    const event = await this.prisma.event.findUnique({
      where: { id: eventId },
      include: { ticketTypes: true, category: { select: { id: true, parentId: true } } },
    });
    if (!event) throw new NotFoundException('Event not found');
    if (event.status !== 'PUBLISHED') throw new ConflictException('Registration is not open for this event');
    const now = new Date();
    if (event.endsAt <= now) throw new ConflictException('This event has ended');

    const seatType = new Map<string, string>(); // seatKey → ticket type it is sold as
    if (seats.length) {
      if (!event.seatMapVersionId) throw new BadRequestException('This event has no seat map');
      const rows = await this.prisma.eventSeat.findMany({ where: { eventId, seatKey: { in: seats } }, select: { seatKey: true, ticketTypeId: true } });
      const found = new Map(rows.map((r) => [r.seatKey, r.ticketTypeId]));
      const unknown = seats.find((k) => !found.has(k));
      if (unknown) throw new BadRequestException(`Unknown seat ${unknown}`);
      const off = seats.find((k) => !found.get(k));
      if (off) throw new BadRequestException(`Seat ${off} is not on sale`);
      for (const k of seats) seatType.set(k, found.get(k)!);
    }
    if (event.seatMapVersionId && merged.size) {
      const seated = await this.prisma.eventSeat.findFirst({ where: { eventId, ticketTypeId: { in: [...merged.keys()] } }, select: { id: true } });
      if (seated) throw new BadRequestException('Seated tickets are bought by choosing seats');
    }
    const bySeatType = new Map<string, string[]>();
    for (const k of seats) bySeatType.set(seatType.get(k)!, [...(bySeatType.get(seatType.get(k)!) ?? []), k]);
    const wanted: [string, number, string[]][] = [
      ...[...merged].map(([id, q]): [string, number, string[]] => [id, q, []]),
      ...[...bySeatType].map(([id, keys]): [string, number, string[]] => [id, keys.length, keys]),
    ];

    let subtotal = 0n;
    const lines = wanted.map(([ticketTypeId, quantity, seatKeys]) => {
      const tt = event.ticketTypes.find((t) => t.id === ticketTypeId);
      if (!tt) throw new NotFoundException('Ticket type not found');
      if (tt.salesStartAt && tt.salesStartAt > now) throw new ConflictException(`Sales for ${tt.name} have not opened yet`);
      if (tt.salesEndAt && tt.salesEndAt < now) throw new ConflictException(`Sales for ${tt.name} have closed`);
      if (quantity > tt.maxPerOrder) throw new BadRequestException(`At most ${tt.maxPerOrder} ${tt.name} per person`);
      subtotal += tt.priceMmk * BigInt(quantity);
      return { tt, quantity, seatKeys };
    });
    // Promo code: discount on paid lines; a 100% code makes the order free (tickets issued now)
    let promo: { id: string } | null = null;
    let discount = 0n;
    if (promoCode?.trim()) {
      const p = await this.prisma.promoCode.findUnique({ where: { eventId_code: { eventId, code: normalizeCode(promoCode) } } });
      const r = applyPromo(p, lines.map(({ tt, quantity }) => ({ ticketTypeId: tt.id, unitPriceMmk: tt.priceMmk, quantity })), now);
      if (!r.ok) throw new BadRequestException(r.reason);
      promo = p;
      discount = r.discountMmk;
    }
    const total = subtotal - discount;
    const paid = total > 0n;
    if (paid && !(await this.methods()).length) throw new ConflictException('Paid tickets are not on sale yet');

    const rules = paid ? await this.prisma.feeRule.findMany({ where: { isActive: true } }) : [];
    const fee = commission(
      pickRule(rules, { eventId, organizationId: event.organizationId, categoryId: event.category?.id ?? null, parentCategoryId: event.category?.parentId ?? null }),
      total,
    );

    const orderId = await this.prisma.$transaction(async (tx) => {
      // Serialize one buyer's checkouts so the per-person limit can't be raced
      await tx.$executeRaw`SELECT id FROM users WHERE id = ${userId}::uuid FOR UPDATE`;
      if (seats.length) {
        // Serialise with seat assignment changes, then make sure the seats are still sold as the types we priced
        await lockEventRow(tx, eventId);
        const now2 = await tx.eventSeat.findMany({ where: { eventId, seatKey: { in: seats } }, select: { seatKey: true, ticketTypeId: true } });
        const moved = now2.filter((x) => x.ticketTypeId !== seatType.get(x.seatKey)).map((x) => x.seatKey);
        if (moved.length) throw seatsTaken(moved);
      }
      for (const { tt, quantity, seatKeys } of lines) {
        const held = await tx.ticket.count({ where: { holderUserId: userId, ticketTypeId: tt.id, status: { in: ['VALID', 'CHECKED_IN'] } } });
        const pending = await tx.orderItem.aggregate({
          _sum: { quantity: true },
          where: { ticketTypeId: tt.id, order: { userId, status: 'PENDING_PAYMENT', holdExpiresAt: { gt: now } } },
        });
        const already = held + (pending._sum.quantity ?? 0);
        if (already + quantity > tt.maxPerOrder) {
          throw new ConflictException(`You already have ${already} ${tt.name} ticket(s); the limit is ${tt.maxPerOrder} per person`);
        }
        if (seatKeys.length) continue; // seats are claimed below; their counters follow event_seats
        const n = paid
          ? await tx.$executeRaw`UPDATE ticket_types SET held = held + ${quantity} WHERE id = ${tt.id}::uuid AND sold + held + ${quantity} <= quota`
          : await tx.$executeRaw`UPDATE ticket_types SET sold = sold + ${quantity} WHERE id = ${tt.id}::uuid AND sold + held + ${quantity} <= quota`;
        if (n !== 1) throw new ConflictException(`Not enough ${tt.name} tickets left`);
      }
      if (promo) {
        const used = await tx.$executeRaw`UPDATE promo_codes SET used = used + 1 WHERE id = ${promo.id}::uuid AND (max_uses IS NULL OR used < max_uses)`;
        if (used !== 1) throw new ConflictException('This code has been used up');
      }
      const order = await tx.order.create({
        data: {
          userId,
          eventId,
          status: paid ? 'PENDING_PAYMENT' : 'CONFIRMED',
          subtotalMmk: subtotal,
          discountMmk: discount,
          promoCodeId: promo?.id ?? null,
          totalMmk: total, // organizer absorbs the commission: buyer pays the (discounted) ticket price
          commissionMmk: fee,
          idempotencyKey: idempotencyKey ?? null,
          holdExpiresAt: paid ? new Date(now.getTime() + HOLD_MINUTES * 60e3) : null,
          channel,
          items: { create: lines.map(({ tt, quantity, seatKeys }) => ({ ticketTypeId: tt.id, quantity, unitPriceMmk: tt.priceMmk, seatKeys })) },
        },
      });
      if (seats.length) {
        const c = await claimSeats(tx, eventId, seats, order.id, order.holdExpiresAt, !paid);
        if (!c.ok) throw seatsTaken(c.taken);
      }
      if (!paid) await this.issueTickets(tx, order.id, userId, lines.map(({ tt, quantity, seatKeys }) => ({ ticketTypeId: tt.id, quantity, seatKeys })));
      if (seats.length) await this.seating.recountTicketTypes(tx, eventId);
      return order.id;
    });
    if (!paid) {
      void this.notify.ticketConfirmed(orderId);
      void this.notify.checkSales(eventId, false);
    }
    return this.orderView(userId, orderId);
  }

  /** What a code would take off (checkout preview; nothing is reserved). */
  async previewPromo(eventId: string, code: string, items: OrderItemInput[]) {
    const types = await this.prisma.ticketType.findMany({ where: { eventId, id: { in: items.map((i) => i.ticketTypeId) } } });
    const lines = items.map((i) => {
      const tt = types.find((t) => t.id === i.ticketTypeId);
      if (!tt) throw new NotFoundException('Ticket type not found');
      return { ticketTypeId: tt.id, unitPriceMmk: tt.priceMmk, quantity: i.quantity };
    });
    const subtotal = lines.reduce((s, l) => s + l.unitPriceMmk * BigInt(l.quantity), 0n);
    const p = await this.prisma.promoCode.findUnique({ where: { eventId_code: { eventId, code: normalizeCode(code) } } });
    const r = applyPromo(p, lines);
    if (!r.ok) return { valid: false, reason: r.reason, subtotalMmk: mmk(subtotal), discountMmk: 0, totalMmk: mmk(subtotal) };
    return { valid: true, code: p!.code, subtotalMmk: mmk(subtotal), discountMmk: mmk(r.discountMmk), totalMmk: mmk(subtotal - r.discountMmk) };
  }

  /** One ticket per unit of a quantity line; one per seat of a seated line, with its label, and the seat becomes SOLD with it. */
  private async issueTickets(tx: Prisma.TransactionClient, orderId: string, userId: string, items: IssueItem[]) {
    await tx.ticket.createMany({
      data: items
        .filter((i) => !i.seatKeys?.length)
        .flatMap((i) => Array.from({ length: i.quantity }, () => ({ orderId, ticketTypeId: i.ticketTypeId, holderUserId: userId }))),
    });
    const keys = items.flatMap((i) => i.seatKeys ?? []);
    if (!keys.length) return;
    const seats = new Map((await tx.eventSeat.findMany({ where: { orderId, seatKey: { in: keys } } })).map((s) => [s.seatKey, s]));
    const ticketIds = new Map<string, string>();
    const data = items.flatMap((i) =>
      (i.seatKeys ?? []).map((k) => {
        const s = seats.get(k);
        if (!s) throw new Error(`issueTickets: seat ${k} is not held by order ${orderId}`);
        const id = randomUUID();
        ticketIds.set(k, id);
        return { id, orderId, ticketTypeId: i.ticketTypeId, holderUserId: userId, seatKey: k, seatLabel: s.label, seatLabelMy: s.labelMy };
      }),
    );
    await tx.ticket.createMany({ data });
    await sellSeats(tx, orderId, ticketIds);
  }

  async orderView(userId: string | null, orderId: string) {
    const o = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: {
        event: { select: { id: true, slug: true, title: true, titleMy: true, startsAt: true } },
        items: { include: { ticketType: { select: { name: true, nameMy: true } } } },
        payments: { orderBy: { createdAt: 'desc' } },
        tickets: { select: { id: true, status: true } },
      },
    });
    if (!o || (userId && o.userId !== userId)) throw new NotFoundException('Order not found');
    const keys = o.items.flatMap((i) => i.seatKeys);
    const labels = keys.length
      ? new Map((await this.prisma.eventSeat.findMany({ where: { eventId: o.eventId, seatKey: { in: keys } }, select: { seatKey: true, label: true, labelMy: true } })).map((s) => [s.seatKey, s]))
      : new Map<string, { label: string; labelMy: string | null }>();
    const live = o.payments.find((p) => p.status === 'PENDING' || p.status === 'INITIATED');
    return {
      id: o.id,
      status: o.status,
      event: o.event,
      items: o.items.map((i) => ({
        ticketTypeId: i.ticketTypeId,
        name: i.ticketType.name,
        nameMy: i.ticketType.nameMy,
        quantity: i.quantity,
        unitPriceMmk: mmk(i.unitPriceMmk),
        seats: i.seatKeys.map((k) => ({ seatKey: k, label: labels.get(k)?.label ?? k, labelMy: labels.get(k)?.labelMy ?? null })),
      })),
      subtotalMmk: mmk(o.subtotalMmk),
      discountMmk: mmk(o.discountMmk),
      totalMmk: mmk(o.totalMmk),
      holdExpiresAt: o.holdExpiresAt,
      paidAt: o.paidAt,
      createdAt: o.createdAt,
      payment: live ? { id: live.id, provider: live.provider, status: live.status, action: live.action } : null,
      payments: o.payments.map((p) => ({ id: p.id, provider: p.provider, status: p.status, createdAt: p.createdAt })),
      ticketIds: o.tickets.map((t) => t.id),
    };
  }

  async myOrders(userId: string, pendingOnly: boolean) {
    const rows = await this.prisma.order.findMany({
      where: { userId, ...(pendingOnly ? { status: 'PENDING_PAYMENT', holdExpiresAt: { gt: new Date() } } : { totalMmk: { gt: 0n } }) },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { id: true },
    });
    return Promise.all(rows.map((r) => this.orderView(userId, r.id)));
  }

  /** Start (or resume) paying an order with one provider. */
  async pay(userId: string, orderId: string, code: string, returnUrl?: string) {
    const provider = this.provider(code);
    if (!(await provider.available())) throw new ConflictException('This payment method is not available');
    const o = await this.prisma.order.findUnique({ where: { id: orderId }, include: { event: { select: { title: true } } } });
    if (!o || o.userId !== userId) throw new NotFoundException('Order not found');
    if (o.status !== 'PENDING_PAYMENT') throw new ConflictException(o.status === 'PAID' ? 'This order is already paid' : 'This order can no longer be paid');
    if (!o.holdExpiresAt || o.holdExpiresAt <= new Date()) throw new GoneException('Your hold expired. Please start again.');

    const reuse = await this.prisma.payment.findFirst({
      where: { orderId, provider: provider.code, status: 'PENDING', expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    if (reuse?.action) return this.orderView(userId, orderId);

    const pay = await this.prisma.payment.create({
      data: { orderId, provider: provider.code, amountMmk: o.totalMmk, status: 'INITIATED', expiresAt: o.holdExpiresAt },
    });
    try {
      const r = await provider.create({
        paymentId: pay.id,
        orderId,
        amountMmk: o.totalMmk,
        title: `Event 360 · ${o.event.title}`.slice(0, 120),
        expiresAt: o.holdExpiresAt,
        notifyUrl: `${this.apiBase}/v1/payments/webhook/${provider.code.toLowerCase()}`,
        returnUrl: this.safeReturnUrl(returnUrl),
        channel: o.channel === 'WEB' ? 'WEB' : 'APP',
      });
      await this.prisma.payment.update({ where: { id: pay.id }, data: { providerRef: r.providerRef, action: r.action as object, status: 'PENDING' } });
    } catch (e) {
      const msg = (e as Error).message.slice(0, 500);
      await this.prisma.payment.update({ where: { id: pay.id }, data: { status: 'FAILED', failureReason: msg } });
      this.logger.warn(`${provider.code} create failed for ${pay.id}: ${msg}`);
      throw new BadGatewayException(`Could not start ${provider.label} payment. Please try again or choose another method.`);
    }
    return this.orderView(userId, orderId);
  }

  /** Only our own front-ends may be used as return URLs (no open redirect). */
  safeReturnUrl(url?: string) {
    if (!url) return undefined;
    try {
      const u = new URL(url);
      const allowed = (this.config.get<string>('CORS_ORIGINS') ?? '').split(',').map((s) => s.trim()).filter(Boolean);
      return allowed.includes(u.origin) ? u.toString() : undefined;
    } catch {
      return undefined;
    }
  }

  async cancel(userId: string, orderId: string) {
    const o = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!o || o.userId !== userId) throw new NotFoundException('Order not found');
    await this.releaseHold(orderId, 'CANCELLED');
    return this.orderView(userId, orderId);
  }

  /** PENDING_PAYMENT → EXPIRED/CANCELLED and give the held seats back (exactly once). */
  private async releaseHold(orderId: string, to: 'EXPIRED' | 'CANCELLED') {
    return this.prisma.$transaction(async (tx) => {
      const seatedIn = await this.seatedEvent(tx, orderId);
      if (seatedIn) await lockEventRow(tx, seatedIn);
      const n = await tx.order.updateMany({ where: { id: orderId, status: 'PENDING_PAYMENT' }, data: { status: to } });
      if (n.count !== 1) return false;
      const o = await tx.order.findUniqueOrThrow({ where: { id: orderId }, select: { promoCodeId: true } });
      if (o.promoCodeId) await tx.$executeRaw`UPDATE promo_codes SET used = GREATEST(used - 1, 0) WHERE id = ${o.promoCodeId}::uuid`;
      const items = await tx.orderItem.findMany({ where: { orderId } });
      for (const i of items) {
        if (i.seatKeys.length) continue;
        await tx.$executeRaw`UPDATE ticket_types SET held = GREATEST(held - ${i.quantity}, 0) WHERE id = ${i.ticketTypeId}::uuid`;
      }
      if (seatedIn) {
        await releaseSeats(tx, orderId, 'AVAILABLE');
        await this.seating.recountTicketTypes(tx, seatedIn);
      }
      return true;
    });
  }

  /** The order's event id when the order has seats (its seat changes must take the event lock), else null. */
  private async seatedEvent(tx: Prisma.TransactionClient, orderId: string): Promise<string | null> {
    const o = await tx.order.findUnique({ where: { id: orderId }, select: { eventId: true, items: { select: { seatKeys: true } } } });
    return o && o.items.some((i) => i.seatKeys.length) ? o.eventId : null;
  }

  // ───────────── provider callbacks ─────────────

  async webhook(code: string, headers: Record<string, string | string[] | undefined>, body: unknown) {
    const provider = this.provider(code);
    let v;
    try {
      v = await provider.verifyCallback(headers, body);
    } catch (e) {
      await this.prisma.paymentEvent.create({ data: { provider: provider.code, verified: false, rawPayload: (body ?? {}) as object } });
      if (e instanceof InvalidSignatureError) throw new UnauthorizedException('Invalid signature');
      throw new BadRequestException((e as Error).message);
    }
    const pay = v.paymentId
      ? await this.prisma.payment.findUnique({ where: { id: v.paymentId } }).catch(() => null)
      : v.providerRef
        ? await this.prisma.payment.findUnique({ where: { provider_providerRef: { provider: provider.code, providerRef: v.providerRef } } })
        : null;
    await this.prisma.paymentEvent.create({ data: { paymentId: pay?.id ?? null, provider: provider.code, verified: true, rawPayload: (body ?? {}) as object } });
    if (!pay || pay.provider !== provider.code) throw new NotFoundException('Unknown payment');
    await this.applyStatus(pay.id, v.status, v.amountMmk);
    return provider.callbackAck();
  }

  private async applyStatus(paymentId: string, status: ProviderStatus, amountMmk?: bigint) {
    if (status === 'SUCCEEDED') return this.settle(paymentId, amountMmk);
    if (status === 'FAILED' || status === 'EXPIRED') {
      await this.prisma.payment.updateMany({ where: { id: paymentId, status: { in: ['INITIATED', 'PENDING'] } }, data: { status } });
    }
  }

  /**
   * Payment confirmed by the provider: issue the tickets and book the sale, exactly once.
   * If the hold already expired, take free seats if there are any; otherwise flag the order for an admin refund.
   */
  async settle(paymentId: string, amountMmk?: bigint) {
    const issuedFor = await this.prisma.$transaction(async (tx) => {
      const pay = await tx.payment.findUnique({ where: { id: paymentId } });
      if (!pay?.orderId) return;
      const seatedIn = await this.seatedEvent(tx, pay.orderId);
      if (seatedIn) await lockEventRow(tx, seatedIn);
      const won = await tx.payment.updateMany({
        where: { id: paymentId, status: { in: ['INITIATED', 'PENDING', 'FAILED', 'EXPIRED'] } },
        data: { status: 'SUCCEEDED' },
      });
      if (won.count !== 1) return; // duplicate callback / already settled
      const order = await tx.order.findUniqueOrThrow({ where: { id: pay.orderId }, include: { items: true, event: { select: { organizationId: true } } } });
      const clearing = ACC.clearing(pay.provider);

      if (amountMmk !== undefined && amountMmk !== pay.amountMmk) {
        await journal(tx, 'payment', pay.id, [{ account: clearing, debit: amountMmk }, { account: ACC.unallocated, credit: amountMmk }]);
        await tx.order.update({ where: { id: order.id }, data: { needsReview: true, reviewNote: `Amount mismatch: paid ${amountMmk}, expected ${pay.amountMmk} (payment ${pay.id})` } });
        return;
      }
      if (order.status === 'PAID' || order.status === 'REFUNDED' || order.status === 'CONFIRMED') {
        await journal(tx, 'payment', pay.id, [{ account: clearing, debit: pay.amountMmk }, { account: ACC.unallocated, credit: pay.amountMmk }]);
        await tx.order.update({ where: { id: order.id }, data: { needsReview: true, reviewNote: `Paid twice: extra payment ${pay.id} (${pay.provider}) must be refunded` } });
        return;
      }

      let issued = false;
      const fromHold = await tx.order.updateMany({ where: { id: order.id, status: 'PENDING_PAYMENT' }, data: { status: 'PAID', paidAt: new Date() } });
      const quantityItems = order.items.filter((i) => !i.seatKeys.length);
      if (fromHold.count === 1) {
        for (const i of quantityItems) await tx.$executeRaw`UPDATE ticket_types SET held = GREATEST(held - ${i.quantity}, 0), sold = sold + ${i.quantity} WHERE id = ${i.ticketTypeId}::uuid`;
        issued = true; // held seats become SOLD as their tickets are issued
      } else {
        // Hold expired or cancelled before the money arrived: try to take the same seats again (all or none)
        let seatsOk = true;
        let claimed: string[] = [];
        const seatKeys = order.items.flatMap((i) => i.seatKeys);
        if (seatKeys.length) {
          const c = await claimSeats(tx, order.eventId, seatKeys, order.id, null, true);
          claimed = c.seats.map((s) => s.id);
          // A seat now sold as another ticket type is not what was paid for
          const typeOf = new Map(order.items.flatMap((i) => i.seatKeys.map((k) => [k, i.ticketTypeId] as const)));
          seatsOk = c.ok && c.seats.every((s) => s.ticketTypeId === typeOf.get(s.seatKey));
        }
        const taken: { id: string; q: number }[] = [];
        if (seatsOk) {
          for (const i of quantityItems) {
            const n = await tx.$executeRaw`UPDATE ticket_types SET sold = sold + ${i.quantity} WHERE id = ${i.ticketTypeId}::uuid AND sold + held + ${i.quantity} <= quota`;
            if (n !== 1) break;
            taken.push({ id: i.ticketTypeId, q: i.quantity });
          }
        }
        issued = seatsOk && taken.length === quantityItems.length;
        if (!issued) {
          for (const t of taken) await tx.$executeRaw`UPDATE ticket_types SET sold = sold - ${t.q} WHERE id = ${t.id}::uuid`;
          await unclaimSeats(tx, claimed);
        }
        await tx.order.update({
          where: { id: order.id },
          data: issued
            ? { status: 'PAID', paidAt: new Date() }
            : { status: 'PAID', paidAt: new Date(), needsReview: true, reviewNote: 'Paid after the hold expired and the tickets sold out: refund the buyer' },
        });
      }
      if (issued) await this.issueTickets(tx, order.id, order.userId, order.items.map((i) => ({ ticketTypeId: i.ticketTypeId, quantity: i.quantity, seatKeys: i.seatKeys })));
      if (seatedIn) await this.seating.recountTicketTypes(tx, seatedIn);
      await journal(tx, 'order', order.id, [
        { account: clearing, debit: order.totalMmk },
        { account: ACC.payable(order.event.organizationId), credit: order.totalMmk - order.commissionMmk },
        { account: ACC.commission, credit: order.commissionMmk },
      ]);
      return issued ? order.id : null;
    });
    if (issuedFor) {
      void this.notify.ticketConfirmed(issuedFor);
      const o = await this.prisma.order.findUnique({ where: { id: issuedFor }, select: { eventId: true } });
      if (o) void this.notify.checkSales(o.eventId, true);
    }
  }

  // ───────────── background: holds + reconciliation ─────────────

  async sweep(now = new Date()) {
    const expired = await this.prisma.order.findMany({ where: { status: 'PENDING_PAYMENT', holdExpiresAt: { lt: now } }, select: { id: true }, take: 200 });
    for (const o of expired) await this.releaseHold(o.id, 'EXPIRED');

    const due = await this.prisma.payment.findMany({
      where: {
        status: 'PENDING',
        createdAt: { lt: new Date(now.getTime() - 60e3) },
        OR: [{ lastCheckedAt: null }, { lastCheckedAt: { lt: new Date(now.getTime() - 60e3) } }],
      },
      take: 50,
    });
    for (const p of due) {
      const tooOld = p.createdAt < new Date(now.getTime() - 2 * 3600e3);
      try {
        const st = await this.provider(p.provider).query({ paymentId: p.id, providerRef: p.providerRef, createdAt: p.createdAt });
        await this.prisma.payment.update({ where: { id: p.id }, data: { lastCheckedAt: now } });
        if (st !== 'PENDING') await this.applyStatus(p.id, st);
        else if (tooOld) await this.applyStatus(p.id, 'EXPIRED');
      } catch (e) {
        await this.prisma.payment.update({ where: { id: p.id }, data: { lastCheckedAt: now } });
        if (tooOld) await this.applyStatus(p.id, 'EXPIRED');
        this.logger.warn(`query ${p.provider} ${p.id}: ${(e as Error).message}`);
      }
    }
    return { expired: expired.length, checked: due.length };
  }

  // ───────────── admin: refunds ─────────────

  /** Whole-order refund: tickets stop working now; the money goes back via the provider, or by hand. */
  async refundOrder(orderId: string, reason: string, actorId: string) {
    const refundIds = await this.prisma.$transaction(async (tx) => {
      const seatedIn = await this.seatedEvent(tx, orderId);
      if (seatedIn) await lockEventRow(tx, seatedIn);
      const n = await tx.order.updateMany({ where: { id: orderId, status: 'PAID' }, data: { status: 'REFUNDED', needsReview: false } });
      if (n.count !== 1) throw new ConflictException('Only paid orders can be refunded');
      const order = await tx.order.findUniqueOrThrow({
        where: { id: orderId },
        include: { tickets: true, payments: { where: { status: 'SUCCEEDED' } }, event: { select: { organizationId: true } } },
      });
      const live = order.tickets.filter((t) => t.status !== 'REFUNDED' && t.status !== 'VOID');
      await tx.ticket.updateMany({ where: { id: { in: live.map((t) => t.id) } }, data: { status: 'REFUNDED' } });
      const perType = new Map<string, number>();
      for (const t of live) if (!t.seatKey) perType.set(t.ticketTypeId, (perType.get(t.ticketTypeId) ?? 0) + 1);
      for (const [id, q] of perType) await tx.$executeRaw`UPDATE ticket_types SET sold = GREATEST(sold - ${q}, 0) WHERE id = ${id}::uuid`;
      if (seatedIn) {
        // Refunded seats go back on sale; seated counters follow event_seats
        await refundSeats(tx, orderId);
        await this.seating.recountTicketTypes(tx, seatedIn);
      }

      // Sale reversed: organizer and platform give back their shares; the buyer is owed the money until it is sent
      await journal(tx, 'refund_order', order.id, [
        { account: ACC.payable(order.event.organizationId), debit: order.totalMmk - order.commissionMmk },
        { account: ACC.commission, debit: order.commissionMmk },
        { account: ACC.refundsPayable, credit: order.totalMmk },
      ]);
      // Extra (duplicate / mismatched) payments were parked as unallocated: return those too
      const extra = order.payments.reduce((s, p) => s + p.amountMmk, 0n) - order.totalMmk;
      if (extra > 0n) await journal(tx, 'refund_extra', order.id, [{ account: ACC.unallocated, debit: extra }, { account: ACC.refundsPayable, credit: extra }]);

      const ids: string[] = [];
      for (const p of order.payments) {
        const r = await tx.refund.create({ data: { orderId, paymentId: p.id, amountMmk: p.amountMmk, reason, createdById: actorId } });
        ids.push(r.id);
      }
      await tx.auditLog.create({ data: { actorId, action: 'order.refund', entityType: 'order', entityId: orderId, data: { reason, tickets: live.length } } });
      return ids;
    });
    for (const id of refundIds) await this.sendRefund(id);
    void this.notify.orderRefunded(orderId);
    return this.adminOrder(orderId);
  }

  /** Ask the provider to return the money (or mark it for a manual transfer). */
  async sendRefund(refundId: string) {
    const r = await this.prisma.refund.findUniqueOrThrow({ where: { id: refundId }, include: { payment: true } });
    if (r.status === 'SUCCEEDED' || !r.payment) return r;
    const provider = this.provider(r.payment.provider);
    if (!provider.refund) return this.prisma.refund.update({ where: { id: r.id }, data: { status: 'MANUAL' } });
    try {
      const out = await provider.refund({ paymentId: r.payment.id, providerRef: r.payment.providerRef, amountMmk: r.amountMmk, refundId: r.id, reason: r.reason });
      return this.completeRefund(r.id, { providerRef: out.providerRef });
    } catch (e) {
      return this.prisma.refund.update({ where: { id: r.id }, data: { status: 'FAILED', error: (e as Error).message.slice(0, 500) } });
    }
  }

  /** Money is back with the buyer (provider confirmed, or admin entered the transfer reference). */
  async completeRefund(refundId: string, p: { providerRef?: string; reference?: string; actorId?: string }) {
    return this.prisma.$transaction(async (tx) => {
      const r = await tx.refund.findUniqueOrThrow({ where: { id: refundId }, include: { payment: true } });
      const n = await tx.refund.updateMany({
        where: { id: refundId, status: { in: ['PENDING', 'FAILED', 'MANUAL'] } },
        data: { status: 'SUCCEEDED', providerRef: p.providerRef ?? null, reference: p.reference ?? null, completedAt: new Date(), error: null },
      });
      if (n.count === 1) {
        await journal(tx, 'refund', r.id, [{ account: ACC.refundsPayable, debit: r.amountMmk }, { account: ACC.clearing(r.payment?.provider ?? 'MANUAL'), credit: r.amountMmk }]);
        if (r.paymentId) await tx.payment.update({ where: { id: r.paymentId }, data: { status: 'REFUNDED' } });
        if (p.actorId) await tx.auditLog.create({ data: { actorId: p.actorId, action: 'refund.complete', entityType: 'refund', entityId: r.id, data: { reference: p.reference ?? null } } });
      }
      return tx.refund.findUniqueOrThrow({ where: { id: refundId } });
    });
  }

  // ───────────── reports ─────────────

  async adminOrders(q: { status?: string; review?: boolean; search?: string; limit?: number }) {
    const s = q.search?.trim();
    const digits = s?.replace(/\D/g, '');
    const or: Prisma.OrderWhereInput[] = !s
      ? []
      : [
          ...(/^[0-9a-f-]{36}$/i.test(s) ? [{ id: s.toLowerCase() }] : []),
          ...(digits && digits.length >= 3 ? [{ user: { phone: { contains: digits } } }] : []),
          { event: { title: { contains: s, mode: 'insensitive' as const } } },
        ];
    const where: Prisma.OrderWhereInput = {
      totalMmk: { gt: 0n },
      ...(q.status ? { status: q.status as Prisma.EnumOrderStatusFilter['equals'] } : {}),
      ...(q.review ? { needsReview: true } : {}),
      ...(or.length ? { OR: or } : {}),
    };
    const rows = await this.prisma.order.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(q.limit ?? 50, 200),
      include: {
        user: { select: { phone: true, displayName: true } },
        event: { select: { title: true, organization: { select: { name: true } } } },
        payments: { orderBy: { createdAt: 'desc' }, take: 3 },
        refunds: true,
        _count: { select: { tickets: true } },
      },
    });
    return rows.map((o) => this.adminRow(o));
  }

  private adminRow(o: {
    id: string;
    status: string;
    needsReview: boolean;
    reviewNote: string | null;
    totalMmk: bigint;
    commissionMmk: bigint;
    createdAt: Date;
    paidAt: Date | null;
    user: { phone: string | null; displayName: string | null };
    event: { title: string; organization: { name: string } };
    payments: { id: string; provider: string; status: string; providerRef: string | null; createdAt: Date }[];
    refunds: { id: string; status: string; amountMmk: bigint; reference: string | null; error: string | null; createdAt: Date }[];
    _count: { tickets: number };
  }) {
    return {
      id: o.id,
      status: o.status,
      needsReview: o.needsReview,
      reviewNote: o.reviewNote,
      totalMmk: mmk(o.totalMmk),
      commissionMmk: mmk(o.commissionMmk),
      createdAt: o.createdAt,
      paidAt: o.paidAt,
      buyer: { phone: maskPhone(o.user.phone), name: o.user.displayName },
      event: o.event.title,
      organization: o.event.organization.name,
      tickets: o._count.tickets,
      payments: o.payments.map((p) => ({ id: p.id, provider: p.provider, status: p.status, providerRef: p.providerRef, createdAt: p.createdAt })),
      refunds: o.refunds.map((r) => ({ id: r.id, status: r.status, amountMmk: mmk(r.amountMmk), reference: r.reference, error: r.error, createdAt: r.createdAt })),
    };
  }

  async adminOrder(orderId: string) {
    const o = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: {
        user: { select: { phone: true, displayName: true } },
        event: { select: { title: true, organization: { select: { name: true } } } },
        payments: { orderBy: { createdAt: 'desc' }, take: 3 },
        refunds: true,
        _count: { select: { tickets: true } },
      },
    });
    if (!o) throw new NotFoundException('Order not found');
    return this.adminRow(o);
  }

  /** What each organizer is owed, from the ledger (sales − commission − refunds). */
  async balances() {
    const sums = await this.prisma.ledgerEntry.groupBy({
      by: ['account'],
      where: { account: { startsWith: 'organizer_payable:' } },
      _sum: { creditMmk: true, debitMmk: true },
    });
    const orgIds = sums.map((s) => s.account.split(':')[1]);
    const orgs = await this.prisma.organization.findMany({ where: { id: { in: orgIds } }, select: { id: true, name: true } });
    const sales = await this.prisma.order.groupBy({
      by: ['eventId'],
      where: { status: { in: ['PAID', 'REFUNDED'] }, totalMmk: { gt: 0n } },
      _sum: { totalMmk: true, commissionMmk: true },
      _count: true,
    });
    const refunded = await this.prisma.order.groupBy({ by: ['eventId'], where: { status: 'REFUNDED', totalMmk: { gt: 0n } }, _sum: { totalMmk: true, commissionMmk: true } });
    const events = await this.prisma.event.findMany({ where: { id: { in: sales.map((s) => s.eventId) } }, select: { id: true, organizationId: true } });
    const orgOf = new Map(events.map((e) => [e.id, e.organizationId]));
    const agg = new Map<string, { gross: bigint; commission: bigint; refunded: bigint; orders: number }>();
    for (const s of sales) {
      const k = orgOf.get(s.eventId)!;
      const a = agg.get(k) ?? { gross: 0n, commission: 0n, refunded: 0n, orders: 0 };
      a.gross += s._sum.totalMmk ?? 0n;
      a.commission += s._sum.commissionMmk ?? 0n;
      a.orders += s._count;
      agg.set(k, a);
    }
    for (const r of refunded) {
      const a = agg.get(orgOf.get(r.eventId)!);
      if (a) {
        a.refunded += r._sum.totalMmk ?? 0n;
        a.commission -= r._sum.commissionMmk ?? 0n;
      }
    }
    return sums
      .map((s) => {
        const id = s.account.split(':')[1];
        const a = agg.get(id) ?? { gross: 0n, commission: 0n, refunded: 0n, orders: 0 };
        return {
          organizationId: id,
          organization: orgs.find((o) => o.id === id)?.name ?? id,
          orders: a.orders,
          grossMmk: mmk(a.gross),
          refundedMmk: mmk(a.refunded),
          commissionMmk: mmk(a.commission),
          owedMmk: mmk((s._sum.creditMmk ?? 0n) - (s._sum.debitMmk ?? 0n)),
        };
      })
      .sort((a, b) => b.owedMmk - a.owedMmk);
  }

  async globalFee() {
    const r = await this.prisma.feeRule.findFirst({ where: { scope: 'GLOBAL', scopeId: null }, orderBy: { createdAt: 'desc' } });
    return r
      ? { percentBp: r.percentBp, fixedMmk: mmk(r.fixedMmk), minMmk: r.minMmk == null ? null : mmk(r.minMmk), maxMmk: r.maxMmk == null ? null : mmk(r.maxMmk), isActive: r.isActive }
      : { percentBp: 0, fixedMmk: 0, minMmk: null, maxMmk: null, isActive: false };
  }

  async setGlobalFee(f: { percentBp: number; fixedMmk?: number; minMmk?: number | null; maxMmk?: number | null; isActive?: boolean }, actorId: string) {
    const data = {
      percentBp: f.percentBp,
      fixedMmk: BigInt(f.fixedMmk ?? 0),
      minMmk: f.minMmk == null ? null : BigInt(f.minMmk),
      maxMmk: f.maxMmk == null ? null : BigInt(f.maxMmk),
      isActive: f.isActive ?? true,
      buyerPays: false,
    };
    const cur = await this.prisma.feeRule.findFirst({ where: { scope: 'GLOBAL', scopeId: null } });
    await this.prisma.$transaction([
      cur ? this.prisma.feeRule.update({ where: { id: cur.id }, data }) : this.prisma.feeRule.create({ data: { scope: 'GLOBAL', ...data } }),
      this.prisma.auditLog.create({ data: { actorId, action: 'fee.global.update', entityType: 'fee_rule', entityId: cur?.id ?? 'GLOBAL', data: { ...f } } }),
    ]);
    return this.globalFee();
  }

  /** Organizer view of one event's sales. */
  async eventSales(organizationId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId }, include: { ticketTypes: { orderBy: { priceMmk: 'asc' } } } });
    if (!e) throw new NotFoundException('Event not found');
    const paid = await this.prisma.order.aggregate({ where: { eventId, status: 'PAID', totalMmk: { gt: 0n } }, _sum: { totalMmk: true, commissionMmk: true }, _count: true });
    const refunded = await this.prisma.order.aggregate({ where: { eventId, status: 'REFUNDED' }, _sum: { totalMmk: true }, _count: true });
    const recent = await this.prisma.order.findMany({
      where: { eventId, status: { in: ['PAID', 'REFUNDED', 'PENDING_PAYMENT'] }, totalMmk: { gt: 0n } },
      orderBy: { createdAt: 'desc' },
      take: 20,
      include: { user: { select: { phone: true, displayName: true } }, items: true },
    });
    const gross = paid._sum.totalMmk ?? 0n;
    const fee = paid._sum.commissionMmk ?? 0n;
    return {
      ticketTypes: e.ticketTypes.map((t) => ({ id: t.id, name: t.name, priceMmk: mmk(t.priceMmk), quota: t.quota, sold: t.sold, held: t.held, revenueMmk: mmk(t.priceMmk * BigInt(t.sold)) })),
      paidOrders: paid._count,
      grossMmk: mmk(gross),
      commissionMmk: mmk(fee),
      netMmk: mmk(gross - fee),
      refundedOrders: refunded._count,
      refundedMmk: mmk(refunded._sum.totalMmk ?? 0n),
      recent: recent.map((o) => ({
        id: o.id,
        status: o.status,
        createdAt: o.createdAt,
        totalMmk: mmk(o.totalMmk),
        quantity: o.items.reduce((s, i) => s + i.quantity, 0),
        buyer: o.user.displayName || maskPhone(o.user.phone),
      })),
    };
  }
}
