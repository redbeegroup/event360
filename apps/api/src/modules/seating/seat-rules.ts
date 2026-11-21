import { Prisma } from '@prisma/client';

/**
 * The ticket type the event's current assignment rules give a seat: a row rule wins over a whole-section rule,
 * NULL with no rule. A scalar subquery over the seat row aliased `seat` (an event_seats row) in the outer statement.
 * (Its own module so the waitlist's seat functions can use it without importing seat-claims.)
 */
export const CURRENT_RULE_TYPE = Prisma.sql`(SELECT r.ticket_type_id FROM event_sections r
  WHERE r.event_id = seat.event_id AND r.section_key = seat.section_key AND (r.row_label = seat.row_label OR r.row_label IS NULL)
  ORDER BY r.row_label IS NULL LIMIT 1)`;
