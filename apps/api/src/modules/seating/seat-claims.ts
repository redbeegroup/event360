import type { EventSeat, Prisma } from '@prisma/client';

/**
 * Seat state changes for checkout. Every function runs inside the caller's transaction, which must already hold
 * the event row lock (lockEventRow) so claims serialise with assignment and map changes, and must call
 * EventSeatsService.recountTicketTypes afterwards.
 */
type Tx = Prisma.TransactionClient;

/** Row-level lock on the event: the same lock seat assignments and map changes take. */
export async function lockEventRow(tx: Tx, eventId: string): Promise<void> {
  await tx.$queryRaw`SELECT id FROM events WHERE id = ${eventId}::uuid FOR UPDATE`;
}

/**
 * Takes all the seats or none: one conditional UPDATE that only changes seats that are still AVAILABLE.
 * When some are missing from the result the caller must give back what was taken (throwing rolls back the
 * transaction; settle uses unclaimSeats). `final` sells them at once (free orders, late payments).
 */
export async function claimSeats(
  tx: Tx,
  eventId: string,
  seatKeys: string[],
  orderId: string,
  heldUntil: Date | null,
  final: boolean,
): Promise<{ ok: true; seats: EventSeat[] } | { ok: false; taken: string[]; seats: EventSeat[] }> {
  const status = final ? 'SOLD' : 'CHECKOUT_HOLD';
  const rows = await tx.$queryRaw<{ id: string }[]>`
    UPDATE event_seats SET status = ${status}::"SeatStatus", order_id = ${orderId}::uuid, held_until = ${heldUntil}
    WHERE event_id = ${eventId}::uuid AND seat_key = ANY(${seatKeys}::text[]) AND status = 'AVAILABLE'
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

/** Hold expired or cancelled: the order's CHECKOUT_HOLD seats go back on sale. */
export async function releaseSeats(tx: Tx, orderId: string, to: 'AVAILABLE'): Promise<number> {
  return tx.$executeRaw`
    UPDATE event_seats SET status = ${to}::"SeatStatus", order_id = NULL, held_until = NULL
    WHERE order_id = ${orderId}::uuid AND status = 'CHECKOUT_HOLD'`;
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

/** Admin refund: the order's sold seats go back on sale. */
export async function refundSeats(tx: Tx, orderId: string): Promise<number> {
  return tx.$executeRaw`
    UPDATE event_seats SET status = 'AVAILABLE', order_id = NULL, ticket_id = NULL, held_until = NULL
    WHERE order_id = ${orderId}::uuid AND status = 'SOLD'`;
}
