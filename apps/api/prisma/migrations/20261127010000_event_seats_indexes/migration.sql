-- Seat lookups by ticket type (seated checks, recounts) and by order (release, refund, settle).
-- event_seats is small, so a plain (non-concurrent) build is fine inside the migration transaction.

-- CreateIndex
CREATE INDEX IF NOT EXISTS "event_seats_ticket_type_id_idx" ON "event_seats"("ticket_type_id");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "event_seats_order_id_idx" ON "event_seats"("order_id");
