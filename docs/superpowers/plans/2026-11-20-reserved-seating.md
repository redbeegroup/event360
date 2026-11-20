# Reserved Seating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins build reusable venue seat maps, let organizers price sections or rows and hold or comp guest seats, let buyers pick exact seats (or best available), and show seats on every ticket.

**Architecture:**
- A layout JSON per immutable map version is expanded into `event_seats` rows when an organizer picks a map.
- Seat claims are single conditional `UPDATE … WHERE status='AVAILABLE'` statements, inside the existing `createOrder` / `releaseHold` / `settle` / `refundOrder` transactions.
- Seated ticket-type counters (`quota`, `held`, `sold`) are kept in step, so dashboards, milestones and Crew stats work unchanged.

**Tech Stack:** NestJS 10 + Prisma 6 (PostgreSQL 18), Next.js 15 portal, Flutter (Riverpod 3, go_router), Jest/supertest, k6.

**Spec:** `docs/superpowers/specs/2026-11-20-reserved-seating-design.md`

## Global Constraints

- **Unseated events unchanged:** they (`Event.seatMapVersionId = null`) must behave exactly as today. All existing suites stay green.
- **Map versions are immutable:** a published `seat_map_versions` row never changes. Editing creates a new draft version.
- **Seat keys:** `seatKey = "<sectionKey>:<rowLabel>:<seatLabel>"`, unique within a version.
- **Seat status values:** `AVAILABLE | CHECKOUT_HOLD | GUEST_HOLD | SOLD | UNSOLD`.
- **Holds:** checkout hold = the existing `HOLD_MINUTES` (10). The sweeper only touches `CHECKOUT_HOLD`.
- **Seated ticket-type counters:**
  - `quota` = assigned seats minus GUEST_HOLD minus comp-SOLD;
  - `held` = CHECKOUT_HOLD;
  - `sold` = buyer orders only (comps excluded).
- **Comps:**
  - a zero-total order with `channel = 'COMP'`;
  - excluded from revenue, commission and milestones;
  - not transferable;
  - not counted toward per-person limits;
  - no SMS.
- **Refunds:**
  - paid refunds stay admin-only and whole-order;
  - attendees may cancel their own **free** tickets before `event.startsAt`;
  - organizers may revoke a single comp, and the seat returns to GUEST_HOLD with its label.
- **Seat availability:** `GET /v1/events/:id/seats` status is cached ≤ 2 s per pod (`MicroCache`), never the 10 s public cache. The layout is cached long, since it is immutable.
- **Languages:** all user-facing text in English and Myanmar (portal `app/lib/i18n.ts`, Flutter `.arb` files).
- **Seat label text:** `"<section name> · Row <row> · Seat <seat>"` (Myanmar: `"<section nameMy> · အတန်း <row> · ခုံ <seat>"`).

## Review Focus

1. **Overlapping claims:** two buyers submit overlapping seat sets at the same time. Exactly one order gets all its seats; the other gets 409 naming the taken seats, and none of its seats stay held. *(Task 4: `50 parallel overlapping claims`.)*
2. **Late payment:** a buyer pays after their hold expired and someone else took one of the seats. The order is flagged `needsReview`, and no seat is double-SOLD. *(Task 4: `late payment after seat resold`.)*
3. **Changing assignments after sales:** an organizer reassigns a row after some seats in it sold. Sold seats keep their ticket type and price; only AVAILABLE and GUEST_HOLD seats change. *(Task 3: `reassign keeps sold seats`.)*
4. **Admin republishes a map:** an admin publishes a new version while an event uses the old one. The event's seats and layout are unchanged. *(Task 2: `new version does not touch events`.)*
5. **Holding unavailable seats:** holding or comping a seat that is in someone's checkout or already sold fails with that seat named, and changes nothing. *(Task 6: `hold rejects non-available seats`.)*

---

### Task 1: Schema and layout expansion

**Files:**
- Modify: `apps/api/prisma/schema.prisma`
- Create: `apps/api/prisma/migrations/20261126010000_reserved_seating/migration.sql`, generated with `prisma migrate diff --from-migrations prisma/migrations --to-schema-datamodel prisma/schema.prisma --shadow-database-url …/e360_shadow --script`
- Create: `apps/api/src/modules/seating/layout.ts`
- Test: `apps/api/src/modules/seating/layout.spec.ts`

