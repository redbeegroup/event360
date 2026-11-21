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
import { maskPhone, mmk } from '../../common/util';
import { NotifyService } from '../notifications/notify.service';
import { PaymentSettingsService } from '../notifications/settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { EventSeatsService } from '../seating/event-seats.service';
import { claimSeats, SEATED_TX, shareLockEvent, refundSeats, releaseSeats, sellSeats, unclaimSeats } from '../seating/seat-claims';
import { commission, pickRule } from './fee';
import { chooseDiscount, currentPrice, priceView } from './pricing';
import { applyPromo, normalizeCode } from './promo';
import { ACC, journal } from './ledger';
import { orgFigures } from './payouts.service';
import { KbzPayProvider } from './providers/kbzpay.provider';
import { MockProvider } from './providers/mock.provider';
import { InvalidSignatureError, PaymentProvider, ProviderStatus } from './providers/provider';
import { WavePayProvider } from './providers/wavepay.provider';
import { WaitlistService } from '../waitlist/waitlist.service';
import { reserveFreed } from '../waitlist/waitlist-stock';

export const HOLD_MINUTES = 10;
const OPEN_ORDER = ['PENDING_PAYMENT'] as const;

export interface OrderItemInput {
  ticketTypeId: string;
  quantity: number;
}

/** 409 for a seated checkout: the app refreshes the map and keeps the buyer's other seats. */
const seatsTaken = (takenSeats: string[]) => new ConflictException({ message: 'Some seats were just taken', takenSeats });
type IssueItem = { ticketTypeId: string; quantity: number; seatKeys?: string[] };
/**
 * Rows sorted by ticket type id: every path that updates several ticket_types rows in one transaction takes them
 * in this order (the same as PostgreSQL's uuid order, which recountTicketTypes uses), so they cannot deadlock.
 */
const byTypeId = <T>(rows: T[], id: (r: T) => string): T[] => [...rows].sort((a, b) => (id(a) < id(b) ? -1 : id(a) > id(b) ? 1 : 0));

