-- CreateEnum
CREATE TYPE "PromoKind" AS ENUM ('PERCENT', 'FIXED');

-- AlterTable
ALTER TABLE "events" ADD COLUMN     "transfer_cutoff_hours" INTEGER NOT NULL DEFAULT 2,
ADD COLUMN     "transfers_enabled" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "discount_mmk" BIGINT NOT NULL DEFAULT 0,
ADD COLUMN     "promo_code_id" UUID;

-- AlterTable
ALTER TABLE "tickets" ADD COLUMN     "transfer_count" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "promo_codes" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "kind" "PromoKind" NOT NULL,
    "value" INTEGER NOT NULL,
    "max_uses" INTEGER,
    "used" INTEGER NOT NULL DEFAULT 0,
    "starts_at" TIMESTAMP(3),
    "ends_at" TIMESTAMP(3),
    "ticket_type_ids" UUID[] DEFAULT ARRAY[]::UUID[],
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_by_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "promo_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ticket_transfers" (
    "id" UUID NOT NULL,
    "ticket_id" UUID NOT NULL,
    "from_user_id" UUID NOT NULL,
    "to_user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ticket_transfers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_daily_stats" (
    "event_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "views" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "event_daily_stats_pkey" PRIMARY KEY ("event_id","day")
);

-- CreateIndex
CREATE UNIQUE INDEX "promo_codes_event_id_code_key" ON "promo_codes"("event_id", "code");

-- CreateIndex
CREATE INDEX "ticket_transfers_ticket_id_idx" ON "ticket_transfers"("ticket_id");

-- AddForeignKey
ALTER TABLE "orders" ADD CONSTRAINT "orders_promo_code_id_fkey" FOREIGN KEY ("promo_code_id") REFERENCES "promo_codes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "promo_codes" ADD CONSTRAINT "promo_codes_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ticket_transfers" ADD CONSTRAINT "ticket_transfers_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "tickets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_daily_stats" ADD CONSTRAINT "event_daily_stats_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

