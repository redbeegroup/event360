import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { NotifyService, when } from '../notifications/notify.service';
import { SmsService } from '../notifications/sms.service';
import { PrismaService } from '../prisma/prisma.service';
import { EventSeatsService } from '../seating/event-seats.service';
import { returnSeatsToSale, SEATED_TX, shareLockEvent } from '../seating/seat-claims';
import { liveOfferedQty, OFFER_MINUTES, poolSeatCount, poolSeats, reserveAvailableSeats, reserveFreed, reserveFreedSeats } from './waitlist-stock';

export { OFFER_MINUTES, reserveFreed, reserveFreedSeats } from './waitlist-stock';

type Tx = Prisma.TransactionClient;
const ACTIVE = ['WAITING', 'OFFERED'] as const;

/**
 * A type's line is closed once its sales end, its event starts, or the event is cancelled or completed: entries
 * expire and the reserve goes back. While the event is otherwise not PUBLISHED (DRAFT/SUBMITTED during a re-review)
 * the line is paused: no joins and no new offers, nothing given back; WAITING entries keep their place and live
 * offers run to their normal expiry.
 */
export function lineState(t: { salesEndAt: Date | null; event: { status: string; startsAt: Date } }, now: Date): 'open' | 'paused' | 'closed' {
  if (['CANCELLED', 'COMPLETED'].includes(t.event.status) || t.event.startsAt <= now || (t.salesEndAt && t.salesEndAt <= now)) return 'closed';
  return t.event.status === 'PUBLISHED' ? 'open' : 'paused';
}
const ORDER_PAYMENTS = { select: { status: true, payments: { select: { status: true } } } } as const;
const OFFER_INCLUDE = { ticketType: { select: { name: true, nameMy: true, event: { select: { id: true, title: true, titleMy: true } } } } } as const;

/** The expired/closed notice for a buyer whose payment is still in flight: the reservation is gone, the payment may land. */
const releasedWhilePaying = (ev: { id: string; title: string; titleMy: string | null }) => ({
  kind: 'waitlist_offer_expired' as const,
  title: 'Your reserved tickets were released',
  titleMy: 'သင့်အတွက် ထိန်းထားသော လက်မှတ်များကို ပြန်လွှတ်လိုက်ပါပြီ',
  body: `Your reserved tickets for ${ev.title} were released. If your payment still goes through, we'll issue tickets if any are left, or refund you.`,
  bodyMy: `${ev.titleMy || ev.title} အတွက် သင့်အတွက် ထိန်းထားသော လက်မှတ်များကို ပြန်လွှတ်လိုက်ပါပြီ။ သင့်ငွေပေးချေမှု ဆက်လက် အောင်မြင်ပါက လက်မှတ်ကျန်သေးလျှင် ထုတ်ပေးပါမည်၊ မကျန်တော့ပါက ငွေပြန်အမ်းပေးပါမည်။`,
  link: `/event/${ev.id}`,
  eventId: ev.id,
});

/** The waitlist_offer notice (same text for its stored inbox row and for its push/SMS). */
const offerNotice = (
  e: { offeredQty: number; offerExpiresAt: Date | null; ticketType: { name: string; nameMy: string | null; event: { id: string; title: string; titleMy: string | null } } },
  sms: boolean,
) => {
  const ev = e.ticketType.event;
  const until = e.offerExpiresAt!;
  return {
    kind: 'waitlist_offer' as const,
    title: 'Tickets are available for you',
    titleMy: 'သင့်အတွက် လက်မှတ် ရနိုင်ပါပြီ',
    body: `${e.offeredQty} ${e.ticketType.name} ticket(s) for ${ev.title} are held for you until ${when(until)}. Buy them before then.`,
    bodyMy: `${ev.titleMy || ev.title} အတွက် ${e.ticketType.nameMy || e.ticketType.name} လက်မှတ် ${e.offeredQty} စောင်ကို ${when(until, 'my')} အထိ သင့်အတွက် ထိန်းထားပါသည်။ ထိုအချိန်မတိုင်မီ ဝယ်ယူပါ။`,
    link: `/event/${ev.id}`,
    eventId: ev.id,
    ...(sms ? { sms: `Tickets for ${short(ev.title, 60)} are available for you until ${when(until)}. Open Event 360.` } : {}),
  };
};
const short = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/**
 * Waitlists for sold-out ticket types (spec "Waitlist", decisions 1-3 and 8).
 * - Every path that frees stock reserves it for the line in its own transaction (reserveFreed / reserveFreedSeats,
 *   waitlist-stock.ts), so the public never sees it while anyone is WAITING.
 * - The payments sweeper (every 30 s on API pods) runs expireOffers then assignOffers: reserved stock goes to WAITING
 *   entries in line order (a partial offer when less is free than the next entry wants) for OFFER_MINUTES; stock
 *   nobody is waiting for goes back on sale.
 * - Only the entry's owner can buy from an offer (PaymentsService.createOrder with `waitlistEntryId`).
 * Lock order: see the header of seating/seat-claims.ts; waitlist entry rows always come last.
 */
