-- AlterTable
ALTER TABLE "live_channels" DROP COLUMN "s3_prefix",
ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "ended_at" TIMESTAMP(3),
ADD COLUMN     "event_id" UUID NOT NULL,
ADD COLUMN     "ingest_key" TEXT NOT NULL,
ADD COLUMN     "job_name" TEXT,
ADD COLUMN     "live_prefix" TEXT,
ADD COLUMN     "peak_viewers" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "recording_enabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "srs_client_id" TEXT,
ADD COLUMN     "started_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "vod_assets" ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "error" TEXT,
ADD COLUMN     "event_id" UUID NOT NULL,
ADD COLUMN     "job_name" TEXT,
ADD COLUMN     "published" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "renditions" JSONB,
ADD COLUMN     "session_id" UUID,
ADD COLUMN     "size_bytes" BIGINT,
ADD COLUMN     "source" TEXT NOT NULL DEFAULT 'LIVE',
ADD COLUMN     "title_my" TEXT,
ADD COLUMN     "updated_at" TIMESTAMP(3) NOT NULL;

-- CreateTable
CREATE TABLE "playback_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "target_type" TEXT NOT NULL,
    "target_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "playback_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "playback_sessions_user_id_target_id_idx" ON "playback_sessions"("user_id", "target_id");

-- CreateIndex
CREATE INDEX "playback_sessions_target_id_last_seen_at_idx" ON "playback_sessions"("target_id", "last_seen_at");

-- CreateIndex
CREATE UNIQUE INDEX "live_channels_ingest_key_key" ON "live_channels"("ingest_key");

-- CreateIndex
CREATE INDEX "live_channels_event_id_idx" ON "live_channels"("event_id");

-- CreateIndex
CREATE INDEX "vod_assets_event_id_idx" ON "vod_assets"("event_id");

-- AddForeignKey
ALTER TABLE "live_channels" ADD CONSTRAINT "live_channels_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vod_assets" ADD CONSTRAINT "vod_assets_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

