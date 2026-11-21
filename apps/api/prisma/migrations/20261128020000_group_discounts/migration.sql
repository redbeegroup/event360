-- AlterTable
ALTER TABLE "orders" ADD COLUMN     "group_discount_bp" INTEGER;

-- CreateTable
CREATE TABLE "group_discounts" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "min_quantity" INTEGER NOT NULL,
    "percent_bp" INTEGER NOT NULL,

    CONSTRAINT "group_discounts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "group_discounts_event_id_min_quantity_key" ON "group_discounts"("event_id", "min_quantity");

-- AddForeignKey
ALTER TABLE "group_discounts" ADD CONSTRAINT "group_discounts_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

