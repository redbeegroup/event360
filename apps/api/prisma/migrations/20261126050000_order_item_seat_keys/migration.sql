-- AlterTable
ALTER TABLE "order_items" ADD COLUMN     "seat_keys" TEXT[] DEFAULT ARRAY[]::TEXT[];

