# Reserved seating: design

Status: draft for approval · 2026-11-20

## Intent

Concerts and theatre shows in Yangon venues are sold by seat: the National Theatre, the Myanmar Convention Centre, hotel ballrooms and concert halls. Today Event 360 only sells counted tickets ("VIP: 200 left"). This phase lets:
- buyers pick their exact seats, or let the app pick the best available;
- organizers hold seats for invited guests and give them complimentary tickets;
- door staff see each ticket's seat.

What success looks like:
- An organizer can put a theatre show on sale without drawing anything.
- A buyer on a small Android phone can get good seats in under a minute.
- Two people never get the same seat, even in an on-sale rush.
- Sponsors and press receive printed or app tickets with their seats.

## Goals

1. **Venue maps (Event 360 admins).** Admins build a reusable seat map per venue once, in the admin portal. Organizers never draw.
2. **Seated events (organizers).** An organizer picks a venue map, then assigns sections or rows to their ticket types (price, colour).
3. **Buying.**
   - Buyers see the map coloured by price, with taken seats greyed out.
   - They can zoom and tap seats, or press "Best available".
   - Seats are held for 10 minutes during payment (free orders confirm immediately).
4. **Mixed events.** One event can mix seated sections and standing areas, such as a concert floor plus a seated balcony.
5. **Guest seats.**
   - Organizers mark seats "Held for guests" with a label, then issue complimentary tickets from them to a guest name and phone.
   - Guests see the ticket in the app when they sign in with that phone.
   - The organizer can download a printable PDF (one ticket per page: name, seat, QR).
   - Unused held seats can be released back to sale.
6. **Seat on every ticket.**
   - "Balcony · Row C · Seat 12" appears in the user app, the Crew app (online and offline), the portal attendee list and CSV, and on the printable ticket.
   - Transfers keep the seat; refunds free it.

## Non-goals (this phase)

- Organizers drawing or editing maps, or copying one and adjusting it. Planned later; the data model must not block it (see "Later: organizer copies").
- Dynamic pricing, seat-level prices (prices are per ticket type, assigned to sections or rows), and resale.
- Accessibility seat booking flows beyond a "wheelchair space" seat attribute shown on the map.
- 3D views or "view from seat" photos.
- Seat swaps or changes after purchase (an admin refunds, then the buyer re-buys).

## Anti-goals

These would count as failure even if everything else works:
- any way for one seat to be sold, held or comped twice;
- a map edit by an admin moving or deleting a seat that is already sold or held for an event;
- a seat picker that is unusable on a 5-inch Android phone in a 1,500-seat hall;
- slowing down existing unseated events, which must keep working exactly as today.

## Constraints from the existing system

- **Stack:** NestJS + Prisma (PostgreSQL 18, schemas `dev` and `prod`), Next.js portal (`apps/web`), Flutter user, crew and organizer apps (`mobile/`), public site (`apps/site`).
- **Orders today** (`apps/api/src/modules/payments/payments.service.ts`):
  - `createOrder` reserves counted seats with `UPDATE ticket_types SET held = held + q WHERE sold + held + q <= quota`, then creates `PENDING_PAYMENT` orders held for 10 minutes. Free orders settle immediately.
  - `releaseHold` (expiry/cancel) and `settle` (paid) move `held` into `sold` and create tickets.
  - A late payment after expiry re-takes seats if free, otherwise flags `needsReview`.
  - `refundOrder` voids tickets and returns quota.
  - A sweeper runs every 30 s.
- **Tickets:** a ticket has `ticketTypeId` and a signed QR (`tid, eid, tt, v`). Transfers bump `qrVersion`. Crew offline mode uses `/crew/events/:id/manifest`.
- **Performance:** today's load test showed Prisma CPU is the bottleneck on the cluster (about 34 ms per heavy list call). Public event pages are cached for 10 s per pod. Seat availability must not go through that 10 s cache (see Availability).
- **Notifications:** SMS is only used for event change and cancel. Complimentary tickets do not send SMS.
- **Languages:** everything user-facing is in English and Myanmar.

## Approaches considered

How seat availability is stored and claimed:

1. **One row per seat per event in PostgreSQL (chosen).**
   - When a seated event is published, its venue map version is copied into an `event_seats` table, with a status per seat.
   - Claims are single conditional updates: all requested seats change only if all are free.
   - This is the same pattern as today's quota counters, which passed the rush test. Holds expire with the existing sweeper, and backups, reports and the crew manifest read the same table.
   - Cost: about 2,000 rows per event.
