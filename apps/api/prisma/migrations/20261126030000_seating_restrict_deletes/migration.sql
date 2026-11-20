-- DropForeignKey
ALTER TABLE "events" DROP CONSTRAINT "events_seat_map_version_id_fkey";

-- DropForeignKey
ALTER TABLE "seat_map_versions" DROP CONSTRAINT "seat_map_versions_seat_map_id_fkey";

-- AddForeignKey
ALTER TABLE "events" ADD CONSTRAINT "events_seat_map_version_id_fkey" FOREIGN KEY ("seat_map_version_id") REFERENCES "seat_map_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "seat_map_versions" ADD CONSTRAINT "seat_map_versions_seat_map_id_fkey" FOREIGN KEY ("seat_map_id") REFERENCES "seat_maps"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