**Interfaces:**
- **Produces, Prisma models:**
  - `SeatMap { id, venueName, venueNameMy?, city, address?, latitude?, longitude?, mapUrl?, isActive, createdAt, updatedAt }` → `seat_maps`
  - `SeatMapVersion { id, seatMapId, version Int, layout Json, seatCount Int, createdById, publishedAt? }`, unique `(seatMapId, version)` → `seat_map_versions`
  - `EventSection { id, eventId, sectionKey, rowLabel?, ticketTypeId }`, unique `(eventId, sectionKey, rowLabel)` → `event_sections`
  - `EventSeat { id, eventId, seatKey, sectionKey, rowLabel, seatLabel, label, ticketTypeId?, status SeatStatus @default(UNSOLD), orderId?, ticketId? @unique, holdLabel?, heldUntil? }`, unique `(eventId, seatKey)`, index `(eventId, status)` → `event_seats`
  - `enum SeatStatus { AVAILABLE CHECKOUT_HOLD GUEST_HOLD SOLD UNSOLD }`
- **Produces, new fields on existing models:**
  - `Event.seatMapVersionId?`
  - `Ticket.seatKey?`, `Ticket.seatLabel?`, `Ticket.isComplimentary Boolean @default(false)`, `Ticket.compLabel?`, `Ticket.guestName?`
  - `TicketType.color String?` (hex, e.g. `#f2b632`)
- **Produces, fixture:** `apps/api/src/modules/seating/__fixtures__/theatre.json`. A 1,200-seat sample: Stalls with 20 rows × 40 seats and a centre aisle (`gapBefore` at seat 21), plus Balcony Left and Balcony Right of 10 rows × 20, a stage, and curve 0.15.
- **Produces, in `layout.ts`:**
  ```ts
  export type SeatAttr = 'RESTRICTED_VIEW' | 'WHEELCHAIR';
  export interface LayoutSeat { n: number; label?: string; gapBefore?: number; attrs?: SeatAttr[]; dx?: number; dy?: number }
  export interface LayoutRow { label: string; seats: LayoutSeat[] }
  export interface LayoutSection { key: string; name: string; nameMy?: string; kind: 'SEATED' | 'STANDING'; x: number; y: number; rotation?: number; curve?: number; rows?: LayoutRow[]; capacity?: number; w?: number; h?: number }
  export interface Layout { width: number; height: number; stage?: { x: number; y: number; w: number; h: number; label?: string }; sections: LayoutSection[] }
  export interface ExpandedSeat { seatKey: string; sectionKey: string; rowLabel: string; seatLabel: string; label: string; labelMy: string; x: number; y: number; attrs: SeatAttr[] }
  export function validateLayout(l: unknown): { ok: true; layout: Layout } | { ok: false; problems: string[] };
  export function expandSeats(l: Layout): ExpandedSeat[]; // seated sections only, layout order
  export const SEAT_SPACING = 24; // layout units between seats and rows
  ```

- [ ] **Step 1: Write failing tests in `layout.spec.ts`**
  - `expandSeats` on 1 section × 2 rows × 3 seats returns 6 seats, with keys `"A:1:1"…"A:2:3"` and labels `"Stalls · Row 1 · Seat 1"`.
  - `gapBefore: 2` shifts x by `2 * SEAT_SPACING`.
  - `curve` > 0 moves end seats down relative to the centre (`y` of the first seat > `y` of the middle seat).
  - A STANDING section adds no seats.
  - The fixture `theatre.json` validates and expands to exactly 1,200 seats with unique keys.
  - `validateLayout` reports duplicate section keys, duplicate seat labels in a row, an empty row, and a STANDING section without `capacity`.
- [ ] **Step 2:** Run `pnpm --filter @event360/api exec jest src/modules/seating/layout.spec.ts`. Expected: FAIL (module not found).
- [ ] **Step 3:** Add the models and migration. Implement `layout.ts` with no I/O.
  - Row y = `section.y + rowIndex * SEAT_SPACING`.
  - Seat x = `section.x + (i + cumulative gaps) * SEAT_SPACING + dx`.
  - Curve: `y += curve * ((x - centreX) / halfWidth)^2`.
  - Rotation is applied about the section origin.
- [ ] **Step 4:** Run the same jest command, then `prisma migrate dev` on the local DB. Expected: PASS, and the migration applies.
- [ ] **Step 5:** Commit `feat(seating): schema and layout expansion`.

### Task 2: Admin venue maps API

**Files:**
- Create: `apps/api/src/modules/seating/seat-maps.service.ts`, `apps/api/src/modules/seating/seating.module.ts` (registered in `app.module.ts`)
- Test: `apps/api/test/seating.e2e-spec.ts` (new suite, `describe('Seat maps')`)

