# Organizer app: event night — design

Date: 2026-11-22. Status: awaiting approval.

## Why

The organizer phone app shows numbers but lets an organizer do little at the venue. Nobody carries a laptop to the
door, so the things the portal does for event night — find a person, admit them, seat a late VIP — are out of reach
when they are needed. This round puts those in the app.

## Goals

- At the venue, an owner or manager can find any ticket holder, see whether they are in, and check them in by hand.
- For a seated event they can see the map as it stands now, hold or release seats, issue a guest ticket and revoke it.
- They can see how many people are on the waitlist per ticket type.

## Not in this round

- Sales breakdown, payouts, full order list (planned as the next round).
- Creating or editing events, ticket types, prices, discounts; team invites; live streaming.
- Printing guest tickets as PDF and assigning ticket types to seats (stay on the portal).
- Scanning QR codes in the organizer app (the crew app does this).

## Must not happen

- A finance-only member being able to hold, release, issue, revoke or check in. They may only look.
- An action that half-succeeds silently: the server treats each seat action as all-or-nothing; the app must show
  that plainly and refresh the map.
- Any server change that alters behaviour for the portal, crew app or buyers. This round needs no API changes.
- Sending SMS. Issuing a guest ticket already sends an in-app notice only; that stays.

## Decisions made with the user

- Scope is "event night at the venue" (option 1 of three).
- The attendee list has a Check in button with Undo for owners and managers.
- Phone numbers are shown in full in the attendee list, as the portal does today.

## Approaches considered

1. **Three additions inside the existing event screen, map viewer shared from the UI package (chosen).** The event
   screen gains a Guests tab and a Seats tab; the waitlist goes on Overview. The pan/zoom/tap seat map viewer is
   lifted out of the buyer's seat picker into `event360_ui` so both apps draw the same map. Cost: touching the
   buyer's seat picker, which is well tested, to use the shared viewer.
2. **Copy the map viewer into the organizer app.** No risk to the buyer screen, but two copies of zoom, hit-testing
   and painting to keep in step. Rejected: the seat map has already needed several fixes.
3. **Open the portal's seats page in a web view.** Least code, but the portal page is built for a mouse (shift-drag
   box select) and a wide screen, and needs a second sign-in. Rejected.

## What gets built

### 1. Guests tab (every event)

Data: `GET /organizations/:orgId/events/:id/attendees` (all tickets, no paging) for the list, and
`GET /organizations/:orgId/events/:id/attendance` is already loaded for totals. The attendees response has no
check-in time, so "checked in" comes from ticket `status` (`CHECKED_IN`).

- Header line: "N of M checked in".
- Search field (client-side: name, guest name, phone digits, seat label) and a filter chip "Not checked in".
- Rows: name (holder display name, else guest name, else phone), ticket type, seat if any, "Guest" badge for
  complimentary tickets, status badge: Checked in (CHECKED_IN) / Not in (VALID) / Cancelled (VOID, REFUNDED,
  TRANSFERRED and any other status; shown dimmed and sorted last; hidden when the "Not checked in" filter is on).
- The list is built lazily (`ListView.builder`); events can have thousands of tickets and the endpoint is unpaged.
  A "Updated HH:MM" line shows how fresh the list is.
- Tap a row: bottom sheet with full name, phone with a Call action (`tel:` link; on the web preview the number is
  selectable text instead; phone can be missing), ticket type, seat, registered
  date, status, and for owners/managers one action:
  - **Check in** for a VALID ticket → `POST /crew/events/:eid/tickets/:tid/checkin` with `gate: "Organizer app"`.
    Result ACCEPTED → success; ALREADY_CHECKED_IN → say so, with when and which gate; other results → show the status.
  - **Undo check-in** for a CHECKED_IN ticket, behind a confirm → `POST …/undo`. 409 "not checked in" → refresh.
  - The Check in and Undo actions are offered only inside the crew app's window: event PUBLISHED or ONGOING, from
    1 day before start to 12 hours after end (builder's call, matching `GET /crew/events`; the server does not
    enforce it for organizer tokens).
  - No connection or a timeout → "Not checked in — no connection. Try again." Retrying is safe: a repeat returns
    ALREADY_CHECKED_IN. There is no offline queue in this round.
- Pull to refresh; the list also refreshes after any action. Finance sees the list with no actions.
- Empty states: no tickets yet; no match for the search.

### 2. Seats tab (only when the event has a seat map)

Data: `GET …/seating` (layout, per-seat status and hold label, colours, counts) and `GET …/seating/guests`.
The tab is not shown when `layout` is null.

