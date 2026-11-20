-- A whole-section rule (row_label IS NULL) must be unique per event and section.
-- The (event_id, section_key, row_label) unique index does not cover NULL row_label in PostgreSQL.
-- Partial index: not expressible in schema.prisma, so it lives only in this migration.
CREATE UNIQUE INDEX "event_sections_section_rule_key" ON "event_sections" ("event_id", "section_key") WHERE "row_label" IS NULL;