**Interfaces:**
- **Consumes:** `validateLayout`, `expandSeats` (Task 1).
- **Produces endpoints** (`@Auth('PLATFORM_ADMIN')`, under `/v1/admin/seat-maps`):
  - `GET /` lists maps with the latest version numbers.
  - `POST /` `{venueName, venueNameMy?, city, address?, latitude?, longitude?, mapUrl?}` → map.
  - `PATCH /:id` updates the same fields plus `isActive`.
  - `GET /:id` returns the map plus versions (without layouts).
  - `GET /:id/versions/:version` returns the version with its layout.
  - `PUT /:id/draft` `{layout}` creates or replaces the single unpublished version; 400 with `problems` if invalid.
  - `POST /:id/publish` publishes the draft (sets `publishedAt` and `seatCount`).
  - `POST /:id/import` `{layout}` is the same as `PUT draft`.
- **Produces, for organizers** (any authenticated org member): `GET /v1/seat-maps` lists active maps that have a published version (id, venue fields, latest published version id, seatCount).
- **Produces:** `SeatMapsService.publishedVersion(versionId): Promise<{ id; layout: Layout; seatMap: SeatMap }>`.

- [ ] **Step 1: Write failing e2e tests**
  - `admin creates map, saves draft, publishes`: version 1, seatCount = expanded seats.
  - `invalid layout returns problems`.
  - `published version is immutable`: `PUT draft` after publish creates version 2, and version 1's layout is unchanged.
  - `new version does not touch events` *(Review Focus 4; completed in Task 3 once events exist; add it here as `it.todo`, then implement it in Task 3)*.
  - `non-admin gets 403`.
  - `organizer list hides maps without a published version`.
- [ ] **Step 2:** Run `pnpm --filter @event360/api exec jest test/seating.e2e-spec.ts -t "Seat maps"` with `DATABASE_URL`/`DIRECT_DATABASE_URL` set. Expected: FAIL.
- [ ] **Step 3:** Implement the service and controllers, with an audit log entry on publish (`AuditLog`, like the settings changes).
- [ ] **Step 4:** Rerun the same command. Expected: PASS.
- [ ] **Step 5:** Commit `feat(seating): admin venue maps`.

### Task 3: Seated events, assignments and availability

**Files:**
- Create: `apps/api/src/modules/seating/event-seats.service.ts`
- Modify: `apps/api/src/modules/seating/seating.module.ts`, `apps/api/src/modules/events/events.service.ts` (DTO includes `seating: { seatMapVersionId, venueName } | null`; ticket types expose `seated: boolean`)
- Test: `apps/api/test/seating.e2e-spec.ts` (`describe('Seated events')`)

**Interfaces:**
- **Consumes:** `SeatMapsService.publishedVersion`, `expandSeats`, `MicroCache`/`publicCacheMs` from `src/common/micro-cache.ts`.
- **Produces endpoints** (org OWNER/MANAGER via `OrgAccessService.assert`, under `/v1/organizations/:orgId/events/:id/seating`):
  - `PUT /map` `{seatMapVersionId}`:
    - copies venue fields into the event's `Venue` row, creating one if missing;
    - creates `event_seats` (status UNSOLD);
    - 409 if any seat is SOLD, CHECKOUT_HOLD or GUEST_HOLD.
  - `DELETE /map` turns the event back into an unseated one (same 409 rule).
  - `PUT /assignments` `{rules: {sectionKey, rowLabel?, ticketTypeId}[]}`:
    - replaces `event_sections`;
    - recomputes `ticketTypeId` and status (UNSOLD↔AVAILABLE) for AVAILABLE, UNSOLD and GUEST_HOLD seats only;
    - STANDING sections map to a ticket type whose quota the organizer sets as today;
    - then recomputes the counters.
  - `GET /` returns `{ layout, versionId, rules, counts: {ticketTypeId: {available, held, guest, sold, comp}} }` plus a per-seat status list for the organizer.
- **Produces, public:** `GET /v1/events/:idOrSlug/seats` → `{ versionId, layout, types: {id, name, nameMy, priceMmk, color}[], seatTypes: string, status: string }`:
  - `seatTypes`: per expanded seat in layout order, the index into `types`, or `-` if unsold, encoded as one char each (`0-9a-zA-Z`).
  - `status`: one char per seat: `A`vailable, `T`aken (CHECKOUT_HOLD, SOLD), `G`uest hold (shown as taken), `U`nsold.
  - Cache: the layout part is cached by `versionId` (long); the status part uses `MicroCache(2000)` per event.
