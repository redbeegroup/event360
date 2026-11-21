import { Prisma } from '@prisma/client';
import type { EventSeat } from '@prisma/client';
import { reserveFreedSeats } from '../waitlist/waitlist-stock';
import { CURRENT_RULE_TYPE } from './seat-rules';

export { CURRENT_RULE_TYPE } from './seat-rules';

/**
 * Seat state changes for checkout. Every function runs inside the caller's transaction, which must already hold
 * the event row share lock (shareLockEvent) so it excludes assignment and map changes (they take FOR UPDATE),
 * and must call EventSeatsService.recountTicketTypes (for the order's seated types, plus any types a seat going
 * back on sale left or joined) afterwards.
 *
 * Checkouts run in parallel with each other. Lock order, the same in every path, so they cannot deadlock:
 * 1. user row: createOrder (the buyer), GuestsService.issue (the guest);
 * 2. event row: shared by checkouts and the waitlist sweeper (never upgraded), FOR UPDATE by organizer seat/map changes;
 * 3. payment row: settle (its conditional status update);
 * 4. order row: settle (SELECT … FOR UPDATE), releaseHold and refundOrder (conditional status update);
 * 5. ticket rows: TicketsService.cancel and GuestsService.revoke (conditional VOID);
 * 6. standing ticket_types rows, in id order (FOR NO KEY UPDATE or a conditional UPDATE). A path that frees standing
 *    stock calls reserveFreed (waitlist-stock.ts) while it holds the row, and the organizer quota edit and the
 *    waitlist join and sweeper (assignOffers) take it here too;
 * 7. promo_codes row (orders with a code; TicketsService.cancel locks it FOR UPDATE here);
 * 8. seat rows: claims lock them in seat_key order; the other functions only touch seats the order already owns.
 *    returnSeatsToSale locks its seats, then reserveFreedSeats keeps some as WAITLIST_HOLD for the line; the
 *    waitlist sweeper locks a type's WAITLIST_HOLD seats in seat_key order;
 * 9. seated ticket_types rows, in id order, in the recount (the waitlist join takes a seated type's row here);
 * 10. waitlist_entries rows, in (created_at, id) order, always last: createOrder marks the offer it used PURCHASED
 *    (conditional update); the sweeper locks WAITING entries to offer them, or OFFERED ones to expire them; leave.
 *    Freeing paths only read entries (an unlocked read can only over-reserve; the sweeper gives the excess back).
 * Two exceptions, both safe:
 * - TicketsService.cancel takes its (free) order's row last, after the recount, only to serialise cancels within
 *   that order; no other path holds a free order's row while waiting for a counter or seat.
 * - GuestsService.revoke takes the comp order's row after the ticket and seat rows; it holds the event row
 *   FOR UPDATE first, which serialises it against every other seat path of that event.
 */
type Tx = Prisma.TransactionClient;

/** A seated on-sale rush queues for pool connections and for the seated types' counter rows: wait, don't fail. */
export const SEATED_TX = { maxWait: 10_000, timeout: 15_000 };

/** Shared lock on the event row: checkouts don't block each other, but wait for (and block) assignment and map changes. */
export async function shareLockEvent(tx: Tx, eventId: string): Promise<void> {
  await tx.$queryRaw`SELECT id FROM events WHERE id = ${eventId}::uuid FOR SHARE`;
}

/**
 * Takes all the seats or none: one conditional UPDATE that only changes seats that are still AVAILABLE. Its
 * subquery locks the rows in seat_key order, so two claims over overlapping seats queue instead of deadlocking;
 * a claim that waited re-checks the status after the other commits and leaves out a seat that was taken.
 * When some are missing from the result the caller must give back what was taken (throwing rolls back the
 * transaction; settle uses unclaimSeats). `final` sells them at once (free orders, late payments).
 * With `waitlistEntryId` (an offer the caller has checked belongs to the buyer) that entry's WAITLIST_HOLD seats can
 * be claimed too; every other WAITLIST_HOLD seat is taken, as for the public.
 */
export async function claimSeats(
  tx: Tx,
  eventId: string,
  seatKeys: string[],
  orderId: string,
  heldUntil: Date | null,
  final: boolean,
  waitlistEntryId: string | null = null,
): Promise<{ ok: true; seats: EventSeat[] } | { ok: false; taken: string[]; seats: EventSeat[] }> {
  const status = final ? 'SOLD' : 'CHECKOUT_HOLD';
  const free = Prisma.sql`(status = 'AVAILABLE' OR (status = 'WAITLIST_HOLD' AND waitlist_entry_id = ${waitlistEntryId}::uuid))`;
  const rows = await tx.$queryRaw<{ id: string }[]>`
    UPDATE event_seats SET status = ${status}::"SeatStatus", order_id = ${orderId}::uuid, held_until = ${heldUntil}, waitlist_entry_id = NULL
    WHERE id IN (
      SELECT id FROM event_seats
      WHERE event_id = ${eventId}::uuid AND seat_key = ANY(${seatKeys}::text[]) AND ${free}
      ORDER BY seat_key
      FOR UPDATE
    ) AND ${free}
    RETURNING id`;
  const seats = await tx.eventSeat.findMany({ where: { id: { in: rows.map((r) => r.id) } } });
  if (seats.length === new Set(seatKeys).size) return { ok: true, seats };
  const got = new Set(seats.map((s) => s.seatKey));
  return { ok: false, taken: seatKeys.filter((k) => !got.has(k)), seats };
}

