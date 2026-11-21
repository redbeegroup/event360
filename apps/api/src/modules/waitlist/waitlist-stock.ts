import { Prisma } from '@prisma/client';
import { CURRENT_RULE_TYPE } from '../seating/seat-rules';

/**
 * Stock reserved for a ticket type's waitlist, inside the caller's transaction. No Nest dependencies, so every
 * path that frees stock (payments, tickets, guests, events, seat-claims) can call these directly.
 *
 * Model: `ticket_types.offered` is all stock held back from the public for the line. Part of it is promised to
 * live offers (entries OFFERED with offer_expires_at in the future, `offered_qty` each); the rest is the type's
 * unassigned "pool", which WaitlistService.assignOffers hands to WAITING entries in line order (or gives back to
 * the public once nobody is waiting). Standing types keep `offered` as a counter; seated types keep it as the
 * count of their WAITLIST_HOLD seats (EventSeatsService.recountTicketTypes), and a pool seat is a WAITLIST_HOLD seat
 * whose waitlist_entry_id is NULL or names an entry whose offer is no longer live.
 *
 * Locks: these read waitlist_entries without locking them (entries come last in the lock order and are locked only
 * by the waitlist's own steps). Reading a slightly stale line can only over-reserve, never hand stock to two
 * buyers: an over-reserved pool goes back to the public at the next sweep.
 */
type Tx = Prisma.TransactionClient;

export const OFFER_MINUTES = 30;

/** Quantity WAITING in line for a type. */
async function waitingQty(tx: Tx, ticketTypeId: string): Promise<number> {
  const [r] = await tx.$queryRaw<{ n: number }[]>`
    SELECT COALESCE(SUM(quantity), 0)::int AS n FROM waitlist_entries WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'WAITING'`;
  return r.n;
}

/** Quantity promised to live offers of a type at `now`. */
export async function liveOfferedQty(tx: Tx, ticketTypeId: string, now: Date): Promise<number> {
  const [r] = await tx.$queryRaw<{ n: number }[]>`
    SELECT COALESCE(SUM(offered_qty), 0)::int AS n FROM waitlist_entries
    WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'OFFERED' AND offer_expires_at > ${now}`;
  return r.n;
}

/**
 * Standing types: called right after a path freed `qty` of a type, while it still holds that type's row lock (it
 * just updated the counters). Moves up to the WAITING demand not yet covered by the pool into `offered`, so the
 * public never sees it. Returns the quantity moved (0 when nobody is waiting: the stock is back on sale as before).
 */
export async function reserveFreed(tx: Tx, ticketTypeId: string, qty: number, now = new Date()): Promise<number> {
  if (qty <= 0) return 0;
  const waiting = await waitingQty(tx, ticketTypeId);
  if (!waiting) return 0;
  // Already locked by the caller; taken again (a no-op) so the counters read here are the ones we update
  const [t] = await tx.$queryRaw<{ quota: number; sold: number; held: number; offered: number }[]>`
    SELECT quota, sold, held, offered FROM ticket_types WHERE id = ${ticketTypeId}::uuid FOR NO KEY UPDATE`;
  if (!t) return 0;
  const pool = t.offered - (await liveOfferedQty(tx, ticketTypeId, now));
  const free = t.quota - t.sold - t.held - t.offered;
  const m = Math.max(0, Math.min(qty, waiting - pool, free));
  if (m > 0) await tx.$executeRaw`UPDATE ticket_types SET offered = offered + ${m} WHERE id = ${ticketTypeId}::uuid`;
  return m;
}

/** Pool seats of a seated type: WAITLIST_HOLD and not promised to a live offer. */
const POOL_SEAT = (now: Date) => Prisma.sql`s.status = 'WAITLIST_HOLD' AND NOT EXISTS (
  SELECT 1 FROM waitlist_entries w WHERE w.id = s.waitlist_entry_id AND w.status = 'OFFERED' AND w.offer_expires_at > ${now})`;