- Shared map viewer (see Build notes) showing every seat:
  - on sale (AVAILABLE): its ticket type colour;
  - sold, being paid for, or held for a waitlist offer (SOLD, CHECKOUT_HOLD, WAITLIST_HOLD): the existing "taken"
    grey;
  - held for guests (GUEST_HOLD): the existing "held" style (`SeatState.held` already means this);
  - no ticket type assigned (UNSOLD): the existing "unavailable" style, not selectable.
  No new seat state or paint style is needed, so the buyer's map is drawn exactly as today.
  The per-seat data does not say which sold seats are guest tickets; the guest list below carries that.
- Legend with counts (available, held for guests, sold, guest tickets) from `counts`.
- Tap a seat to select or unselect it (owners/managers only). Seats that are sold or being paid for cannot be
  selected. A selection bar shows "N seats selected" and Clear, with exactly one enabled action by selection:
  - all selected are on sale → **Hold for guests**: sheet asking for a label (required, max 100) →
    `POST …/seating/hold`;
  - all selected are held for guests → **Release** (confirm) → `POST …/seating/release`, and
    **Issue guest tickets**: sheet with guest name (required, max 200), phone (required, Myanmar mobile) and an
    optional label → `POST …/seating/comps`. The sheet says the guest finds the tickets in the Event 360 app after
    signing in with that number, and that no SMS is sent. Before sending, a confirm step repeats the number and
    seats ("Issue 2 guest tickets to 09 123 456 789?"): a mistyped number gives the tickets to a stranger. Held
    seats with no ticket type cannot be issued; the action is disabled for them with a hint;
  - a mix → no action, with a hint to select either free seats or held seats.
  With two actions available (held seats), Issue is the primary button and Release the secondary.
- Tapping a single held seat with nothing else selected shows its hold label in the selection bar.
- Errors: a 409 with `takenSeats` → message "Some of those seats changed. The map has been updated.", refresh,
  and drop the changed seats from the selection. A 400 on phone → inline field error. Other errors → the app's
  usual error snackbar.
- Guest list under the map: name, masked phone, seat, label, status (In / Not in / Revoked), and for
  owners/managers a **Revoke** button (confirm) on tickets that are valid and not checked in →
  `POST …/seating/comps/:ticketId/revoke`. 409 already checked in / already revoked → say so and refresh.
- Finance sees map, legend and guest list with no selection and no actions.
- Limit: at most 200 seats per action (server limit); the bar disables actions above that and says why.

### 3. Waitlist on Overview

Data: `GET …/waitlist`. A card listing each ticket type that has anyone waiting or offered:
"12 waiting · 2 with an offer". Hidden when the total is zero. Also add the `offered` seat count (seats held for
waitlist offers), which the dashboard already sends, to the existing seat counts block.

## Build notes

- `event360_ui`: new `SeatMapView` widget = the InteractiveViewer + fit/zoom logic + tap hit-testing now inside the
  buyer's seat picker, taking layout, per-seat states and colours, selected set, and `onSeatTap`. The buyer's seat
  picker is changed to use it with no visible or behavioural change. `SeatState` and the painter are not changed;
  the organizer app maps server statuses to the existing states.
- `event360_core`: models and API methods for attendees, organizer seating overview, guests, hold, release, comps,
  revoke, waitlist counts. The crew check-in and undo calls already exist (`crewManualCheckin`, `crewUndo`) and
  work with an organizer's token. `SeatCounts` gains `offered`. Android/iOS manifests declare the `tel` scheme.
- Organizer app: Guests and Seats tabs in `event_screen.dart` (split into files per tab — the file is already
  large), providers keyed by `(orgId, eventId)` like the existing ones, strings in English and Myanmar.
- Tab order: Overview, Guests, Seats, Door, Announce, Promos.
- Large text: the new screens join the 2× overflow sweep added on 2026-11-22.
- One gold button per screen, as in the rest of the apps; sheets use navy/outline for secondary actions.

## Testing

- Widget tests with the fake API: list, search, filter, check-in and undo incl. each result; role gating for finance;
  seat selection rules and the action shown for each selection; hold, release, issue, revoke incl. 409 with
  `takenSeats`; tab hidden without a map; waitlist card shown/hidden.
- The buyer seat picker's existing tests must pass unchanged after the viewer is extracted.
- 2× text sweep in English and Myanmar for the new tabs and sheets.
- On dev: run through hold → issue → guest sees ticket → check in from the Guests tab → undo → revoke, on the seated
  sample event, with screenshots.

## Left to the builder

Widget structure, provider layout, exact Myanmar wording (to be added to the native-speaker review sheet), the
hatched paint style, and how list rows are laid out at small widths.
