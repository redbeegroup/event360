-- AlterTable
ALTER TABLE "event_sessions" ADD COLUMN     "description" TEXT,
ADD COLUMN     "description_my" TEXT,
ADD COLUMN     "location" TEXT,
ADD COLUMN     "title_my" TEXT;

-- AlterTable
ALTER TABLE "events" ADD COLUMN     "accessibility" TEXT,
ADD COLUMN     "accessibility_my" TEXT,
ADD COLUMN     "age_min" INTEGER,
ADD COLUMN     "dress_code" TEXT,
ADD COLUMN     "dress_code_my" TEXT,
ADD COLUMN     "languages" TEXT,
ADD COLUMN     "languages_my" TEXT,
ADD COLUMN     "parking" TEXT,
ADD COLUMN     "parking_my" TEXT,
ADD COLUMN     "refund_policy" TEXT,
ADD COLUMN     "refund_policy_my" TEXT,
ADD COLUMN     "terms" TEXT,
ADD COLUMN     "terms_my" TEXT,
ADD COLUMN     "what_to_bring" TEXT,
ADD COLUMN     "what_to_bring_my" TEXT;

-- AlterTable
ALTER TABLE "organizations" ADD COLUMN     "description_my" TEXT,
ADD COLUMN     "facebook_url" TEXT,
ADD COLUMN     "show_contact" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "website" TEXT;

-- AlterTable
ALTER TABLE "venues" ADD COLUMN     "directions" TEXT,
ADD COLUMN     "directions_my" TEXT,
ADD COLUMN     "map_url" TEXT;

-- CreateTable
CREATE TABLE "event_performers" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "name_my" TEXT,
    "role" TEXT,
    "role_my" TEXT,
    "bio" TEXT,
    "bio_my" TEXT,
    "photo_key" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "event_performers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_media" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "key" TEXT NOT NULL,
    "caption" TEXT,
    "caption_my" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "event_media_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "event_faqs" (
    "id" UUID NOT NULL,
    "event_id" UUID NOT NULL,
    "question" TEXT NOT NULL,
    "question_my" TEXT,
    "answer" TEXT NOT NULL,
    "answer_my" TEXT,
    "sort_order" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "event_faqs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "event_performers_event_id_sort_order_idx" ON "event_performers"("event_id", "sort_order");

-- CreateIndex
CREATE INDEX "event_media_event_id_sort_order_idx" ON "event_media"("event_id", "sort_order");

-- CreateIndex
CREATE INDEX "event_faqs_event_id_sort_order_idx" ON "event_faqs"("event_id", "sort_order");

-- CreateIndex
CREATE INDEX "event_sessions_event_id_starts_at_idx" ON "event_sessions"("event_id", "starts_at");

-- AddForeignKey
ALTER TABLE "event_performers" ADD CONSTRAINT "event_performers_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_media" ADD CONSTRAINT "event_media_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "event_faqs" ADD CONSTRAINT "event_faqs_event_id_fkey" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE CASCADE;