- **Produces:** `EventSeatsService.recountTicketTypes(tx, eventId): Promise<void>`, which sets `quota`, `held` and `sold` on the event's seated ticket types from `event_seats`, following the Global Constraints formula. Called after every seat state change, in the same transaction.
- **Produces:** `EventSeatsService.labelFor(seat): { label: string; labelMy: string }`.
- **Ticket type colour:** organizers set `color` via the existing ticket-type create and update DTOs. If unset, colours come from a fixed palette by price order.

- [ ] **Step 1: Write failing e2e tests**
  - `picking a map creates seats and copies venue`.
  - `row rule beats section rule`.
  - `unassigned seats are UNSOLD and not on sale`.
  - `seated ticket type quota equals assigned seats`.
  - `reassign keeps sold seats` *(Review Focus 3; mark one seat SOLD directly in the DB first)*.
  - `cannot change map once a seat is sold`.
  - `public seats endpoint encodes types and status`: the decoded lengths equal the seat count.
  - `new version does not touch events` (fill in the todo from Task 2).
  - `unseated event unchanged`: the existing event detail has `seating: null`.
- [ ] **Step 2:** Run the jest command for `-t "Seated events"`. Expected: FAIL.
- [ ] **Step 3:** Implement. Choosing or changing the map counts as a `venue` change for `REVIEWED_FIELDS` re-review; assignments do not.
- [ ] **Step 4:** Rerun. Expected: PASS. Also run the full `pnpm --filter @event360/api test` and expect it to stay green.
- [ ] **Step 5:** Commit `feat(seating): seated events, assignments, availability`.

### Task 4: Seated checkout (claim, expire, settle, late pay, admin refund)

**Files:**
- Modify: `apps/api/src/modules/payments/payments.service.ts` (`createOrder`, `releaseHold`, `settle`, `issueTickets`, `refundOrder`, `orderView`), `apps/api/src/modules/payments/payments.module.ts` (`CreateOrderDto.seats?: string[]`, max 20)
- Create: `apps/api/src/modules/seating/seat-claims.ts`
- Test: `apps/api/test/seating.e2e-spec.ts` (`describe('Seated checkout')`)

**Interfaces:**
- **Consumes:** `recountTicketTypes`, `labelFor` (Task 3).
- **Produces, in `seat-claims.ts`** (all take a `Prisma.TransactionClient`):
  - `claimSeats(tx, eventId, seatKeys, orderId, heldUntil: Date | null, final: boolean): Promise<{ ok: true; seats: EventSeat[] } | { ok: false; taken: string[] }>`. One `UPDATE … WHERE event_id=… AND seat_key = ANY(…) AND status='AVAILABLE' RETURNING …`. If the count is short, the caller throws 409 `{ message, takenSeats }`. `final=true` sets SOLD directly (free orders).
  - `releaseSeats(tx, orderId, to: 'AVAILABLE'): Promise<number>` releases CHECKOUT_HOLD seats of the order.
  - `sellSeats(tx, orderId, ticketIdsBySeat: Map<string,string>): Promise<void>` sets CHECKOUT_HOLD → SOLD and `ticket_id`.
- **`createOrder(userId, eventId, items, idempotencyKey?, channel?, promoCode?, seats?: string[])`:**
  - Seats are grouped by their seat's ticket type into lines. Quantity per type = number of seats.
  - Lines for seated types skip the `ticket_types` quota UPDATE and use `claimSeats` instead. Unseated or standing lines are unchanged.
  - The per-person limit counts seats.
  - Seats whose ticket type is null, or from another event, get 400.
- **`issueTickets`** sets `seatKey` and `seatLabel` on tickets created for seated lines (one ticket per seat).
- **`releaseHold`** calls `releaseSeats`.
- **`settle`:**
  - In the existing "hold expired" branch, it re-claims the order's seat keys. If any are not AVAILABLE, it sets `needsReview` exactly like the no-quota case.
  - Otherwise it calls `sellSeats`.
- **`refundOrder`** sets the order's seats back to AVAILABLE (`ticket_id = null`, `order_id = null`).
- Every path calls `recountTicketTypes` for seated events.