@Injectable()
export class WaitlistService {
  private readonly logger = new Logger(WaitlistService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly seating: EventSeatsService,
    private readonly notify: NotifyService,
    private readonly sms: SmsService,
  ) {}

  /** See waitlist-stock.ts. */
  reserveFreed(tx: Tx, ticketTypeId: string, qty: number): Promise<number> {
    return reserveFreed(tx, ticketTypeId, qty);
  }

  /** See waitlist-stock.ts. */
  reserveFreedSeats(tx: Tx, seatIds: string[]): Promise<string[]> {
    return reserveFreedSeats(tx, seatIds);
  }

  /**
   * createOrder's last step (entry rows come last in the lock order): the offer becomes PURCHASED by `orderId` if it
   * is still the buyer's and live right now. False means the caller must roll back.
   */
  async markPurchased(tx: Tx, entryId: string, userId: string, orderId: string): Promise<boolean> {
    const n = await tx.$executeRaw`
      UPDATE waitlist_entries SET status = 'PURCHASED', order_id = ${orderId}::uuid, updated_at = now()
      WHERE id = ${entryId}::uuid AND user_id = ${userId}::uuid AND status = 'OFFERED' AND offer_expires_at > clock_timestamp()`;
    return n === 1;
  }

  /**
   * releaseHold's last step: the checkout made from this offer was released before the offer's original expiry, and
   * `qty` was set aside for it again; the entry is OFFERED again until that same expiry. It keeps the released
   * order's id: an OFFERED entry with an order is a reopened offer (its buyer is told if the line closes).
   * Skipped (false) when the buyer already has another active entry for the type: only one may be WAITING/OFFERED
   * (waitlist_entries_active_key), and a failed update would abort the release (and wedge the sweeper). join refuses
   * while such a checkout is unpaid (CHECKOUT_PENDING), so this only meets entries made before that check; the
   * released stock is then the pool, offered on in line order.
   */
  async reopenOffer(tx: Tx, entryId: string, orderId: string, qty: number): Promise<boolean> {
    const n = await tx.$executeRaw`
      UPDATE waitlist_entries e SET status = 'OFFERED', offered_qty = ${qty}, updated_at = now()
      WHERE e.id = ${entryId}::uuid AND e.status = 'PURCHASED' AND e.order_id = ${orderId}::uuid AND e.offer_expires_at > clock_timestamp()
        AND NOT EXISTS (
          SELECT 1 FROM waitlist_entries a
          WHERE a.ticket_type_id = e.ticket_type_id AND a.user_id = e.user_id AND a.status IN ('WAITING', 'OFFERED') AND a.id <> e.id
        )`;
    return n === 1;
  }

  // ───────────── buyers ─────────────