/** Undo a partial claim inside a transaction that will still commit (seats were AVAILABLE just before). */
export async function unclaimSeats(tx: Tx, seatIds: string[]): Promise<void> {
  if (!seatIds.length) return;
  await tx.$executeRaw`UPDATE event_seats SET status = 'AVAILABLE', order_id = NULL, held_until = NULL WHERE id = ANY(${seatIds}::uuid[]) AND ticket_id IS NULL`;
}

/** What returnSeatsToSale changed: the seats, and every ticket type they left or joined (recount all of them). */
export interface ReturnedSeats {
  seatKeys: string[];
  typeIds: string[];
}

/**
 * Seats matching `where` (a condition on event_seats columns aliased `seat`; include the expected status) go back on
 * sale under the event's current assignment rules, which may have changed while they were held or sold: a row rule
 * wins over a whole-section rule, and with no rule the seat is UNSOLD with no type. Locks the seats in seat_key order.
 * While people are waiting for a seat's (new) type, reserveFreedSeats keeps it for them as WAITLIST_HOLD instead
 * (`reserve: false` skips that: the waitlist sweeper giving back seats nobody is waiting for).
 * The caller must hold the event row lock (shared or exclusive) so the rules can't change meanwhile, and must then
 * recount `typeIds` (the old and the new types) with EventSeatsService.recountTicketTypes(tx, eventId, typeIds, ...),
 * which locks those ticket_types rows in id order, after the seats.
 */
export async function returnSeatsToSale(tx: Tx, where: Prisma.Sql, opts: { reserve?: boolean } = {}): Promise<ReturnedSeats> {
  const locked = await tx.$queryRaw<{ id: string; seat_key: string; old_type: string | null; new_type: string | null }[]>`
    SELECT seat.id, seat.seat_key, seat.ticket_type_id::text AS old_type, ${CURRENT_RULE_TYPE}::text AS new_type
    FROM event_seats seat
    WHERE ${where}
    ORDER BY seat.seat_key
    FOR UPDATE OF seat`;
  if (!locked.length) return { seatKeys: [], typeIds: [] };
  const kept = new Set(opts.reserve === false ? [] : await reserveFreedSeats(tx, locked.map((r) => r.id)));
  const onSale = locked.filter((r) => !kept.has(r.id)).map((r) => r.id);
  if (onSale.length) {
    await tx.$executeRaw`
      UPDATE event_seats seat SET
        ticket_type_id = ${CURRENT_RULE_TYPE},
        status = CASE WHEN ${CURRENT_RULE_TYPE} IS NULL THEN 'UNSOLD'::"SeatStatus" ELSE 'AVAILABLE'::"SeatStatus" END,
        order_id = NULL, ticket_id = NULL, held_until = NULL, hold_label = NULL, waitlist_entry_id = NULL
      WHERE seat.id = ANY(${onSale}::uuid[])`;
  }
  const types = new Set<string>();
  for (const r of locked) for (const t of [r.old_type, r.new_type]) if (t) types.add(t);
  return { seatKeys: locked.map((r) => r.seat_key), typeIds: [...types] };
}

/** Hold expired or cancelled: the order's CHECKOUT_HOLD seats go back on sale (under the current rules). */
export async function releaseSeats(tx: Tx, orderId: string): Promise<ReturnedSeats> {
  return returnSeatsToSale(tx, Prisma.sql`order_id = ${orderId}::uuid AND status = 'CHECKOUT_HOLD'`);
}

/**
 * The order's held (or already sold, for final claims) seats become SOLD with their ticket. Throws if any seat
 * is not this order's: that would mean a seat changed hands, and the whole transaction must roll back.
 */
export async function sellSeats(tx: Tx, orderId: string, ticketIdsBySeat: Map<string, string>): Promise<void> {
  if (!ticketIdsBySeat.size) return;
  const keys = [...ticketIdsBySeat.keys()];
  const ids = keys.map((k) => ticketIdsBySeat.get(k)!);
  const n = await tx.$executeRaw`
    UPDATE event_seats s SET status = 'SOLD', ticket_id = v.ticket_id, held_until = NULL
    FROM unnest(${keys}::text[], ${ids}::uuid[]) AS v(seat_key, ticket_id)
    WHERE s.order_id = ${orderId}::uuid AND s.seat_key = v.seat_key AND s.status IN ('CHECKOUT_HOLD', 'SOLD') AND s.ticket_id IS NULL`;
  if (n !== keys.length) throw new Error(`sellSeats: order ${orderId} holds ${n} of ${keys.length} seats`);
}

/** Admin refund: the order's sold seats go back on sale (under the current rules). */
export async function refundSeats(tx: Tx, orderId: string): Promise<ReturnedSeats> {
  return returnSeatsToSale(tx, Prisma.sql`order_id = ${orderId}::uuid AND status = 'SOLD'`);
}