- [ ] **Step 1: Write failing e2e tests**, using `PAYMENTS_MOCK=true` and the mock provider like `test/payments.e2e-spec.ts`:
  - `free seated order issues tickets with seat labels`.
  - `paid seated order holds then settles`: the seats are SOLD and the tickets carry `seatLabel`.
  - `taken seat returns 409 naming it and holds nothing`.
  - `50 parallel overlapping claims` *(Review Focus 1)*: 50 buyers each claim the same 2 seats plus one unique seat. Exactly 1 succeeds, the 49 losers leave no CHECKOUT_HOLD rows, and `ticket_types.held` equals the CHECKOUT_HOLD count.
  - `expired hold frees seats` (call the sweeper method directly).
  - `late payment after seat resold` *(Review Focus 2)*: `needsReview`, and only one SOLD per seat.
  - `admin refund frees all seats`.
  - `per-person limit counts seats`.
  - `mixed order: seats plus standing quantity`.
- [ ] **Step 2:** Run with `-t "Seated checkout"`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Rerun, then the full API suite. Expected: PASS, with `payments.e2e-spec.ts` unchanged and green.
- [ ] **Step 5:** Commit `feat(seating): seated checkout`.

### Task 5: Best available

**Files:**
- Create: `apps/api/src/modules/seating/best-available.ts`
- Modify: `apps/api/src/modules/seating/seating.module.ts`, adding the public `POST /v1/events/:id/seats/best` `{ticketTypeId, quantity}` (Throttle 20/min)
- Test: `apps/api/src/modules/seating/best-available.spec.ts`