  async join(userId: string, ticketTypeId: string, quantity: number) {
    const t = await this.prisma.ticketType.findUnique({ where: { id: ticketTypeId }, include: { event: true, _count: { select: { eventSeats: true } } } });
    if (!t || !t.event.publishedAt) throw new NotFoundException('Ticket type not found'); // never listed: unknown
    const now = new Date();
    const state = lineState(t, now);
    if (state === 'closed') throw new ConflictException({ message: 'The waitlist is closed', reasonCode: 'WAITLIST_CLOSED' });
    if (state === 'paused') throw new ConflictException({ message: 'The waitlist is paused while the event is being reviewed', reasonCode: 'WAITLIST_PAUSED' });
    if (t.salesStartAt && t.salesStartAt > now) throw new ConflictException('Sales have not opened yet');
    if (quantity < 1 || quantity > t.maxPerOrder) throw new BadRequestException(`Join for 1 to ${t.maxPerOrder} tickets`);
    const seated = t._count.eventSeats > 0;
    const entryId = await this.prisma.$transaction(async (tx) => {
      // The buyer's row first, as at checkout (lock order step 1): serialises one buyer's joins and checkouts, so the
      // per-person limit can't be raced. FOR NO KEY UPDATE, not FOR UPDATE: it must not conflict with the KEY SHARE
      // that inserts referencing the user (a settle's tickets) take while holding this type's counter row.
      await tx.$queryRaw`SELECT id FROM users WHERE id = ${userId}::uuid FOR NO KEY UPDATE`;
      // The type's counter row serialises the join with every path that frees or reserves this type's stock (they
      // hold it while reading the line), so a standing type can't be freed unseen by a joiner. Seated: event (share)
      // then the seated counter row, as in the recount; a release that races a join is caught by the sweeper.
      if (seated) await shareLockEvent(tx, t.eventId);
      const [c] = await tx.$queryRaw<{ quota: number; sold: number; held: number; offered: number }[]>`
        SELECT quota, sold, held, offered FROM ticket_types WHERE id = ${ticketTypeId}::uuid FOR NO KEY UPDATE`;
      const open = seated
        ? await tx.eventSeat.count({ where: { ticketTypeId, status: 'AVAILABLE' } })
        : c.quota - c.sold - c.held - c.offered;
      if (open > 0) throw new ConflictException({ message: 'These tickets are not sold out: you can buy them now', reasonCode: 'NOT_SOLD_OUT' });
      // The per-person limit, as at checkout: what the buyer holds or is paying for, plus what they wait for
      const held = await tx.ticket.count({ where: { holderUserId: userId, ticketTypeId, isComplimentary: false, status: { in: ['VALID', 'CHECKED_IN'] } } });
      const pending = await tx.orderItem.aggregate({
        _sum: { quantity: true },
        where: { ticketTypeId, order: { userId, status: 'PENDING_PAYMENT', holdExpiresAt: { gt: now } } },
      });
      const already = held + (pending._sum.quantity ?? 0);
      if (already + quantity > t.maxPerOrder) {
        throw new ConflictException({ message: `You already have ${already} ${t.name} ticket(s); the limit is ${t.maxPerOrder} per person`, reasonCode: 'LIMIT' });
      }
      // A checkout made from this buyer's offer and not yet paid or released: its release reopens that offer, so a
      // second active entry can't exist alongside it. (Its own code, not LIMIT: the buyer may be well under the limit.)
      const paying = await tx.waitlistEntry.findFirst({ where: { ticketTypeId, userId, status: 'PURCHASED', order: { status: 'PENDING_PAYMENT' } }, select: { id: true } });
      if (paying) {
        throw new ConflictException({ message: 'Finish or cancel the checkout from your waitlist offer first', reasonCode: 'CHECKOUT_PENDING' });
      }
      if (await tx.waitlistEntry.findFirst({ where: { ticketTypeId, userId, status: { in: [...ACTIVE] } }, select: { id: true } })) {
        throw new ConflictException({ message: 'You are already on this waitlist', reasonCode: 'ALREADY_WAITING' });
      }
      try {
        return (await tx.waitlistEntry.create({ data: { ticketTypeId, userId, quantity } })).id;
      } catch (e) {
        if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') throw new ConflictException({ message: 'You are already on this waitlist', reasonCode: 'ALREADY_WAITING' });
        throw e;
      }
    });
    if (seated) await this.reserveAfterJoin(t.eventId, ticketTypeId);
    return { entryId, position: await this.position(entryId) };
  }

  /**
   * After a seated join commits: a release that read the line just before the join committed may have put seats on
   * sale. Reserve them now (event share → AVAILABLE seats, SKIP LOCKED → recount) rather than at the next sweep.
   */
  private async reserveAfterJoin(eventId: string, ticketTypeId: string) {
    if (!(await this.prisma.eventSeat.count({ where: { ticketTypeId, status: 'AVAILABLE' } }))) return;
    await this.prisma
      .$transaction(async (tx) => {
        await shareLockEvent(tx, eventId);
        if (await reserveAvailableSeats(tx, ticketTypeId)) await this.seating.recountTicketTypes(tx, eventId, [], [ticketTypeId]);
      }, SEATED_TX)
      .catch((e) => this.logger.warn(`waitlist join reserve for ${ticketTypeId}: ${(e as Error).message}`)); // the sweeper retries
  }