/** Flags an order for admin review, keeping any earlier note (one line per reason) so no refund reason is lost. */
async function flagForReview(tx: Prisma.TransactionClient, orderId: string, note: string) {
  await tx.$executeRaw`UPDATE orders SET needs_review = true, review_note = CASE WHEN review_note IS NULL OR review_note = '' THEN ${note} ELSE review_note || E'\n' || ${note} END WHERE id = ${orderId}::uuid`;
}

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
    private readonly waitlist: WaitlistService,
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
      this.timer = setInterval(() => void this.sweepAll(), 30_000);
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
   * `waitlistEntryId`: the buyer's live waitlist offer. Its type's line takes up to the offered quantity from the
   * stock reserved for it (`offered`, or the entry's WAITLIST_HOLD seats) instead of public stock; the entry becomes
   * PURCHASED and whatever the buyer left goes to the next in line. Prices, discounts and promo rules are as usual.
   */
  async createOrder(
    userId: string,
    eventId: string,
    items: OrderItemInput[],
    idempotencyKey?: string,
    channel: 'APP' | 'WEB' = 'APP',
    promoCode?: string,
    seats: string[] = [],
    waitlistEntryId?: string,
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
      include: { ticketTypes: { include: { priceSteps: true } }, groupDiscounts: true, category: { select: { id: true, parentId: true } } },
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

    // The offer: the buyer's own, live, for a type in this order, and not for more than was offered
    let offer: { id: string; ticketTypeId: string; offeredQty: number } | null = null;
    if (waitlistEntryId) {
      const e = await this.prisma.waitlistEntry.findUnique({ where: { id: waitlistEntryId }, include: { ticketType: { select: { eventId: true } } } });
      if (!e || e.userId !== userId || e.ticketType.eventId !== eventId) throw new NotFoundException('Waitlist offer not found');
      if (e.status !== 'OFFERED' || !e.offerExpiresAt || e.offerExpiresAt <= now) throw new ConflictException({ message: 'This waitlist offer is no longer open', reasonCode: 'OFFER_CLOSED' });
      const line = wanted.find(([id]) => id === e.ticketTypeId);
      if (!line) throw new BadRequestException('The order must include the tickets you were offered');
      if (!line[2].length && line[1] > e.offeredQty) throw new BadRequestException(`Your offer is for at most ${e.offeredQty} ticket(s)`);
      offer = { id: e.id, ticketTypeId: e.ticketTypeId, offeredQty: e.offeredQty };
    }

    let subtotal = 0n;
    const lines = wanted.map(([ticketTypeId, quantity, seatKeys]) => {
      const tt = event.ticketTypes.find((t) => t.id === ticketTypeId);
      if (!tt) throw new NotFoundException('Ticket type not found');
      if (tt.salesStartAt && tt.salesStartAt > now) throw new ConflictException(`Sales for ${tt.name} have not opened yet`);
      if (tt.salesEndAt && tt.salesEndAt < now) throw new ConflictException(`Sales for ${tt.name} have closed`);
      if (quantity > tt.maxPerOrder) throw new BadRequestException(`At most ${tt.maxPerOrder} ${tt.name} per person`);
      const unitPrice = currentPrice(tt.priceMmk, tt.priceSteps, now); // frozen into the order item below
      subtotal += unitPrice * BigInt(quantity);
      return { tt, quantity, seatKeys, unitPrice };
    });
    // Promo code: discount on paid lines; a 100% code makes the order free (tickets issued now).
    // The group discount (paid-type tickets only) competes with it: the larger wins, a tie goes to the group discount.
    let promoRow: { id: string } | null = null;
    let promoMmk: bigint | null = null;
    if (promoCode?.trim()) {
      const p = await this.prisma.promoCode.findUnique({ where: { eventId_code: { eventId, code: normalizeCode(promoCode) } } });
      const r = applyPromo(p, lines.map(({ tt, quantity, unitPrice }) => ({ ticketTypeId: tt.id, unitPriceMmk: unitPrice, quantity })), now);
      // Old clients read `message`; the apps map `reasonCode` to their own (Myanmar) text
      if (!r.ok) throw new BadRequestException({ message: r.reason, reasonCode: r.reasonCode });
      promoRow = p;
      promoMmk = r.discountMmk;
    }
    const choice = chooseDiscount(lines.map((l) => ({ unitPriceMmk: l.unitPrice, quantity: l.quantity })), event.groupDiscounts, promoMmk);
    const promo = choice.promoApplied ? promoRow : null; // only a winning code takes a use
    const discount = choice.discountMmk;
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
      if (event.seatMapVersionId) {
        // Shared lock: excludes seat assignment and map changes (not other checkouts) for the rest of the checkout
        await shareLockEvent(tx, eventId);
      }
      if (seats.length) {
        // The seats must still be sold as the types we priced
        const now2 = await tx.eventSeat.findMany({ where: { eventId, seatKey: { in: seats } }, select: { seatKey: true, ticketTypeId: true } });
        const moved = now2.filter((x) => x.ticketTypeId !== seatType.get(x.seatKey)).map((x) => x.seatKey);
        if (moved.length) throw seatsTaken(moved);
      }
      // Standing counter rows in id order (see byTypeId); the order items keep the buyer's order
      for (const { tt, quantity, seatKeys } of byTypeId(lines, (l) => l.tt.id)) {
        const held = await tx.ticket.count({ where: { holderUserId: userId, ticketTypeId: tt.id, isComplimentary: false, status: { in: ['VALID', 'CHECKED_IN'] } } });
        const pending = await tx.orderItem.aggregate({
          _sum: { quantity: true },
          where: { ticketTypeId: tt.id, order: { userId, status: 'PENDING_PAYMENT', holdExpiresAt: { gt: now } } },
        });
        const already = held + (pending._sum.quantity ?? 0);
        if (already + quantity > tt.maxPerOrder) {
          throw new ConflictException(`You already have ${already} ${tt.name} ticket(s); the limit is ${tt.maxPerOrder} per person`);
        }
        if (seatKeys.length) continue; // seats are claimed below; their counters follow event_seats
        // An offer's line moves its quantity from `offered` (reserved for it) to held/sold; others take public stock
        const fromOffer = offer?.ticketTypeId === tt.id;
        const n = fromOffer
          ? paid
            ? await tx.$executeRaw`UPDATE ticket_types SET held = held + ${quantity}, offered = offered - ${quantity} WHERE id = ${tt.id}::uuid AND offered >= ${quantity}`
            : await tx.$executeRaw`UPDATE ticket_types SET sold = sold + ${quantity}, offered = offered - ${quantity} WHERE id = ${tt.id}::uuid AND offered >= ${quantity}`
          : paid
            ? await tx.$executeRaw`UPDATE ticket_types SET held = held + ${quantity} WHERE id = ${tt.id}::uuid AND sold + held + offered + ${quantity} <= quota`
            : await tx.$executeRaw`UPDATE ticket_types SET sold = sold + ${quantity} WHERE id = ${tt.id}::uuid AND sold + held + offered + ${quantity} <= quota`;
        if (n !== 1) throw new ConflictException(fromOffer ? { message: 'This waitlist offer is no longer open', reasonCode: 'OFFER_CLOSED' } : `Not enough ${tt.name} tickets left`);
      }
      if (merged.size) {
        // Quantity lines never sell a seated type. Checked again here, after the counter rows are locked: on a seated
        // event the share lock keeps assignments out; on an event that was unseated when read, an assignment that
        // commits from now on must wait for (or deadlock with, and be refused against) this checkout.
        const seated = await tx.eventSeat.findFirst({ where: { eventId, ticketTypeId: { in: [...merged.keys()] } }, select: { id: true } });
        if (seated) throw new BadRequestException('Seated tickets are bought by choosing seats');
      }
      // Last-use race: if another buyer takes the final use after we read the code, this order fails with USED_UP rather than falling back to the group discount (accepted).
      if (promo) {
        const used = await tx.$executeRaw`UPDATE promo_codes SET used = used + 1 WHERE id = ${promo.id}::uuid AND (max_uses IS NULL OR used < max_uses)`;
        if (used !== 1) throw new ConflictException({ message: 'This code has been used up', reasonCode: 'USED_UP' }); // the last use went meanwhile
      }
      const order = await tx.order.create({
        data: {
          userId,
          eventId,
          status: paid ? 'PENDING_PAYMENT' : 'CONFIRMED',
          subtotalMmk: subtotal,
          discountMmk: discount,
          promoCodeId: promo?.id ?? null,
          groupDiscountBp: choice.groupBp,
          totalMmk: total, // organizer absorbs the commission: buyer pays the (discounted) ticket price
          commissionMmk: fee,
          idempotencyKey: idempotencyKey ?? null,
          holdExpiresAt: paid ? new Date(now.getTime() + HOLD_MINUTES * 60e3) : null,
          channel,
          items: { create: lines.map(({ tt, quantity, seatKeys, unitPrice }) => ({ ticketTypeId: tt.id, quantity, unitPriceMmk: unitPrice, seatKeys })) },
        },
      });
      if (seats.length) {
        const c = await claimSeats(tx, eventId, seats, order.id, order.holdExpiresAt, !paid, offer?.id ?? null);
        if (!c.ok) throw seatsTaken(c.taken);
      }
      if (!paid) await this.issueTickets(tx, order.id, userId, lines.map(({ tt, quantity, seatKeys }) => ({ ticketTypeId: tt.id, quantity, seatKeys })));
      if (seats.length) await this.seating.recountTicketTypes(tx, eventId, [], [...bySeatType.keys()]);
      // The offer's entry row last (lock order): it must still be live now, or everything above rolls back
      if (offer && !(await this.waitlist.markPurchased(tx, offer.id, userId, order.id))) throw new ConflictException({ message: 'This waitlist offer is no longer open', reasonCode: 'OFFER_CLOSED' });
      return order.id;
    }, seats.length ? SEATED_TX : undefined);
    if (!paid) {
      void this.notify.ticketConfirmed(orderId);
      void this.notify.checkSales(eventId, false);
    }
    return this.orderView(userId, orderId);
  }

  /** What a code would take off (checkout preview; nothing is reserved). */
  async previewPromo(eventId: string, code: string, items: OrderItemInput[], seats: string[] = []) {
    if (!items.length && !seats.length) throw new BadRequestException('Choose at least one ticket');
    // Seats count as one ticket each of the type assigned to them, as at checkout
    const seatTypes = new Map<string, number>();
    if (seats.length) {
      const rows = await this.prisma.eventSeat.findMany({ where: { eventId, seatKey: { in: [...new Set(seats)] } }, select: { seatKey: true, ticketTypeId: true } });
      const found = new Map(rows.map((r) => [r.seatKey, r.ticketTypeId]));
      for (const k of new Set(seats)) {
        if (!found.has(k)) throw new BadRequestException(`Unknown seat ${k}`);
        const t = found.get(k);
        if (!t) throw new BadRequestException(`Seat ${k} is not on sale`);
        seatTypes.set(t, (seatTypes.get(t) ?? 0) + 1);
      }
    }
    const wanted = [...items, ...[...seatTypes].map(([ticketTypeId, quantity]) => ({ ticketTypeId, quantity }))];
    const types = await this.prisma.ticketType.findMany({ where: { eventId, id: { in: wanted.map((i) => i.ticketTypeId) } }, include: { priceSteps: true } });
    const now = new Date();
    const lines = wanted.map((i) => {
      const tt = types.find((t) => t.id === i.ticketTypeId);
      if (!tt) throw new NotFoundException('Ticket type not found');
      return { ticketTypeId: tt.id, unitPriceMmk: currentPrice(tt.priceMmk, tt.priceSteps, now), quantity: i.quantity };
    });
    const subtotal = lines.reduce((s, l) => s + l.unitPriceMmk * BigInt(l.quantity), 0n);
    const p = await this.prisma.promoCode.findUnique({ where: { eventId_code: { eventId, code: normalizeCode(code) } } });
    const r = applyPromo(p, lines);
    if (!r.ok) return { valid: false, reason: r.reason, reasonCode: r.reasonCode, subtotalMmk: mmk(subtotal), discountMmk: 0, totalMmk: mmk(subtotal), discountSource: null, promoApplied: false };
    // A valid code can still lose to the group discount: say so, so the app can explain
    const tiers = await this.prisma.groupDiscount.findMany({ where: { eventId }, select: { minQuantity: true, percentBp: true } });
    const c = chooseDiscount(lines, tiers, r.discountMmk);
    return { valid: true, code: p!.code, subtotalMmk: mmk(subtotal), discountMmk: mmk(c.discountMmk), totalMmk: mmk(subtotal - c.discountMmk), discountSource: c.source, promoApplied: c.promoApplied };
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
      discountSource: o.groupDiscountBp != null ? ('GROUP' as const) : o.promoCodeId ? ('PROMO' as const) : null,
      groupDiscountBp: o.groupDiscountBp,
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
    let reopened: string | null = null;
    const out = await this.prisma.$transaction(async (tx) => {
      reopened = null;
      const seatedIn = await this.seatedEvent(tx, orderId);
      if (seatedIn) await shareLockEvent(tx, seatedIn.eventId);
      const n = await tx.order.updateMany({ where: { id: orderId, status: 'PENDING_PAYMENT' }, data: { status: to } });
      if (n.count !== 1) return false;
      const items = byTypeId(await tx.orderItem.findMany({ where: { orderId } }), (i) => i.ticketTypeId);
      // A checkout made from a waitlist offer, released before the offer's own time ran out: the offer gets back what
      // is released (read without a lock: a PURCHASED entry only changes in a release of its order, and this order's
      // row is ours now)
      const lost = await tx.waitlistEntry.findFirst({
        where: { orderId, status: 'PURCHASED', offerExpiresAt: { gt: new Date() } },
        select: { id: true, ticketTypeId: true, offeredQty: true },
      });
      let backToOffer = 0;
      for (const i of items) {
        if (i.seatKeys.length) continue;
        if (lost?.ticketTypeId === i.ticketTypeId) {
          const q = Math.min(i.quantity, lost.offeredQty);
          await tx.$executeRaw`UPDATE ticket_types SET held = GREATEST(held - ${i.quantity}, 0), offered = offered + ${q} WHERE id = ${i.ticketTypeId}::uuid`;
          backToOffer += q;
          if (i.quantity > q) await reserveFreed(tx, i.ticketTypeId, i.quantity - q);
          continue;
        }
        await tx.$executeRaw`UPDATE ticket_types SET held = GREATEST(held - ${i.quantity}, 0) WHERE id = ${i.ticketTypeId}::uuid`;
        await reserveFreed(tx, i.ticketTypeId, i.quantity); // people waiting get it first (row still locked)
      }
      // Same lock order as createOrder and settle: standing ticket_types rows, then the promo code, then seats
      const o = await tx.order.findUniqueOrThrow({ where: { id: orderId }, select: { promoCodeId: true } });
      if (o.promoCodeId) await tx.$executeRaw`UPDATE promo_codes SET used = GREATEST(used - 1, 0) WHERE id = ${o.promoCodeId}::uuid`;
      const seatedOffer = !!lost && !!seatedIn?.typeIds.includes(lost.ticketTypeId);
      if (seatedIn?.typeIds.length) {
        // An offered seat the buyer didn't take may still point at the entry: it counts towards what the offer gets back
        const still = seatedOffer ? await tx.eventSeat.count({ where: { waitlistEntryId: lost!.id, status: 'WAITLIST_HOLD' } }) : 0;
        const offerTo = seatedOffer && lost!.offeredQty > still ? { entryId: lost!.id, ticketTypeId: lost!.ticketTypeId, max: lost!.offeredQty - still } : undefined;
        // A seat may come back under another type (or none) if the rules changed while it was held
        const back = await releaseSeats(tx, orderId, offerTo);
        backToOffer += back.offered;
        await this.seating.recountTicketTypes(tx, seatedIn.eventId, back.typeIds, [...new Set([...seatedIn.typeIds, ...back.typeIds])]);
      }
      // A seated offer is exactly the WAITLIST_HOLD seats pointing at it
      if (seatedOffer) backToOffer = await tx.eventSeat.count({ where: { waitlistEntryId: lost!.id, status: 'WAITLIST_HOLD' } });
      // The entry row last. If its time ran out meanwhile, what was set aside for it is the pool (the sweeper offers it on)
      if (lost && backToOffer && (await this.waitlist.reopenOffer(tx, lost.id, orderId, backToOffer))) reopened = lost.id;
      return true;
    }, await this.seatedTx(orderId));
    if (reopened) void this.waitlist.notifyReopened(reopened);
    return out;
  }

  /** Transaction options for an order: a seated one waits for the pool and counter rows like seated checkout does. */
  private async seatedTx(orderId: string | null | undefined) {
    if (!orderId) return undefined;
    const o = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { event: { select: { seatMapVersionId: true } }, items: { where: { seatKeys: { isEmpty: false } }, select: { id: true }, take: 1 } },
    });
    return o && (o.event.seatMapVersionId || o.items.length) ? SEATED_TX : undefined;
  }

  /**
   * For an order on a seated event (or with seats): its event, whose row the caller share-locks so seat
   * assignments can't change under it, and the order's seated ticket types (empty for quantity-only orders).
   * Null for unseated events, which take no event lock, as before.
   */
  private async seatedEvent(tx: Prisma.TransactionClient, orderId: string): Promise<{ eventId: string; typeIds: string[] } | null> {
    const o = await tx.order.findUnique({
      where: { id: orderId },
      select: { eventId: true, event: { select: { seatMapVersionId: true } }, items: { select: { seatKeys: true, ticketTypeId: true } } },
    });
    const seated = o?.items.filter((i) => i.seatKeys.length) ?? [];
    return o && (seated.length || o.event.seatMapVersionId) ? { eventId: o.eventId, typeIds: [...new Set(seated.map((i) => i.ticketTypeId))] } : null;
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
    const txOpts = await this.seatedTx((await this.prisma.payment.findUnique({ where: { id: paymentId }, select: { orderId: true } }))?.orderId);
    const issuedFor = await this.prisma.$transaction(async (tx) => {
      const pay = await tx.payment.findUnique({ where: { id: paymentId } });
      if (!pay?.orderId) return;
      const seatedIn = await this.seatedEvent(tx, pay.orderId);
      if (seatedIn) await shareLockEvent(tx, seatedIn.eventId);
      const won = await tx.payment.updateMany({
        where: { id: paymentId, status: { in: ['INITIATED', 'PENDING', 'FAILED', 'EXPIRED'] } },
        data: { status: 'SUCCEEDED' },
      });
      if (won.count !== 1) return; // duplicate callback / already settled
      // Lock the order row before deciding anything: another payment for the same order (another provider, or a
      // second late payment) may be settling right now, and only one of them may issue the tickets. Lock order:
      // event (share) → payment → order → standing ticket_types → promo code → seats → seated ticket_types.
      const [locked] = await tx.$queryRaw<{ status: string }[]>`SELECT status::text AS status FROM orders WHERE id = ${pay.orderId}::uuid FOR UPDATE`;
      const order = await tx.order.findUniqueOrThrow({ where: { id: pay.orderId }, include: { items: true, event: { select: { organizationId: true } } } });
      const status = locked.status;
      const clearing = ACC.clearing(pay.provider);

      if (amountMmk !== undefined && amountMmk !== pay.amountMmk) {
        await journal(tx, 'payment', pay.id, [{ account: clearing, debit: amountMmk }, { account: ACC.unallocated, credit: amountMmk }]);
        await flagForReview(tx, order.id, `Amount mismatch: paid ${amountMmk}, expected ${pay.amountMmk} (payment ${pay.id})`);
        return;
      }
      if (status === 'PAID' || status === 'REFUNDED' || status === 'CONFIRMED') {
        await journal(tx, 'payment', pay.id, [{ account: clearing, debit: pay.amountMmk }, { account: ACC.unallocated, credit: pay.amountMmk }]);
        await flagForReview(tx, order.id, `Paid twice: extra payment ${pay.id} (${pay.provider}) must be refunded`);
        return;
      }

      let issued = false;
      const quantityItems = byTypeId(order.items.filter((i) => !i.seatKeys.length), (i) => i.ticketTypeId);
      if (status === 'PENDING_PAYMENT') {
        await tx.order.update({ where: { id: order.id }, data: { status: 'PAID', paidAt: new Date() } });
        for (const i of quantityItems) await tx.$executeRaw`UPDATE ticket_types SET held = GREATEST(held - ${i.quantity}, 0), sold = sold + ${i.quantity} WHERE id = ${i.ticketTypeId}::uuid`;
        issued = true; // held seats become SOLD as their tickets are issued
      } else {
        // Hold expired or cancelled before the money arrived: try to take the same seats again (all or none)
        // Same lock order as createOrder: quantity lines (ticket_types) first, then seats.
        const taken: { id: string; q: number }[] = [];
        // A quantity type that has become seated since the order can only be sold with seats now
        const nowSeated =
          seatedIn && quantityItems.length
            ? await tx.eventSeat.findFirst({ where: { eventId: order.eventId, ticketTypeId: { in: quantityItems.map((i) => i.ticketTypeId) } }, select: { id: true } })
            : null;
        if (!nowSeated) {
          for (const i of quantityItems) {
            // Stock reserved for the waitlist is not for late payments either
            const n = await tx.$executeRaw`UPDATE ticket_types SET sold = sold + ${i.quantity} WHERE id = ${i.ticketTypeId}::uuid AND sold + held + offered + ${i.quantity} <= quota`;
            if (n !== 1) break;
            taken.push({ id: i.ticketTypeId, q: i.quantity });
          }
        }
        // Expiry gave the promo use back; the order is PAID either way (tickets or refund review), so take it again,
        // even past max_uses: the code was valid when the order was made. Same place as createOrder: after the
        // standing ticket_types rows, before the seats.
        if (order.promoCodeId) await tx.$executeRaw`UPDATE promo_codes SET used = used + 1 WHERE id = ${order.promoCodeId}::uuid`;
        let seatsOk = taken.length === quantityItems.length;
        let claimed: string[] = [];
        const seatKeys = order.items.flatMap((i) => i.seatKeys);
        if (seatsOk && seatKeys.length) {
          const c = await claimSeats(tx, order.eventId, seatKeys, order.id, null, true);
          claimed = c.seats.map((s) => s.id);
          for (const s of c.seats) if (s.ticketTypeId && seatedIn && !seatedIn.typeIds.includes(s.ticketTypeId)) seatedIn.typeIds.push(s.ticketTypeId);
          // A seat now sold as another ticket type is not what was paid for
          const typeOf = new Map(order.items.flatMap((i) => i.seatKeys.map((k) => [k, i.ticketTypeId] as const)));
          seatsOk = c.ok && c.seats.every((s) => s.ticketTypeId === typeOf.get(s.seatKey));
        }
        issued = seatsOk;
        if (!issued) {
          // Undo of what this transaction just took from public stock: it goes back to the public, not to the
          // waitlist (it was free a moment ago, and the hold's release already reserved for the line)
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
      if (seatedIn) await this.seating.recountTicketTypes(tx, seatedIn.eventId, [], seatedIn.typeIds);
      await journal(tx, 'order', order.id, [
        { account: clearing, debit: order.totalMmk },
        { account: ACC.payable(order.event.organizationId), credit: order.totalMmk - order.commissionMmk },
        { account: ACC.commission, credit: order.commissionMmk },
      ]);
      return issued ? order.id : null;
    }, txOpts);
    if (issuedFor) {
      void this.notify.ticketConfirmed(issuedFor);
      const o = await this.prisma.order.findUnique({ where: { id: issuedFor }, select: { eventId: true } });
      if (o) void this.notify.checkSales(o.eventId, true);
    }
  }

  // ───────────── background: holds + reconciliation ─────────────

  /** The 30 s loop on API pods: holds and payments, then the waitlist (expired offers out, reserved stock offered). */
  async sweepAll(now = new Date()) {
    await this.sweep(now).catch((e) => this.logger.warn(`sweep: ${(e as Error).message}`));
    await this.waitlist.expireOffers(now).catch((e) => this.logger.warn(`waitlist expiry: ${(e as Error).message}`));
    await this.waitlist.assignOffers(now).catch((e) => this.logger.warn(`waitlist offers: ${(e as Error).message}`));
  }

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
      if (seatedIn) await shareLockEvent(tx, seatedIn.eventId);
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
      for (const [id, q] of byTypeId([...perType], ([k]) => k)) {
        await tx.$executeRaw`UPDATE ticket_types SET sold = GREATEST(sold - ${q}, 0) WHERE id = ${id}::uuid`;
        await reserveFreed(tx, id, q); // people waiting get it first (row still locked)
      }
      if (seatedIn?.typeIds.length) {
        // Refunded seats go back on sale; seated counters follow event_seats
        const back = await refundSeats(tx, orderId);
        await this.seating.recountTicketTypes(tx, seatedIn.eventId, back.typeIds, [...new Set([...seatedIn.typeIds, ...back.typeIds])]);
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
    }, await this.seatedTx(orderId));
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

  /** What each organizer earned, was paid and is owed — the same figures the organizer payouts summary shows. */
  async balances() {
    const figs = await orgFigures(this.prisma);
    const orgs = await this.prisma.organization.findMany({ where: { id: { in: [...figs.keys()] } }, select: { id: true, name: true } });
    return [...figs.values()]
      .map((f) => ({
        organizationId: f.organizationId,
        organization: orgs.find((o) => o.id === f.organizationId)?.name ?? f.organizationId,
        orders: f.orders,
        grossMmk: mmk(f.grossMmk),
        refundedMmk: mmk(f.refundedMmk),
        commissionMmk: mmk(f.commissionMmk),
        paidOutMmk: mmk(f.paidOutMmk),
        owedMmk: mmk(f.owedMmk),
      }))
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
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId }, include: { ticketTypes: { orderBy: { priceMmk: 'asc' }, include: { priceSteps: true } } } });
    if (!e) throw new NotFoundException('Event not found');
    // What each type actually earned: the frozen unit price of paid, non-comp order items
    const earned = new Map<string, bigint>();
    for (const r of await this.prisma.orderItem.findMany({ where: { order: { eventId, status: 'PAID', channel: { not: 'COMP' } } }, select: { ticketTypeId: true, quantity: true, unitPriceMmk: true } })) {
      earned.set(r.ticketTypeId, (earned.get(r.ticketTypeId) ?? 0n) + r.unitPriceMmk * BigInt(r.quantity));
    }
    const nowT = new Date();
    const paid = await this.prisma.order.aggregate({ where: { eventId, status: 'PAID', totalMmk: { gt: 0n }, channel: { not: 'COMP' } }, _sum: { totalMmk: true, commissionMmk: true }, _count: true });
    const refunded = await this.prisma.order.aggregate({ where: { eventId, status: 'REFUNDED', channel: { not: 'COMP' } }, _sum: { totalMmk: true }, _count: true });
    const recent = await this.prisma.order.findMany({
      where: { eventId, status: { in: ['PAID', 'REFUNDED', 'PENDING_PAYMENT'] }, totalMmk: { gt: 0n }, channel: { not: 'COMP' } },
      orderBy: { createdAt: 'desc' },
      take: 20,
      include: { user: { select: { phone: true, displayName: true } }, items: true },
    });
    const gross = paid._sum.totalMmk ?? 0n;
    const fee = paid._sum.commissionMmk ?? 0n;
    return {
      ticketTypes: e.ticketTypes.map((t) => ({ id: t.id, name: t.name, ...priceView(t, nowT), quota: t.quota, sold: t.sold, held: t.held, offered: t.offered, revenueMmk: mmk(earned.get(t.id) ?? 0n) })),
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
