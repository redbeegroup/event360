-- CreateEnum
CREATE TYPE "CheckinMethod" AS ENUM ('QR', 'MANUAL');

-- AlterTable
ALTER TABLE "checkins" ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "crew_session_id" UUID,
ADD COLUMN     "event_id" UUID NOT NULL,
ADD COLUMN     "method" "CheckinMethod" NOT NULL DEFAULT 'QR',
ADD COLUMN     "undone_at" TIMESTAMP(3),
ADD COLUMN     "undone_by" TEXT,
ALTER COLUMN "crew_user_id" DROP NOT NULL;

-- CreateTable
CREATE TABLE "event_access_codes" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "code_hash" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "gate" TEXT,
    "created_by_id" UUID NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "event_access_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crew_sessions" (
    "id" UUID NOT NULL,
    "access_code_id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "device_name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "crew_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "event_access_codes_code_hash_key" ON "event_access_codes"("code_hash");

-- CreateIndex
CREATE INDEX "event_access_codes_event_id_idx" ON "event_access_codes"("event_id");

-- CreateIndex
CREATE INDEX "crew_sessions_event_id_idx" ON "crew_sessions"("event_id");

-- CreateIndex
CREATE INDEX "checkins_event_id_scanned_at_idx" ON "checkins"("event_id", "scanned_at");

-- AddForeignKey
ALTER TABLE "checkins" ADD CONSTRAINT "checkins_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checkins" ADD CONSTRAINT "checkins_crew_user_id_fkey" FOREIGN KEY ("crew_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "checkins" ADD CONSTRAINT "checkins_crew_session_id_fkey" FOREIGN KEY ("crew_session_id") REFERENCES "crew_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_access_codes" ADD CONSTRAINT "event_access_codes_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crew_sessions" ADD CONSTRAINT "crew_sessions_access_code_id_fkey" FOREIGN KEY ("access_code_id") REFERENCES "event_access_codes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