2. **Seat locks in Redis, with database rows only on payment.** Faster under extreme load, but two sources of truth, and holds are lost if Redis restarts. Not needed at our scale.
3. **Seat states packed into one field on the event.** Compact, but every purchase serialises on one row, the same hot-row problem the view counter had.

The user picked option 1. Maps are stored as a layout description (JSON). The portal renders it as SVG and Flutter draws it on a zoomable canvas. Printable tickets are a PDF produced by the API.

## Data model

New tables (one migration). The names are suggestions; the builder may refine them.

### Venue maps (admin-owned, reusable)

- **`seat_maps`**: `id`, `venueName`, `venueNameMy`, `city`, `address`, `latitude?`, `longitude?`, `mapUrl?`, `isActive`, timestamps.
- **`seat_map_versions`**: `id`, `seatMapId`, `version` (int), `layout` (JSON, below), `seatCount`, `createdById`, `publishedAt?`.
  - Only published versions can be chosen by organizers.
  - A published version is **immutable**; editing creates a new draft version.
- **Layout JSON:**
  - `{ width, height, stage: {x,y,w,h,label}, sections: [...] }`
  - Each section has `{ key, name, nameMy, kind: 'SEATED'|'STANDING', x, y, rotation, curve, rows: [...] }` for seated sections, or `{ ..., kind: 'STANDING', capacity, shape }` for standing ones.
  - Each row has `{ label, seats: [{ n, label?, x?, gapBefore?, attrs: ['RESTRICTED_VIEW'|'WHEELCHAIR'|...] }] }`.
  - Seat positions are computed from row and seat index plus `curve`, with optional per-seat overrides.
  - Each seat has a stable `seatKey = "<sectionKey>:<rowLabel>:<seatLabel>"`, unique within a version.

### Per event

- **`Event`** gains `seatMapVersionId?`. Null means an unseated event and today's behaviour, unchanged.
- **`event_sections`** maps sections or rows to ticket types for an event:
  - columns: `eventId`, `sectionKey`, `rowLabel?` (null = whole section), `ticketTypeId`;
  - the most specific rule wins (row over section);
  - sections or rows with no rule are not on sale.
