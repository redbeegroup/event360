-- CreateTable
CREATE TABLE "ticket_price_steps" (
    "id" UUID NOT NULL,
    "ticket_type_id" UUID NOT NULL,
    "starts_at" TIMESTAMP(3) NOT NULL,
    "price_mmk" BIGINT NOT NULL,

    CONSTRAINT "ticket_price_steps_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ticket_price_steps_ticket_type_id_starts_at_key" ON "ticket_price_steps"("ticket_type_id", "starts_at");

-- AddForeignKey
ALTER TABLE "ticket_price_steps" ADD CONSTRAINT "ticket_price_steps_ticket_type_id_fkey" FOREIGN KEY ("ticket_type_id") REFERENCES "ticket_types"("id") ON DELETE CASCADE ON UPDATE CASCADE;