**Interfaces:**
- **Consumes:** `ExpandedSeat` (Task 1) and seat statuses.
- **Produces:**
  ```ts
  export function bestAvailable(seats: (ExpandedSeat & { status: string; ticketTypeId: string | null })[], stage: { x: number; y: number } | undefined, ticketTypeId: string, quantity: number): string[] | null;
  ```
  - Prefer `quantity` adjacent seats in one row (adjacent = consecutive in layout order with no `gapBefore` between them), choosing the block whose centre is closest to the stage centre (or to the layout's top centre if there is no stage).
  - Otherwise, the `quantity` closest AVAILABLE seats of that type within the best section.
  - Return null if there aren't enough.
  - The endpoint returns `{ seats: string[] }` and does **not** hold anything. The buyer then submits them to `createOrder`.

- [ ] **Step 1: Write failing unit tests**
  - `picks centre block of adjacent seats in front row`.
  - `skips blocks split by an aisle gap`.
  - `falls back to closest scattered seats`.
  - `returns null when not enough`.
  - `ignores other ticket types and taken seats`.
- [ ] **Step 2:** Run `jest src/modules/seating/best-available.spec.ts`. Expected: FAIL.
- [ ] **Step 3:** Implement the function and the endpoint.
- [ ] **Step 4:** Rerun. Expected: PASS.
- [ ] **Step 5:** Commit `feat(seating): best available`.

### Task 6: Guest holds, complimentary tickets, revoke and PDF

**Files:**
- Create: `apps/api/src/modules/seating/guests.service.ts`, `apps/api/src/modules/seating/ticket-pdf.ts`
- Modify: `apps/api/src/modules/seating/seating.module.ts`, `apps/api/src/modules/tickets/tickets.service.ts` (`transfer` rejects `isComplimentary` with 409 "Guest tickets can't be transferred"), `apps/api/package.json` (adds `pdfkit` + `@types/pdfkit`, pure JS)
- Test: `apps/api/test/seating.e2e-spec.ts` (`describe('Guest seats')`)

**Interfaces:**
- **Consumes:** `recountTicketTypes`, `labelFor` (Task 3); `TicketTokenService.sign` (`apps/api/src/modules/tickets/ticket-token.service.ts`); `NotifyService` (an inbox and push to the guest, using the existing `ticket_received` kind).
- **Produces endpoints** (org OWNER/MANAGER, under `/v1/organizations/:orgId/events/:id/seating`):
  - `POST /hold` `{seats: string[], label}`: AVAILABLE → GUEST_HOLD. 409 `{takenSeats}` if any seat isn't AVAILABLE.
  - `POST /release` `{seats}`: GUEST_HOLD → AVAILABLE.
  - `POST /comps` `{seats, guestName, phone, label?}`:
    - every seat must be GUEST_HOLD;
    - upserts the user by phone (same helper as transfers);
    - creates an Order (`channel 'COMP'`, status `CONFIRMED`, all totals 0, `commissionMmk 0`);
    - creates tickets with `isComplimentary`, `compLabel`, `guestName`, `seatKey` and `seatLabel`;
    - marks the seats SOLD.
  - `GET /guests` lists comp tickets: guest name, masked phone, seat label, label, status, checked in.
  - `POST /comps/:ticketId/revoke`: the ticket becomes `VOID`, and its seat goes back to GUEST_HOLD with `holdLabel = compLabel`.
  - `GET /comps.pdf?ids=…` (or all) streams `application/pdf`: one A5 page per ticket with event title, date in Myanmar time, venue, guest name, seat label, comp label and a QR of the signed ticket token (use `qrcode` to a PNG buffer).
- **Excluded from figures:** comp orders are left out of revenue, sales totals, the dashboard `orders`/`revenueMmk`, `notify.checkSales` milestones and the finance balances. Filter `channel != 'COMP'` wherever those queries sum orders (`orgtools.module.ts` dashboard, `payments.service.ts` sales view, `notify.service.ts` milestones).

- [ ] **Step 1: Write failing e2e tests**
  - `hold rejects non-available seats` *(Review Focus 5)*.
  - `release returns seats to sale`.
  - `comps issue tickets to a phone and mark seats sold`, with the guest's `/v1/me/tickets` showing the seat and "Complimentary".
  - `comps excluded from sales, revenue and milestones`.
  - `comp ticket cannot be transferred`.
  - `revoking one of several comps returns only that seat to GUEST_HOLD`.
  - `comps.pdf has one page per ticket`: the body starts with `%PDF` and the count of `/Type /Page` matches.
- [ ] **Step 2:** Run with `-t "Guest seats"`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Rerun, then the full suite. Expected: PASS.
- [ ] **Step 5:** Commit `feat(seating): guest holds and complimentary tickets`.

### Task 7: Seats on tickets, crew, CSV and dashboard; attendees cancel free tickets

**Files:**
- Modify:
  - `apps/api/src/modules/tickets/tickets.service.ts` (the `me/tickets` view adds `seat`, `isComplimentary`, `compLabel`, `canCancel`);
  - `apps/api/src/modules/tickets/tickets.module.ts`, adding `POST /v1/me/tickets/:id/cancel`;
  - `apps/api/src/modules/checkin/checkin.service.ts` (`ticketView` and `manifest` add `seat`; the comp label is shown in the holder line);
  - `apps/api/src/modules/orgtools/orgtools.module.ts` (CSV adds `Seat` and `Complimentary` columns; the dashboard adds `seats: {available, guest, sold, comp}` per type);
  - `apps/api/src/modules/checkin/checkin.service.ts` `stats` (a comp count per type).
- Test: `apps/api/test/seating.e2e-spec.ts` (`describe('Seat everywhere')`)

**Interfaces:**
- **Consumes:** Tasks 3, 4 and 6.
- **Produces:** `POST /v1/me/tickets/:id/cancel`:
  - **Allowed only** if the holder is the caller, the ticket is VALID, not complimentary, its order `totalMmk = 0` and `channel != 'COMP'`, and `now < event.startsAt`. Otherwise 409 with the reason.
  - **Effect:** the ticket becomes `VOID`. For seated events the seat goes back to AVAILABLE (`recountTicketTypes`); for unseated events, `ticket_types.sold -= 1`.
  - **Returns** `{ ok: true }`.
- **Produces:** the `me/tickets` field `canCancel: boolean`, under the same rule.

- [ ] **Step 1: Write failing e2e tests**
  - `my tickets show seat label`.
  - `crew manifest and scan include seat`.
  - `attendee CSV has Seat column`.
  - `cancel free seated ticket frees the seat`.
  - `cancel free unseated ticket returns quota`.
  - `cannot cancel paid ticket` (409).
  - `cannot cancel after start` (409).
  - `transfer keeps the seat`.
- [ ] **Step 2:** Run with `-t "Seat everywhere"`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Rerun, then the full suite. Expected: PASS.
- [ ] **Step 5:** Commit `feat(seating): seats on tickets, crew, CSV; cancel free tickets`.

### Task 8: Portal: Admin → Venues and map editor

**Files:**
- Create: `apps/web/app/admin/venues/page.tsx` (list and create), `apps/web/app/admin/venues/[id]/page.tsx` (details, versions, editor), `apps/web/app/components/SeatMapEditor.tsx` (client component), `apps/web/app/components/SeatMapView.tsx` (SVG renderer, reused in Task 9)
- Create: `apps/web/app/lib/seat-layout.ts`, a copy of the pure `expandSeats`/`validateLayout` from Task 1. Keep the two in sync: the Task 1 fixture `theatre.json` is the shared reference, and the portal file carries a header comment pointing to the API source.
- Modify: `apps/web/app/admin/layout.tsx` (a "Venues" nav link), `apps/web/app/admin/actions.ts` (actions for create, update, saveDraft, publish, import), `apps/web/app/lib/i18n.ts` (EN and MY keys)

**Interfaces:**
- **Consumes:** the Task 2 endpoints.
- **Produces:**
  - `SeatMapView({ layout, seatTypes?, status?, colors?, selected?: Set<string>, onToggle?(seatKey), held?: Set<string> })` renders an SVG with a viewBox from the layout `width`/`height`, a stage rect, section labels, and circles per seat (r = 9).
  - `SeatMapEditor({ initial: Layout, onSave(layout) })`:
    - the section list on the left: add a seated section (rows, seats per row, start number, direction LTR/RTL, odd/even) or a standing one (capacity, w, h);
    - section fields: key, name, nameMy, x, y, rotation, curve;
    - per-row label, seat count and "gap after seat N";
    - click seats to delete, tag RESTRICTED_VIEW or tag WHEELCHAIR;
    - a live preview with `SeatMapView`, a live seat count, and validation problems listed;
    - Save draft, Publish (with a confirm), Import JSON (a textarea), Export JSON.

- [ ] **Step 1:** Run `cd apps/web && npx tsc --noEmit && npx next build`, then check on a locally running API with Playwright (`scratchpad` script, like earlier phases):
  - an admin creates the sample "Event 360 Sample Theatre" map from the fixture via Import, sees 1,200 seats, and publishes;
  - take a screenshot.
  Expected: build OK and the screenshot shows the map.
- [ ] **Step 2:** Commit `feat(portal): admin venue maps and editor`.

### Task 9: Portal: organizer Seats tab, guests and comps

**Files:**
- Create: `apps/web/app/organizer/[orgId]/events/[id]/seats/page.tsx`, `apps/web/app/organizer/[orgId]/events/[id]/comps.pdf/route.ts` (proxies the Task 6 PDF with the user's token)
- Modify: `apps/web/app/organizer/[orgId]/events/[id]/page.tsx` (a "Seated venue" picker in event details, plus a link to the Seats tab), `apps/web/app/organizer/actions.ts`, `apps/web/app/lib/i18n.ts`

**Interfaces:**
- **Consumes:** Task 3 endpoints (`PUT map`, `PUT assignments`, `GET seating`), Task 6 endpoints, `SeatMapView` (Task 8).
- **Produces the Seats tab UI:**
  - **Assign mode:** click a section, or a row label, then pick a ticket type. A legend shows each type's colour and seat count.
  - **Guests mode:** click or drag-select seats, then "Hold for guests" (label) or "Release".
  - **Issue comps:** with held seats selected, open a form (guest name, phone, label) and issue.
  - **Guest list table:** with Revoke per row, "Download PDF (selected / all)", and the checked-in state.
  - **Counts:** available, held, sold and comps per ticket type.

- [ ] **Step 1:** Typecheck and build the portal. Run a Playwright check against the local API:
  - the organizer picks the sample map, assigns VIP (rows A–C), Standard (stalls) and Balcony;
  - holds 6 seats "Sponsor", issues 2 comps, and downloads the PDF (200, `application/pdf`);
  - take screenshots.
- [ ] **Step 2:** Commit `feat(portal): organizer seats, guest holds and comps`.

### Task 10: User app: seat picker, seat on tickets, cancel free ticket

**Files:**
- Modify:
  - `mobile/packages/core/lib/src/models.dart`: `EventSeating`, `SeatMapData` (decoded layout plus `seatTypes`/`status` strings), `MyTicket.seat`, `isComplimentary`, `compLabel`, `canCancel`, and `TicketType.seated`/`color`;
  - `mobile/packages/core/lib/src/api.dart`: `seatMap(eventId)`, `bestSeats(eventId, ticketTypeId, qty)`, `createOrder(..., seats:)`, `cancelTicket(id)`;
  - `mobile/apps/user_app/lib/screens/event_detail_screen.dart` (a "Choose seats" button for seated events);
  - `mobile/apps/user_app/lib/screens/ticket_screen.dart` and `tickets_screen.dart` (seat label, "Complimentary · label", and a "Cancel ticket" button with confirm when `canCancel`);
  - `mobile/apps/user_app/lib/app/router.dart` (route `/event/:id/seats`);
  - `.arb` files (EN and MY).
- Create: `mobile/packages/ui/lib/src/seat_map_painter.dart`, a `CustomPainter` plus hit-testing reused by the Crew and Organizer apps; exported from `event360_ui`. Also `mobile/apps/user_app/lib/screens/seat_picker_screen.dart`.

**Interfaces:**
- **Consumes:** `GET /v1/events/:id/seats`, `POST /v1/events/:id/seats/best`, `POST /v1/events/:id/orders {seats}`, `POST /v1/me/tickets/:id/cancel`.
- **Produces the seat picker:**
  - `InteractiveViewer` (minScale fits the whole map, maxScale 6) with `SeatMapPainter`;
  - seats are tappable at scale ≥ 1.6; below that, tapping a section zooms into it;
  - availability is polled every 5 s while open;
  - a bottom bar shows the selected seat labels, the total in MMK, a "Best available" sheet (type + quantity) and Continue;
  - Continue goes to the existing checkout flow with `seats`;
  - on 409, show the taken seats, drop them from the selection and refresh.

- [ ] **Step 1: Write failing widget tests**, with a fake API like the existing tests:
  - `seat picker renders and selects up to maxPerOrder`;
  - `409 drops taken seats and refreshes`;
  - `best available fills selection`;
  - `ticket shows seat label and complimentary`;
  - `cancel button only when canCancel`.
- [ ] **Step 2:** Run `cd mobile && melos run test`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `melos run analyze && melos run test`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(app): seat picker and seats on tickets`.

### Task 11: Crew and Organizer apps; public website

**Files:**
- Modify:
  - `mobile/packages/core/lib/src/crew.dart` (manifest and scan models get `seat`);
  - `mobile/apps/crew_app/lib/screens/scan_screen.dart` (the seat shown large on the result card, plus the comp label), `lookup_screen.dart` (seat in results);
  - `mobile/apps/organizer_app/lib/screens/…` (the live overview shows seat counts available, held, sold and comps for seated events);
  - `apps/site/app/[lang]/e/[slug]/page.tsx` (a "Reserved seating" badge and a static SVG map overview coloured by ticket type, from `GET /v1/events/:id/seats`, using a server-side copy of the SVG drawing; the site has no React client JS for it);
  - `apps/site/app/lib/i18n.ts`.
- Test: crew widget test `scan result shows seat`, including offline (manifest seat); site `npx tsc --noEmit && npx next build`.

**Interfaces:**
- **Consumes:** the Task 7 manifest and scan `seat` fields, and the Task 3 public seats endpoint.
- **Produces:** UI only.

- [ ] **Step 1:** Write the failing crew widget test `scan result shows seat` for online and offline results. Run `melos run test`. Expected: FAIL.
- [ ] **Step 2:** Implement the crew, organizer and site changes.
- [ ] **Step 3:** Run `melos run analyze && melos run test`, then the site typecheck and build. Expected: PASS.
- [ ] **Step 4:** Commit `feat(seating): seats in crew, organizer app and website`.

### Task 12: Load test, sample data, dev rollout

**Files:**
- Modify: `infra/loadtest/k6.js` (a new `seated` scenario: 1,000 buyers on a 500-seat assigned map, half picking random available seats from `/seats`, half via `/seats/best`; counters `seated_claimed` and `seated_conflict`), `infra/loadtest/data.js` (creates a seated variant using the fixture map), `docs/runbook.md` §10 (results)
- Uses: the Task 1 fixture `theatre.json`

- [ ] **Step 1:** Run the full API suite, `melos run test`, portal and site builds, and `pnpm test:manifests`. Expected: all green.
- [ ] **Step 2:** Commit and push. Wait for dev to run the new image (the `wait_dev.py` pattern). Import the fixture map on dev via the admin API, and create one sample seated event in a sample org.
- [ ] **Step 3:** Run the seated load test on dev. Pass criteria:
  - `seated_claimed` ≤ 500, with exactly one SOLD seat per seat (check with a DB query in `data.js`);
  - zero 5xx;
  - p95 of `/seats` < 300 ms at 50 req/s.
  Then run cleanup.
- [ ] **Step 4:** Record the results in the runbook and commit `test(seating): seated load test results`.

---

**Self-review notes:**
- **Spec coverage:**
  - admin maps: T2, T8;
  - organizer assign, hold, comps, PDF, revoke: T3, T6, T9;
  - buyer picker and best available: T5, T10;
  - holds, settle, refund, late pay: T4;
  - seats on tickets, crew, CSV, dashboard, transfer, cancel free: T7, T11;
  - mixed standing: T3, T4;
  - website overview: T11;
  - 2 s availability cache: T3;
  - re-review rule: T3;
  - load test and rollout: T12.
- **Names used across tasks:**
  - `recountTicketTypes`, `labelFor`, `claimSeats`, `releaseSeats`, `sellSeats`, `bestAvailable`, `expandSeats`, `validateLayout`, `SeatMapView`, `SeatMapPainter`;
  - endpoint paths as defined above.