  /** 1-based place among the WAITING entries of its type, in (createdAt, id) order; null once offered or done. */
  private async position(entryId: string): Promise<number | null> {
    const [r] = await this.prisma.$queryRaw<{ n: number | null }[]>`
      SELECT CASE WHEN e.status = 'WAITING' THEN (
        SELECT count(*)::int + 1 FROM waitlist_entries w
        WHERE w.ticket_type_id = e.ticket_type_id AND w.status = 'WAITING' AND (w.created_at, w.id) < (e.created_at, e.id)
      ) END AS n
      FROM waitlist_entries e WHERE e.id = ${entryId}::uuid`;
    return r?.n ?? null;
  }

  /** Leaves the line (or gives up a live offer: its stock goes to the next entry at the next sweep). */
  async leave(userId: string, ticketTypeId: string) {
    // Only the entry row: an offer's stock stays in `offered` (or WAITLIST_HOLD) and becomes the pool
    const rows = await this.prisma.$queryRaw<{ id: string }[]>`
      UPDATE waitlist_entries SET status = 'LEFT', updated_at = now()
      WHERE ticket_type_id = ${ticketTypeId}::uuid AND user_id = ${userId}::uuid AND status IN ('WAITING', 'OFFERED')
      RETURNING id`;
    if (!rows.length) throw new NotFoundException({ message: 'You are not on this waitlist', reasonCode: 'NOT_WAITING' });
    return { ok: true };
  }

  /** The buyer's entries: active ones, and those that ended in the last 7 days. */
  async mine(userId: string) {
    const now = new Date();
    const rows = await this.prisma.waitlistEntry.findMany({
      where: { userId, OR: [{ status: { in: [...ACTIVE] } }, { status: { in: ['PURCHASED', 'EXPIRED'] }, updatedAt: { gt: new Date(now.getTime() - 7 * 86400e3) } }] },
      orderBy: { createdAt: 'desc' },
      include: {
        ticketType: { select: { id: true, name: true, nameMy: true, event: { select: { id: true, slug: true, title: true, titleMy: true, startsAt: true } } } },
        seats: { where: { status: 'WAITLIST_HOLD' }, select: { seatKey: true, label: true, labelMy: true }, orderBy: { seatKey: 'asc' } },
      },
      take: 50,
    });
    return Promise.all(
      rows.map(async (e) => {
        const live = e.status === 'OFFERED' && !!e.offerExpiresAt && e.offerExpiresAt > now;
        const status = e.status === 'OFFERED' && !live ? 'EXPIRED' : e.status;
        return {
          id: e.id,
          serverNow: now.toISOString(), // the phone's clock may be off: the app counts the offer down against this
          ticketTypeId: e.ticketTypeId,
          eventId: e.ticketType.event.id,
          status,
          quantity: e.quantity,
          position: e.status === 'WAITING' ? await this.position(e.id) : null,
          offeredQty: live || e.status === 'PURCHASED' ? e.offeredQty : 0,
          offerExpiresAt: live ? e.offerExpiresAt : null,
          seatKeys: live ? e.seats.map((s) => s.seatKey) : [],
          seats: live ? e.seats : [],
          orderId: e.orderId,
          createdAt: e.createdAt,
          event: e.ticketType.event,
          ticketType: { id: e.ticketType.id, name: e.ticketType.name, nameMy: e.ticketType.nameMy },
        };
      }),
    );
  }

  // ───────────── organizer ─────────────

