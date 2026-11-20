-- CreateTable
CREATE TABLE "error_groups" (
    "id" UUID NOT NULL,
    "fingerprint" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "stack" TEXT,
    "path" TEXT,
    "count" INTEGER NOT NULL DEFAULT 1,
    "first_seen" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_release" TEXT,
    "last_context" JSONB,
    "resolved_at" TIMESTAMP(3),
    "alerted_at" TIMESTAMP(3),

    CONSTRAINT "error_groups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "monitor_checks" (
    "name" TEXT NOT NULL,
    "ok" BOOLEAN NOT NULL DEFAULT true,
    "consecutive_failures" INTEGER NOT NULL DEFAULT 0,
    "last_error" TEXT,
    "detail" TEXT,
    "last_checked_at" TIMESTAMP(3),
    "changed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "alerting" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "monitor_checks_pkey" PRIMARY KEY ("name")
);

-- CreateTable
CREATE TABLE "monitor_incidents" (
    "id" UUID NOT NULL,
    "check" TEXT NOT NULL,
    "error" TEXT NOT NULL,
    "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at" TIMESTAMP(3),

    CONSTRAINT "monitor_incidents_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "error_groups_fingerprint_key" ON "error_groups"("fingerprint");

-- CreateIndex
CREATE INDEX "error_groups_last_seen_idx" ON "error_groups"("last_seen");

-- CreateIndex
CREATE INDEX "monitor_incidents_started_at_idx" ON "monitor_incidents"("started_at");

