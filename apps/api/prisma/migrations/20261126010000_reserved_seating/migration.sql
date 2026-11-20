-- CreateEnum
CREATE TYPE "SeatStatus" AS ENUM ('AVAILABLE', 'CHECKOUT_HOLD', 'GUEST_HOLD', 'SOLD', 'UNSOLD');

-- AlterTable
ALTER TABLE "events" ADD COLUMN     "seat_map_version_id" UUID;

-- AlterTable
ALTER TABLE "ticket_types" ADD COLUMN     "color" TEXT;

-- AlterTable
ALTER TABLE "tickets" ADD COLUMN     "comp_label" TEXT,
ADD COLUMN     "guest_name" TEXT,
ADD COLUMN     "is_complimentary" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "seat_key" TEXT,
ADD COLUMN     "seat_label" TEXT;

-- CreateTable
CREATE TABLE "seat_maps" (
    "id" UUID NOT NULL,
    "venue_name" TEXT NOT NULL,
    "venue_name_my" TEXT,
    "city" TEXT NOT NULL,
    "address" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "map_url" TEXT,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "seat_maps_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "seat_map_versions" (
    "id" UUID NOT NULL,
    "seat_map_id" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "layout" JSONB NOT NULL,
    "seat_count" INTEGER NOT NULL,
    "created_by_id" UUID NOT NULL,
    "published_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "seat_map_versions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_sections" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "section_key" TEXT NOT NULL,
    "row_label" TEXT,
    "ticket_type_id" UUID NOT NULL,

    CONSTRAINT "event_sections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_seats" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "seat_key" TEXT NOT NULL,
    "section_key" TEXT NOT NULL,
    "row_label" TEXT NOT NULL,
    "seat_label" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "ticket_type_id" UUID,
    "status" "SeatStatus" NOT NULL DEFAULT 'UNSOLD',
    "order_id" UUID,
    "ticket_id" UUID,
    "hold_label" TEXT,
    "held_until" TIMESTAMP(3),

    CONSTRAINT "event_seats_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "seat_map_versions_seat_map_id_version_key" ON "seat_map_versions"("seat_map_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "event_sections_event_id_section_key_row_label_key" ON "event_sections"("event_id", "section_key", "row_label");

-- CreateIndex
CREATE UNIQUE INDEX "event_seats_ticket_id_key" ON "event_seats"("ticket_id");

-- CreateIndex
CREATE INDEX "event_seats_event_id_status_idx" ON "event_seats"("event_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "event_seats_event_id_seat_key_key" ON "event_seats"("event_id", "seat_key");

-- AddForeignKey
ALTER TABLE "events" ADD CONSTRAINT "events_seat_map_version_id_fkey" FOREIGN KEY ("seat_map_version_id") REFERENCES "seat_map_versions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seat_map_versions" ADD CONSTRAINT "seat_map_versions_seat_map_id_fkey" FOREIGN KEY ("seat_map_id") REFERENCES "seat_maps"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seat_map_versions" ADD CONSTRAINT "seat_map_versions_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_sections" ADD CONSTRAINT "event_sections_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_sections" ADD CONSTRAINT "event_sections_ticket_type_id_fkey" FOREIGN KEY ("ticket_type_id") REFERENCES "ticket_types"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_seats" ADD CONSTRAINT "event_seats_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_seats" ADD CONSTRAINT "event_seats_ticket_type_id_fkey" FOREIGN KEY ("ticket_type_id") REFERENCES "ticket_types"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_seats" ADD CONSTRAINT "event_seats_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "tickets"("id") ON DELETE SET NULL ON UPDATE CASCADE;

