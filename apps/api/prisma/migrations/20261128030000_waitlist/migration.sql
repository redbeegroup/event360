-- CreateEnum
CREATE TYPE "WaitlistStatus" AS ENUM ('WAITING', 'OFFERED', 'PURCHASED', 'EXPIRED', 'LEFT');

-- AlterEnum
ALTER TYPE "SeatStatus" ADD VALUE 'WAITLIST_HOLD';

-- AlterTable
ALTER TABLE "event_seats" ADD COLUMN     "waitlist_entry_id" UUID;

-- AlterTable
ALTER TABLE "ticket_types" ADD COLUMN     "offered" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "waitlist_entries" (
    "id" UUID NOT NULL,
    "ticket_type_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "status" "WaitlistStatus" NOT NULL DEFAULT 'WAITING',
    "offered_qty" INTEGER NOT NULL DEFAULT 0,
    "offered_at" TIMESTAMP(3),
    "offer_expires_at" TIMESTAMP(3),
    "order_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "waitlist_entries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "waitlist_entries_ticket_type_id_status_created_at_idx" ON "waitlist_entries"("ticket_type_id", "status", "created_at");

-- CreateIndex
CREATE INDEX "waitlist_entries_user_id_status_idx" ON "waitlist_entries"("user_id", "status");

-- CreateIndex
CREATE INDEX "waitlist_entries_status_offer_expires_at_idx" ON "waitlist_entries"("status", "offer_expires_at");

-- AddForeignKey
ALTER TABLE "event_seats" ADD CONSTRAINT "event_seats_waitlist_entry_id_fkey" FOREIGN KEY ("waitlist_entry_id") REFERENCES "waitlist_entries"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "waitlist_entries" ADD CONSTRAINT "waitlist_entries_ticket_type_id_fkey" FOREIGN KEY ("ticket_type_id") REFERENCES "ticket_types"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "waitlist_entries" ADD CONSTRAINT "waitlist_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "waitlist_entries" ADD CONSTRAINT "waitlist_entries_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE SET NULL ON UPDATE CASCADE;


-- One active (WAITING or OFFERED) entry per user and ticket type (not expressible in the Prisma schema)
CREATE UNIQUE INDEX "waitlist_entries_active_key" ON "waitlist_entries" ("ticket_type_id", "user_id") WHERE "status" IN ('WAITING', 'OFFERED');
