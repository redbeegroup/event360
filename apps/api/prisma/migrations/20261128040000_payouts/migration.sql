-- CreateEnum
CREATE TYPE "PayoutMethod" AS ENUM ('BANK', 'KBZPAY', 'WAVEPAY', 'CASH', 'OTHER');

-- CreateTable
CREATE TABLE "payouts" (
    "id" UUID NOT NULL,
    "organization_id" UUID NOT NULL,
    "amount_mmk" BIGINT NOT NULL,
    "paid_at" TIMESTAMP(3) NOT NULL,
    "method" "PayoutMethod" NOT NULL,
    "reference" TEXT,
    "note" TEXT,
    "created_by_id" UUID NOT NULL,
    "voided_at" TIMESTAMP(3),
    "void_reason" TEXT,
    "voided_by_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payouts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "payouts_organization_id_paid_at_idx" ON "payouts"("organization_id", "paid_at");

