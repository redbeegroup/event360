-- Rows made before this point were announced by older code: mark them as notified so they are not sent again.
UPDATE "waitlist_entries" SET "offer_notified_at" = COALESCE("offered_at", "created_at", now()) WHERE "offer_notified_at" IS NULL;

-- NULL now means "offered by the current code, push and SMS pending"; every other insert is already notified.
ALTER TABLE "waitlist_entries" ALTER COLUMN "offer_notified_at" SET DEFAULT now();
