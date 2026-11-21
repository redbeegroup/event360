-- Seats offered to a waitlist entry (GET /me/waitlist, ON DELETE SET NULL from waitlist_entries). Partial: almost
-- every seat has no entry. Prisma's schema can't express the predicate; it sees the plain index it declares.
CREATE INDEX "event_seats_waitlist_entry_id_idx" ON "event_seats"("waitlist_entry_id") WHERE "waitlist_entry_id" IS NOT NULL;