export async function poolSeatCount(tx: Tx, ticketTypeId: string, now: Date): Promise<number> {
  const [r] = await tx.$queryRaw<{ n: number }[]>`SELECT count(*)::int AS n FROM event_seats s WHERE s.ticket_type_id = ${ticketTypeId}::uuid AND ${POOL_SEAT(now)}`;
  return r.n;
}

/** Pool seat ids of a type in seat_key order (the caller holds their locks). */
export async function poolSeats(tx: Tx, ticketTypeId: string, now: Date): Promise<{ id: string; seat_key: string }[]> {
  return tx.$queryRaw`SELECT s.id, s.seat_key FROM event_seats s WHERE s.ticket_type_id = ${ticketTypeId}::uuid AND ${POOL_SEAT(now)} ORDER BY s.seat_key`;
}

/**
 * Seated types: called by returnSeatsToSale with the seats it has locked and is about to put back on sale. For
 * each ticket type the current rules give those seats, keeps up to the WAITING demand not covered by the pool as
 * unassigned WAITLIST_HOLD seats (in seat_key order). Returns the ids kept; the caller puts the rest on sale and
 * recounts the types (WAITLIST_HOLD counts as `offered`).
 */
export async function reserveFreedSeats(tx: Tx, seatIds: string[], now = new Date()): Promise<string[]> {
  if (!seatIds.length) return [];
  const rows = await tx.$queryRaw<{ id: string; new_type: string | null }[]>`
    SELECT seat.id, ${CURRENT_RULE_TYPE}::text AS new_type FROM event_seats seat WHERE seat.id = ANY(${seatIds}::uuid[]) ORDER BY seat.seat_key`;
  const byType = new Map<string, string[]>();
  for (const r of rows) if (r.new_type) byType.set(r.new_type, [...(byType.get(r.new_type) ?? []), r.id]);
  const keep: { id: string; type: string }[] = [];
  for (const [type, ids] of byType) {
    const waiting = await waitingQty(tx, type);
    if (!waiting) continue;
    const need = waiting - (await poolSeatCount(tx, type, now));
    for (const id of ids.slice(0, Math.max(0, need))) keep.push({ id, type });
  }
  if (!keep.length) return [];
  await tx.$executeRaw`
    UPDATE event_seats s SET status = 'WAITLIST_HOLD', ticket_type_id = v.type, order_id = NULL, ticket_id = NULL, held_until = NULL,
      hold_label = NULL, waitlist_entry_id = NULL
    FROM unnest(${keep.map((k) => k.id)}::uuid[], ${keep.map((k) => k.type)}::uuid[]) AS v(id, type)
    WHERE s.id = v.id`;
  return keep.map((k) => k.id);
}

/**
 * Seated types: AVAILABLE seats of a type become pool seats while the line wants more than the pool holds (seats
 * newly assigned to a sold-out type, or a join that raced a release). The caller holds the event row lock; locks
 * the seats in seat_key order (SKIP LOCKED: seats a checkout is claiming are left to it) and returns how many it
 * took. The caller recounts the type.
 */
export async function reserveAvailableSeats(tx: Tx, ticketTypeId: string, now = new Date()): Promise<number> {
  const waiting = await waitingQty(tx, ticketTypeId);
  if (!waiting) return 0;
  const need = waiting - (await poolSeatCount(tx, ticketTypeId, now));
  if (need <= 0) return 0;
  const rows = await tx.$queryRaw<{ id: string }[]>`
    UPDATE event_seats SET status = 'WAITLIST_HOLD', waitlist_entry_id = NULL
    WHERE id IN (
      SELECT id FROM event_seats WHERE ticket_type_id = ${ticketTypeId}::uuid AND status = 'AVAILABLE'
      ORDER BY seat_key LIMIT ${need} FOR UPDATE SKIP LOCKED
    ) AND status = 'AVAILABLE'
    RETURNING id`;
  return rows.length;
}