  /** Waitlist size per ticket type of an organizer's event. */
  async eventCounts(organizationId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId }, select: { ticketTypes: { select: { id: true, name: true, nameMy: true }, orderBy: [{ priceMmk: 'asc' }, { id: 'asc' }] } } });
    if (!e) throw new NotFoundException('Event not found');
    const groups = await this.prisma.waitlistEntry.groupBy({
      by: ['ticketTypeId', 'status'],
      where: { ticketTypeId: { in: e.ticketTypes.map((t) => t.id) }, status: { in: [...ACTIVE] } },
      _count: true,
      _sum: { quantity: true, offeredQty: true },
    });
    const g = (id: string, s: string) => groups.find((x) => x.ticketTypeId === id && x.status === s);
    const ticketTypes = e.ticketTypes.map((t) => ({
      id: t.id,
      name: t.name,
      nameMy: t.nameMy,
      waiting: g(t.id, 'WAITING')?._count ?? 0,
      waitingQuantity: g(t.id, 'WAITING')?._sum.quantity ?? 0,
      offered: g(t.id, 'OFFERED')?._count ?? 0,
      offeredQuantity: g(t.id, 'OFFERED')?._sum.offeredQty ?? 0,
    }));
    return { ticketTypes, total: ticketTypes.reduce((s, t) => s + t.waiting + t.offered, 0) };
  }

  // ───────────── sweeper ─────────────

  /**
   * Types the sweeper must look at: stock reserved but not promised to a live offer (to offer it or give it back),
   * or a line with public stock it could take (AVAILABLE seats; a standing type's free quota). A sold-out type with
   * a line and nothing free is left alone, so such types can't crowd out the rest of the batch.
   */
  async typesToOffer(now = new Date()): Promise<string[]> {
    // Open (PUBLISHED) or closed lines (whose reserve must go back); paused ones wait for the event to be published
    const NOT_PAUSED = Prisma.sql`(e.status IN ('PUBLISHED', 'CANCELLED', 'COMPLETED') OR e.starts_at <= ${now} OR tt.sales_end_at <= ${now})`;
    const rows = await this.prisma.$queryRaw<{ id: string }[]>`
      SELECT tt.id::text AS id FROM ticket_types tt JOIN events e ON e.id = tt.event_id
      WHERE ${NOT_PAUSED} AND tt.offered > 0 AND tt.offered > COALESCE((
        SELECT SUM(w.offered_qty) FROM waitlist_entries w WHERE w.ticket_type_id = tt.id AND w.status = 'OFFERED' AND w.offer_expires_at > ${now}
      ), 0)
      UNION
      SELECT tt.id::text FROM ticket_types tt JOIN events e ON e.id = tt.event_id
      WHERE ${NOT_PAUSED} AND EXISTS (SELECT 1 FROM waitlist_entries w WHERE w.ticket_type_id = tt.id AND w.status = 'WAITING')
        AND (
          EXISTS (SELECT 1 FROM event_seats s WHERE s.ticket_type_id = tt.id AND s.status = 'AVAILABLE')
          OR (tt.quota - tt.sold - tt.held - tt.offered > 0 AND NOT EXISTS (SELECT 1 FROM event_seats s WHERE s.ticket_type_id = tt.id))
        )
      ORDER BY 1 LIMIT 500`;
    return rows.map((r) => r.id);
  }

  /**
   * Offers reserved stock to WAITING entries, in line order, type by type (one transaction each), then sends the
   * offers' push and SMS (their inbox notices are stored with the offers). Also gives back stock nobody is waiting for, and reserves public stock a type's line still wants (seats
   * newly free after a join raced a release).
   */
  async assignOffers(now = new Date()) {
    const offers: string[] = [];
    let released = 0;
    for (const id of await this.typesToOffer(now)) {
      try {
        const r = await this.assignType(id, now);
        offers.push(...r.offers);
        released += r.released;
      } catch (e) {
        this.logger.warn(`waitlist offers for ${id}: ${(e as Error).message}`);
      }
    }
    await this.notifyOffers(now); // also offers an earlier pass stored but did not get to send
    return { offered: offers.length, released };
  }

  private async assignType(ticketTypeId: string, now: Date): Promise<{ offers: string[]; released: number }> {
    const none = { offers: [], released: 0 };
    const t = await this.prisma.ticketType.findUnique({
      where: { id: ticketTypeId },
      select: { eventId: true, quota: true, sold: true, held: true, offered: true, salesEndAt: true, event: { select: { status: true, startsAt: true } }, _count: { select: { eventSeats: true } } },
    });
    if (!t) return none;
    const seated = t._count.eventSeats > 0;
    // A closed line (expireOffers ends its entries) gets no new offers; its reserve only goes back. A paused one is
    // left exactly as it is until the event is published again.
    const state = lineState(t, now);
    if (state === 'paused') return none;
    const open = state === 'open';
    // Unlocked look first: most sold-out types with a line have nothing to offer, and must not lock their counters
    const waiting = open ? ((await this.prisma.waitlistEntry.aggregate({ where: { ticketTypeId, status: 'WAITING' }, _sum: { quantity: true } }))._sum.quantity ?? 0) : 0;
    const pool = seated ? await poolSeatCount(this.prisma, ticketTypeId, now) : t.offered - (await liveOfferedQty(this.prisma, ticketTypeId, now));
    const free = seated ? await this.prisma.eventSeat.count({ where: { ticketTypeId, status: 'AVAILABLE' } }) : t.quota - t.sold - t.held - t.offered;
    if (pool <= 0 && (!waiting || free <= 0)) return none;
    if (seated) {
      if (waiting > pool && free > 0) {
        await this.prisma.$transaction(async (tx) => {
          await shareLockEvent(tx, t.eventId);
          if (await reserveAvailableSeats(tx, ticketTypeId, now)) await this.seating.recountTicketTypes(tx, t.eventId, [], [ticketTypeId]);
        }, SEATED_TX);
      }
      return this.prisma.$transaction((tx) => this.assignSeated(tx, t.eventId, ticketTypeId, now, open), SEATED_TX);
    }
    return this.prisma.$transaction((tx) => this.assignStanding(tx, ticketTypeId, now, open));
  }

  private async waitingIn(tx: Tx, ticketTypeId: string, open: boolean): Promise<number> {
    if (!open) return 0;
    const [d] = await tx.$queryRaw<{ n: number }[]>`SELECT COALESCE(SUM(quantity), 0)::int AS n FROM waitlist_entries WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'WAITING'`;
    return d.n;
  }

  /** Standing: counter row → WAITING entries (line order). */
  private async assignStanding(tx: Tx, ticketTypeId: string, now: Date, open: boolean) {
    const [c] = await tx.$queryRaw<{ quota: number; sold: number; held: number; offered: number }[]>`
      SELECT quota, sold, held, offered FROM ticket_types WHERE id = ${ticketTypeId}::uuid FOR NO KEY UPDATE`;
    let pool = c.offered - (await liveOfferedQty(tx, ticketTypeId, now));
    if (pool < 0) {
      // offered below what live offers hold: a counter went wrong somewhere. Never give back (or offer) from it.
      this.logger.warn(`waitlist: negative pool ${pool} for ticket type ${ticketTypeId} (offered ${c.offered})`);
      pool = 0;
    }
    const waiting = await this.waitingIn(tx, ticketTypeId, open);
    // Public stock the line still wants (normally none: freeing paths reserve as they go)
    const add = Math.max(0, Math.min(waiting - pool, c.quota - c.sold - c.held - c.offered));
    pool += add;
    const offers = pool > 0 && waiting > 0 ? await this.offerInOrder(tx, ticketTypeId, pool, now) : [];
    const given = offers.reduce((s, o) => s + o.qty, 0);
    const released = Math.max(0, pool - given); // nobody left waiting for it: back on sale
    if (add || released) await tx.$executeRaw`UPDATE ticket_types SET offered = offered + ${add - released} WHERE id = ${ticketTypeId}::uuid`;
    return { offers: offers.map((o) => o.id), released };
  }

  /** Seated: event (share) → the type's WAITLIST_HOLD seats (seat_key order) → seated counter row → WAITING entries. */
  private async assignSeated(tx: Tx, eventId: string, ticketTypeId: string, now: Date, open: boolean) {
    await shareLockEvent(tx, eventId);
    await tx.$queryRaw`SELECT id FROM event_seats WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'WAITLIST_HOLD' ORDER BY seat_key FOR UPDATE`;
    const pool = await poolSeats(tx, ticketTypeId, now); // a fresh read, after the locks
    const keep = pool.slice(0, Math.max(0, await this.waitingIn(tx, ticketTypeId, open)));
    const extra = pool.slice(keep.length).map((s) => s.id);
    // Seats nobody is waiting for go back on sale (under the current rules)
    const back = extra.length ? await returnSeatsToSale(tx, Prisma.sql`seat.id = ANY(${extra}::uuid[]) AND seat.status = 'WAITLIST_HOLD'`, { reserve: false }) : { typeIds: [] as string[] };
    await this.seating.recountTicketTypes(tx, eventId, back.typeIds, [...new Set([ticketTypeId, ...back.typeIds])]);
    const offers = keep.length ? await this.offerInOrder(tx, ticketTypeId, keep.length, now) : [];
    let i = 0;
    for (const o of offers) {
      const ids = keep.slice(i, i + o.qty).map((s) => s.id);
      i += o.qty;
      await tx.$executeRaw`UPDATE event_seats SET waitlist_entry_id = ${o.id}::uuid WHERE id = ANY(${ids}::uuid[])`;
    }
    return { offers: offers.map((o) => o.id), released: extra.length };
  }

  /** Locks WAITING entries in line order (the last lock) and offers `pool` to them: all they want, or what is left. */
  private async offerInOrder(tx: Tx, ticketTypeId: string, pool: number, now: Date): Promise<{ id: string; qty: number }[]> {
    const entries = await tx.$queryRaw<{ id: string; quantity: number }[]>`
      SELECT id, quantity FROM waitlist_entries WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'WAITING'
      ORDER BY created_at, id LIMIT ${pool} FOR NO KEY UPDATE`;
    const expires = new Date(now.getTime() + OFFER_MINUTES * 60e3);
    const out: { id: string; qty: number }[] = [];
    let left = pool;
    for (const e of entries) {
      if (left <= 0) break;
      const qty = Math.min(e.quantity, left);
      const n = await tx.$executeRaw`
        UPDATE waitlist_entries SET status = 'OFFERED', offered_qty = ${qty}, offered_at = ${now}, offer_expires_at = ${expires}, offer_notified_at = NULL, updated_at = now()
        WHERE id = ${e.id}::uuid AND status = 'WAITING'`;
      if (n !== 1) continue;
      // The inbox notice commits with the offer (a plain insert: no lock that conflicts with the lock order); push and SMS follow
      const row = await tx.waitlistEntry.findUniqueOrThrow({ where: { id: e.id }, include: OFFER_INCLUDE });
      await tx.notification.create({ data: this.notify.inboxRow(row.userId, offerNotice(row, false)) });
      out.push({ id: e.id, qty });
      left -= qty;
    }
    return out;
  }

  /**
   * Ends offers whose time is up (their stock becomes the pool, offered to the next entry by assignOffers), and
   * closes the line of types whose sales ended or whose event started (or is no longer on sale): those entries
   * expire, and people still WAITING get an inbox message.
   */
  async expireOffers(now = new Date()) {
    const closed = await this.prisma.$queryRaw<{ id: string; user_id: string; old: string; ticket_type_id: string; order_id: string | null }[]>`
      WITH c AS (
        SELECT w.id, w.status::text AS old FROM waitlist_entries w
        JOIN ticket_types t ON t.id = w.ticket_type_id JOIN events e ON e.id = t.event_id
        WHERE w.status IN ('WAITING', 'OFFERED') AND (t.sales_end_at <= ${now} OR e.starts_at <= ${now} OR e.status IN ('CANCELLED', 'COMPLETED'))
        ORDER BY w.created_at, w.id
        FOR NO KEY UPDATE OF w
      )
      UPDATE waitlist_entries w SET status = 'EXPIRED', updated_at = now() FROM c
      WHERE w.id = c.id AND w.status IN ('WAITING', 'OFFERED')
      RETURNING w.id::text, w.user_id::text, c.old, w.ticket_type_id::text, w.order_id::text`;
    const expired = await this.prisma.$queryRaw<{ id: string }[]>`
      WITH c AS (
        SELECT id FROM waitlist_entries WHERE status = 'OFFERED' AND offer_expires_at <= ${now}
        ORDER BY created_at, id
        FOR NO KEY UPDATE
      )
      UPDATE waitlist_entries w SET status = 'EXPIRED', updated_at = now() FROM c
      WHERE w.id = c.id AND w.status = 'OFFERED' AND w.offer_expires_at <= ${now}
      RETURNING w.id::text`;
    // People still waiting, and buyers whose reopened offer (OFFERED with the released order) the close ends
    const sorry = closed.filter((c) => c.old === 'WAITING' || (c.old === 'OFFERED' && c.order_id));
    if (sorry.length) await this.notifyClosed(sorry);
    if (expired.length) await this.notifyExpired(expired.map((e) => e.id));
    return { expired: expired.length, closed: closed.length };
  }

  // ───────────── notifications ─────────────

  /**
   * One notice per offer: the inbox row is stored with the offer; this sends push, and SMS when SMS is enabled and
   * "Waitlist SMS" is on. Each live offer not yet sent is claimed first (NULL means "offered by this code, push and SMS pending"; rows from older code or a join carry a time. Never two SMS for one offer; a crash after the
   * claim loses that offer's push and SMS only), then sent. A reopened offer keeps its mark, so it is not sent again.
   */
  private async notifyOffers(now: Date) {
    const rows = await this.prisma.waitlistEntry.findMany({
      where: { status: 'OFFERED', offerNotifiedAt: null, offerExpiresAt: { gt: now } },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      include: OFFER_INCLUDE,
      take: 200,
    });
    if (!rows.length) return;
    const cfg = await this.sms.settingsConfig().catch(() => null);
    const sms = !!cfg?.enabled && cfg.waitlistSms !== false;
    for (const e of rows) {
      try {
        // Expiry is checked again now: the pass may have been slow, and a lapsed offer is not announced
        const claim = await this.prisma.waitlistEntry.updateMany({ where: { id: e.id, status: 'OFFERED', offerNotifiedAt: null, offerExpiresAt: { gt: new Date() } }, data: { offerNotifiedAt: now } });
        if (claim.count !== 1) continue;
        await this.notify.pushAndSms([e.userId], offerNotice(e, sms));
      } catch (err) {
        this.logger.warn(`waitlist offer notice ${e.id}: ${(err as Error).message}`);
      }
    }
  }

  /** Inbox only (no SMS): a reopened offer's tickets are reserved again, until the offer's original expiry. */
  async notifyReopened(entryId: string) {
    const e = await this.prisma.waitlistEntry.findUnique({
      where: { id: entryId },
      include: { ticketType: { select: { event: { select: { id: true, title: true, titleMy: true } } } } },
    });
    if (!e || e.status !== 'OFFERED' || !e.offerExpiresAt) return;
    const ev = e.ticketType.event;
    void this.notify.toUsers([e.userId], {
      kind: 'waitlist_offer_reopened',
      title: 'Your tickets are still reserved',
      titleMy: 'သင့်လက်မှတ်များကို ဆက်လက် ထိန်းထားပါသည်',
      body: `Your tickets for ${ev.title} are still reserved until ${when(e.offerExpiresAt)}.`,
      bodyMy: `${ev.titleMy || ev.title} အတွက် သင့်လက်မှတ်များကို ${when(e.offerExpiresAt, 'my')} အထိ ဆက်လက် ထိန်းထားပါသည်။`,
      link: `/event/${ev.id}`,
      eventId: ev.id,
    });
  }

  /** Where the entry's checkout payment stands: nothing to say (PAID), still in flight, or no payment. */
  private paymentState(e: { order: { status: string; payments: { status: string }[] } | null }): 'paid' | 'in_flight' | 'none' {
    if (!e.order) return 'none';
    if (e.order.status === 'PAID' || e.order.status === 'CONFIRMED') return 'paid';
    return e.order.payments.some((p) => ['INITIATED', 'PENDING', 'EXPIRED'].includes(p.status)) ? 'in_flight' : 'none';
  }

  /** Inbox only (no SMS): the offer's time ran out. */
  private async notifyExpired(entryIds: string[]) {
    const rows = await this.prisma.waitlistEntry.findMany({
      where: { id: { in: entryIds } },
      include: { order: ORDER_PAYMENTS, ticketType: { select: { event: { select: { id: true, title: true, titleMy: true } } } } },
    });
    for (const e of rows) {
      const state = this.paymentState(e);
      if (state === 'paid') continue; // they bought it after all
      const ev = e.ticketType.event;
      void this.notify.toUsers([e.userId], state === 'in_flight' ? releasedWhilePaying(ev) : {
        kind: 'waitlist_offer_expired',
        title: 'Your offer expired',
        titleMy: 'သင့်ကမ်းလှမ်းချက် သက်တမ်းကုန်ပါပြီ',
        body: `Your offer for ${ev.title} expired.`,
        bodyMy: `${ev.titleMy || ev.title} အတွက် သင့်ကမ်းလှမ်းချက် သက်တမ်းကုန်သွားပါပြီ။`,
        link: `/event/${ev.id}`,
        eventId: ev.id,
      });
    }
  }

  private async notifyClosed(entries: { id: string; user_id: string }[]) {
    const rows = await this.prisma.waitlistEntry.findMany({
      where: { id: { in: entries.map((e) => e.id) } },
      include: { order: ORDER_PAYMENTS, ticketType: { select: { name: true, nameMy: true, event: { select: { id: true, title: true, titleMy: true } } } } },
    });
    for (const e of rows) {
      const state = this.paymentState(e);
      if (state === 'paid') continue;
      const ev = e.ticketType.event;
      void this.notify.toUsers([e.userId], state === 'in_flight' ? releasedWhilePaying(ev) : {
        kind: 'waitlist_closed',
        title: "Tickets didn't become available",
        titleMy: 'လက်မှတ် ပြန်မရနိုင်ခဲ့ပါ',
        body: `The waitlist for ${e.ticketType.name} at ${ev.title} has closed. Tickets didn't become available.`,
        bodyMy: `${ev.titleMy || ev.title} ၏ ${e.ticketType.nameMy || e.ticketType.name} စောင့်ဆိုင်းစာရင်း ပိတ်သွားပါပြီ။ လက်မှတ် ပြန်မရနိုင်ခဲ့ပါ။`,
        link: `/event/${ev.id}`,
        eventId: ev.id,
      });
    }
  }
}
