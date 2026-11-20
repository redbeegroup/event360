-- DropIndex
DROP INDEX "notifications_user_id_created_at_idx";

-- AlterTable
ALTER TABLE "events" ADD COLUMN     "sales_milestone" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "notifications" ADD COLUMN     "audience" TEXT NOT NULL DEFAULT 'attendee';

-- CreateIndex
CREATE INDEX "notifications_user_id_audience_created_at_idx" ON "notifications"("user_id", "audience", "created_at");