- **`event_seats`**, one row per seat in the event, created as soon as the organizer **picks the venue map** (while the event is still a draft):
  - They are re-created only while no seat is SOLD, CHECKOUT_HOLD or GUEST_HOLD. *(builder's call, from review)*
  - Organizers can therefore assign prices and hold guest seats **before** submitting or publishing. Publishing remains "on sale", as today, so guest seats are held before the opening rush.
  - `eventId`, `seatKey`, `sectionKey`, `rowLabel`, `seatLabel`, `ticketTypeId?`, `status`, `orderId?`, `ticketId?`, `holdLabel?`, `heldUntil?`;
  - `status` is one of `AVAILABLE | CHECKOUT_HOLD | GUEST_HOLD | SOLD | UNSOLD` (UNSOLD = no ticket type assigned);
  - unique `(eventId, seatKey)`; index `(eventId, status)`.
  - Standing areas get **no** `event_seats` rows. They are a ticket type with a quota, exactly as today.
- **`TicketType`** *(builder's call, from review)*:
  - For seated ticket types, `quota` = assigned seats that are not GUEST_HOLD or comped, meaning the seats actually for sale.
  - `held` counts CHECKOUT_HOLD seats only.
  - `sold` counts buyer orders only (paid or free), **not** comps.
  - So the sales milestones ("first sale", "half sold", "sold out"), dashboards and revenue reflect real sales.
  - Guest holds and comps are reported separately (a `comp` count per type on the dashboard and Crew stats).
  - GUEST_HOLD seats keep their ticket type, so releasing them returns them to the right price.
  - The sweeper only ever touches CHECKOUT_HOLD.
- **`Ticket`** gains `seatKey?` plus denormalised `seatLabel?` (display text, such as "Balcony · Row C · Seat 12"), and `isComplimentary` + `compLabel?`.
- **`Order`**: free orders reuse the existing path. Complimentary tickets are a new zero-total order with `channel = 'COMP'`, which excludes them from commission and revenue.

## Behaviour

### Admin: building a venue map (portal, Admin → Venues)

- **List venues:** create, archive.
- **Map editor**, practical rather than polished:
  - The canvas shows the stage plus sections.
  - Add a section: seated (rows count, seats per row, start number, numbering direction left-to-right or right-to-left, odd/even only) or standing (capacity).
  - Move or rotate a section by dragging or entering numbers, and set its curve.
  - Per row: label, seat count, gaps after seat N. Select seats to delete them or tag them (restricted view, wheelchair).
  - Live seat count.
- **Saving and publishing:** save as draft; publish (validates that `seatKey`s are unique and every row has seats). Editing a published map creates a new draft version. Events keep the version they were created with.
- **Import:** admins can import a layout JSON, for quick starts and to copy between dev and prod.

### Organizer: setting up a seated event (portal)

- **Picking a venue:** in event details, the organizer chooses "Seated venue" and picks a published map. Or they keep "Venue address only" (today's unseated event).
  - Picking a map **copies** its name, address, city and pin into the event's existing per-event `Venue` row. That keeps the city filter, the venue check and the notification text unchanged. `seat_maps` is a separate admin catalogue, and `Venue` is not restructured. *(builder's call, from review)*
  - Choosing or changing the map counts as a venue change for the existing re-review rule for unverified organizers. Seat assignments, guest holds and comps do **not** trigger re-review.
- **Ticket types:**
  - Seated ticket types have no quota field; it is computed from assigned seats.
  - Standing sections become a ticket type with the section's capacity as its default quota (editable).
- **Assigning prices** ("Seats" tab):
  - The map is shown.
  - Click a section to assign it to a ticket type, or expand it and assign rows.
  - Colours come from the ticket type. A legend shows the seat count per type.
- **Holding seats for guests:**
  - Select seats (click, or drag to select a block) and choose "Hold for guests" with a label (Sponsor, Press, Artist).
  - Held seats show striped. "Release" returns them to sale.
- **Issuing complimentary tickets:**
  - Select held seats, then "Issue complimentary tickets": guest name, phone (Myanmar format), label.
  - This creates a zero-total COMP order and the tickets, then marks the seats SOLD.
  - The phone owner sees the ticket in the app when they sign in, using the same mechanism as transfers to a phone number that has not signed up yet (create the user by phone if missing).
  - Comp tickets are **not transferable** (they're issued to a named guest) and don't count toward the guest's per-person buying limit. *(builder's call, from review)*
  - An inbox notification and push are sent if that user has the app.
- **Guest list:** guest name, phone (masked), seats, label, checked in yes/no.
  - Actions: download a PDF of selected guest tickets, one per A5/A4 page, with event, date, venue, guest name, seat, QR, label; revoke a comp (voids the ticket, the seat goes back to GUEST_HOLD).
- **Locking:** once any seat is SOLD, the event's map version cannot change. Assignments can still change for AVAILABLE and GUEST_HOLD seats only.

### Buyer: picking seats (user app, web and Android, plus organizer preview)

- **Event page:** seated events show "Choose seats". Standing ticket types still use the quantity picker.
- **Seat picker screen:**
  - The map is drawn on a canvas with pinch-zoom and pan. It starts zoomed to fit, with section labels; seats become tappable once zoomed in enough.
  - Seats are coloured by ticket type. Taken and held seats are grey, restricted view seats are marked, wheelchair spaces are marked.
  - Tapping a seat selects it, up to the ticket type's `maxPerOrder` across the order.
  - A bottom bar shows the selected seats, the total and Continue.
- **Best available:** pick a ticket type and quantity, and the server chooses seats.
  - Rule: same row, adjacent, nearest the centre of the section closest to the stage. If no adjacent block fits, it falls back to the closest seats in the same section.
  - The buyer sees the chosen seats and can accept or re-pick.
- **Continue:** `POST /v1/events/:id/orders` with `seats: [seatKey]` (plus `items` for standing types, so mixed orders work).
  - The server claims all seats in one statement (`UPDATE event_seats SET status='CHECKOUT_HOLD', order_id=…, held_until=now()+10min WHERE event_id=… AND seat_key = ANY(…) AND status='AVAILABLE'`). If the row count ≠ requested, everything rolls back with 409 and the list of seats that were taken.
  - The app refreshes the map and keeps the buyer's other selections.
- **After the claim:** payment, the waiting screen and expiry work as today.
  - On settle: seats → SOLD with `ticketId`, and ticket rows get `seatKey`/`seatLabel`.
  - On expiry or cancel: seats → AVAILABLE.
  - Late payment after expiry: re-claim the same seats if still AVAILABLE, otherwise `needsReview` (same rule as today).
- **Per-person limit:** `maxPerOrder` and the existing per-user ticket limit count seats too.
- **Promo codes:** apply to seated orders unchanged (they act on order totals).

### Availability endpoint

- **`GET /v1/events/:id/seats`** returns the map layout plus a compact status list.
- **Caching:** status is cached at most **2 s** per pod, not the 10 s public cache. The layout is cached long, since it is immutable per version.
- **Payload size:** it must stay small for 2,000 seats. Suggested shape: status as a string of one character per seat in layout order, plus the ticket type per section/row.
- **Live updates:** clients poll every 5 s while the picker is open. Realtime push via the existing Socket.IO gateway is optional, the builder's call.

### Tickets, door and after-sales

- **Ticket views:** the user app ticket, the Crew scan result, the Crew manual lookup, the attendee list/CSV and the printable PDF show the seat label. Comp tickets show "Complimentary · <label>".
- **Crew offline manifest:** gains `seat` per ticket. A scan result shows the seat large.
- **Transfers:** keep `seatKey`, and `qrVersion` bumps as today.
- **Refunds:** set the seat back to AVAILABLE, or to GUEST_HOLD if it was a comp being revoked.
- **Event cancelled:** existing flow, no seat changes needed.
- **Organizer dashboard:** a sold/held/available seat count per ticket type, plus a small map thumbnail showing sold density.

### Public website

The event page shows "Reserved seating" and a static, non-interactive overview of the map with price colours. Buying stays in the app or web app.

## Edge cases to handle

- Two buyers clicking the same seat at the same moment: one gets it, the other gets 409 with that seat named.
- An admin publishes a new map version while events use the old one: those events keep the old version, and only new events see the new one.
- An organizer changes a row's ticket type after some seats in it are sold: only AVAILABLE and GUEST_HOLD seats change; sold seats keep their ticket and price.
- Holding seats for guests that are in someone's CHECKOUT_HOLD: not allowed; only AVAILABLE seats can be held.
- Issuing a comp for a seat that was released and sold meanwhile: fails with that seat named.
- A seated event with every seat held or sold shows "Sold out" (held seats count as not available).
- Event page cache (10 s): the ticket type "remaining" counts on cached pages may lag; the seat endpoint is the source of truth.

## Testing expectations

- **API e2e:**
  - map versioning immutability;
  - publish creates `event_seats`;
  - assignment rules (row over section);
  - concurrent claims for overlapping seats (exactly one wins, with a test of 50 parallel claims);
  - hold expiry frees seats;
  - settle sets tickets' seats;
  - late payment rules;
  - refund and revoke;
  - transfer keeps the seat;
  - best available picks an adjacent block;
  - comps excluded from revenue and commission;
  - PDF endpoint returns a PDF with the right number of pages;
  - the crew manifest includes seats;
  - unseated events behave exactly as before (the existing suites stay green).
- **Flutter widget tests:** seat picker renders a map, selection limits, 409 refresh, best available flow, seat label on ticket and Crew result.
- **Load test:** extend `infra/loadtest/k6.js` with a seated rush (1,000 buyers on a 500-seat map, random and best-available picks), with no double sale and p95 targets similar to today's.

## Rollout

- Dev first: build one sample venue map (a generic 1,200-seat theatre with stalls and two balconies) and one sample seated event.
- Prod after your OK. Real Yangon venue maps are built by Event 360 admins from floor plans; the builder provides the editor and the sample only.

## Later: organizer copies (not now)

The data model allows a later "copy a venue map into an event and adjust it", by letting `Event.seatMapVersionId` point at an event-private version. Nothing in this phase should assume versions are always admin-owned beyond permissions.

## Left to the builder

- Exact table and column names, and the JSON field names.
- The map editor's interaction details, the SVG and canvas rendering approach, and the zoom thresholds.
- The availability payload encoding, and whether to add Socket.IO push.
- PDF library choice (pure JS, runs in the API image).
- The best-available tie-breaking details beyond the rule above.
