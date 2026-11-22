# Organizer App: Event Night Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give owners and managers a Guests tab (find, check in, undo), a Seats tab (hold, release, guest tickets) and waitlist counts in the organizer phone app.

**Architecture:** No API changes. New models and client methods in `event360_core`; the pan/zoom/tap seat map viewer moves from the buyer's seat picker into `event360_ui` as `SeatMapView`; the organizer app's event screen is split into one file per tab and gains two tabs and one card.

**Tech Stack:** Flutter, Riverpod 3 (`FutureProvider.family` keyed by `EventKey`), go_router, gen-l10n (en, my), dio.

**Spec:** `docs/superpowers/specs/2026-11-22-organizer-app-event-night-design.md`

## Global Constraints

- No changes under `apps/api`, `apps/web`, `apps/site`. No new server routes.
- Finance (`ORG_FINANCE`, `canEdit == false`) sees lists and the map but no selection and no action buttons.
- Buyer seat picker: no visible or behavioural change; its existing tests pass without edits to their assertions.
- `SeatState` and `SeatMapPainter` are not changed.
- Exactly one gold button per screen and per sheet; secondary actions navy or outline.
- Every new string in `app_en.arb` and `app_my.arb`; Myanmar natural, no uppercase styling.
- Layout at 1.0× text unchanged for existing screens; new screens pass the 2.0× overflow sweep in en and my at 390×844.
- `melos run analyze` has zero warnings; `melos run test` passes.
- No SMS anywhere. Check-in gate label is exactly `Organizer app`.
- Commit footer on every commit:
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01CsYsPiiALYTiE9YyJ6GZPD`.

## Review Focus

- Server refuses a seat action (409 with `takenSeats`) because another organizer or a buyer changed seats: map refreshes, changed seats leave the selection, message shown. (Task 4)
- Check-in pressed twice or retried after a timeout: second result is ALREADY_CHECKED_IN and is shown as information, not an error. (Task 3)
- Attendee with no phone, no display name, or a status the app does not know (e.g. TRANSFERRED): row still renders, grouped as Cancelled, no Call action without a phone. (Task 3)
- Event without a seat map, or a map with seats that have no ticket type: no Seats tab; untyped seats not selectable; held untyped seats cannot be issued. (Task 4)
- 3,000 attendees: list builds lazily and search stays responsive. (Task 3)

---

### Task 1: Core models and API methods

**Files:**
- Modify: `mobile/packages/core/lib/src/org.dart`, `mobile/packages/core/lib/src/api.dart`
- Test: `mobile/packages/core/test/org_event_night_test.dart`

**Interfaces — Produces** (all in `org.dart`, exported like the existing organizer models):

```dart
class Attendee { final String id, status; final DateTime createdAt; final String? seatLabel, seatLabelMy, guestName, holderName, phone; final bool isComplimentary; final String ticketTypeName;
  String get displayName; // holderName, else guestName, else phone, else ''
  bool get isIn => status == 'CHECKED_IN'; bool get isValid => status == 'VALID'; bool get isDead => !isIn && !isValid;
  factory Attendee.fromJson(Map<String, dynamic> j); }

class OrgSeat { final String seatKey, status; final String? ticketTypeId, holdLabel; } // status: AVAILABLE|CHECKOUT_HOLD|WAITLIST_HOLD|GUEST_HOLD|SOLD|UNSOLD
class OrgSeating { final Map<String, dynamic>? layout; final List<OrgSeat> seats; final Map<String, String> colors; // typeId -> #hex
  final Map<String, SeatCounts> counts; bool get hasMap => layout != null; factory OrgSeating.fromJson(...); }
class GuestTicket { final String id, guestName, phone /* masked */, seatKey, status; final String? seatLabel, seatLabelMy, label; final bool checkedIn;
  bool get canRevoke => status == 'VALID' && !checkedIn; }
class WaitlistCounts { final List<WaitlistTypeCount> types; final int total; }
class WaitlistTypeCount { final String id, name; final String? nameMy; final int waiting, offered; }
/// Thrown by hold/release/comps on HTTP 409 carrying takenSeats.
class SeatsChanged implements Exception { final String message; final List<String> takenSeats; }
```

`SeatCounts` gains `final int offered` (JSON `offered`, default 0).

`Event360Api` methods (paths under `/organizations/$orgId/events/$eventId`):

```dart
Future<List<Attendee>> attendees(String orgId, String eventId);                      // GET /attendees
Future<OrgSeating> orgSeating(String orgId, String eventId);                         // GET /seating
Future<List<GuestTicket>> guestTickets(String orgId, String eventId);                // GET /seating/guests
Future<int> holdSeats(String orgId, String eventId, List<String> seats, String label);   // POST /seating/hold -> held
Future<int> releaseSeats(String orgId, String eventId, List<String> seats);              // POST /seating/release -> released
Future<int> issueGuestTickets(String orgId, String eventId, List<String> seats, {required String guestName, required String phone, String? label}); // POST /seating/comps -> tickets.length
Future<void> revokeGuestTicket(String orgId, String eventId, String ticketId);       // POST /seating/comps/$ticketId/revoke
Future<WaitlistCounts> waitlistCounts(String orgId, String eventId);                 // GET /waitlist
```

hold/release/issue throw `SeatsChanged` when the error response is 409 and its body has a `takenSeats` list (look at how `_call` maps errors to `ApiException` and whether it keeps the response body; extend it minimally if not). Other errors stay `ApiException`.

- [ ] **Step 1:** Write `org_event_night_test.dart`: `Attendee.fromJson` with full row; with `holder` null and `guestName` set (`displayName` is the guest name); with neither (phone); status `TRANSFERRED` → `isDead`; `OrgSeating.fromJson` with `layout: null` → `hasMap == false`; `SeatCounts.fromJson({'offered': 3})`; `GuestTicket.canRevoke` false when `checkedIn`; `WaitlistCounts.fromJson` from the shape `{ticketTypes:[{id,name,nameMy,waiting,waitingQuantity,offered,offeredQuantity}], total}`.
- [ ] **Step 2:** Run `cd mobile/packages/core && flutter test test/org_event_night_test.dart` — fails (types missing).
- [ ] **Step 3:** Implement models and methods. Attendee JSON: `{id,status,createdAt,seatLabel,seatLabelMy,isComplimentary,guestName,ticketType:{id,name},holder:{id,displayName,phone}|null}`. Guest JSON: `{id,guestName,phone,seatKey,seatLabel,seatLabelMy,label,status,checkedIn,orderId,createdAt}`.
- [ ] **Step 4:** Add an API test (same style as existing core API tests, using the dio mock adapter if present, else a `HttpClientAdapter` stub) that a 409 `{message:'Some seats are not available', takenSeats:['A:1:1']}` from hold becomes `SeatsChanged` with that list, and a 409 without `takenSeats` stays `ApiException`.
- [ ] **Step 5:** `flutter test` in core passes; `melos run analyze` no warnings. Commit `core: organizer attendees, seating, guest tickets and waitlist models`.

### Task 2: Shared `SeatMapView`

**Files:**
- Create: `mobile/packages/ui/lib/src/seat_map_view.dart` (export from `event360_ui.dart`)
- Modify: `mobile/apps/user_app/lib/screens/seat_picker_screen.dart`
- Test: `mobile/packages/ui/test/seat_map_view_test.dart`

**Interfaces — Produces:**

```dart
const double kSeatTapScale = 1.6; // moves here from seat_picker_screen.dart; re-export so existing imports keep compiling

class SeatMapViewController { void zoomTo(Rect layoutRect, {Offset? focus}); void fit(); double get scale; }

class SeatMapView extends StatefulWidget {
  const SeatMapView({super.key, required this.layout, required this.states, required this.colors,
    this.selected = const {}, this.reserved = const {}, this.lang = 'en', this.controller,
    this.onSeatTap,            // seat index in layout.seats; called only when zoomed in to kSeatTapScale or more
    this.onScaleChanged, this.highlightSection, this.ink, this.stageColor, this.takenColor});
}
```

Behaviour is what the buyer screen does today: first layout fits the map to the viewport; a tap below `kSeatTapScale` zooms to the tapped section (or toward the tap point when no section is hit); at or above it, a tap on a seat calls `onSeatTap(index)`; pinch and pan via `InteractiveViewer` with the same min/max scale and boundary margin; the viewport size change re-fit rule (`_place`) is preserved. The "Zoom in to pick seats" hint pill stays in the buyer screen (it reads `onScaleChanged`).

- [ ] **Step 1:** Write `seat_map_view_test.dart` with a 2-section layout fixture: first frame fits the whole map inside 390×500; tapping a section while zoomed out does not call `onSeatTap` and raises the reported scale; after `controller.zoomTo(sectionBounds)` a tap on a seat centre calls `onSeatTap` with that seat's index; `selected` seats repaint (painter `shouldRepaint` true when the set changes).
- [ ] **Step 2:** Run it — fails (widget missing).
- [ ] **Step 3:** Move the viewer code (`TransformationController`, `_place`, `_zoomTo`, tap handling, `InteractiveViewer` + `CustomPaint`) out of `_SeatPickerScreenState` into `SeatMapView`; the screen keeps selection, holds, promo, legend, bottom bar, best-available and calls the controller where it used `_zoomTo`.
- [ ] **Step 4:** `cd mobile && melos run test` — ui test passes and every existing user_app seat picker test passes with no assertion edits (finder changes only if a private widget type was referenced). Commit `ui: shared SeatMapView; buyer seat picker uses it`.

### Task 3: Organizer event screen split + Guests tab

**Files:**
- Create: `mobile/apps/organizer_app/lib/screens/event/overview_tab.dart`, `door_tab.dart`, `announce_tab.dart`, `promos_tab.dart`, `guests_tab.dart` (move existing private tab widgets verbatim, made library-public)
- Modify: `mobile/apps/organizer_app/lib/screens/event_screen.dart`, `lib/app/providers.dart`, `lib/l10n/app_en.arb`, `app_my.arb`, `android/app/src/main/AndroidManifest.xml` (`<queries>` intent for `tel`), `ios/Runner/Info.plist` (`LSApplicationQueriesSchemes` `tel`)
- Test: `mobile/apps/organizer_app/test/widget_test.dart` (FakeApi additions), `test/guests_tab_test.dart`

**Interfaces:**
- Consumes: Task 1 `attendees`, existing `crewManualCheckin`, `crewUndo`, `attendanceProvider`.
- Produces: `final attendeesProvider = FutureProvider.family<List<Attendee>, EventKey>(...)`; `GuestsTab({required EventKey k, required bool canEdit, required OrgEvent event})`; `bool checkInOpen(OrgEvent e, DateTime now)` in `guests_tab.dart` = status is `PUBLISHED` or `ONGOING` and `now` is within `[startsAt - 24h, endsAt + 12h]`. Tab order `Overview, Guests, Seats (Task 4), Door, Announce, Promos`; keys `tabGuests`, `guestSearch`, `guestFilterNotIn`, `guestRow-<id>`, `guestCheckIn`, `guestUndo`, `guestCall`.

Sorting: not-in first, then checked-in, then dead; within a group by `displayName` case-insensitively. Search matches `displayName`, `guestName`, digits of `phone`, `seatLabel`, `seatLabelMy`.

English strings (Myanmar by the implementer, added to `docs/i18n/seating-my-review.csv`): `tabGuests` "Guests"; `guestsCount` "{inCount} of {total} checked in"; `guestsSearch` "Search name, phone or seat"; `guestsNotIn` "Not checked in"; `statusIn` "Checked in"; `statusNotIn` "Not in"; `statusCancelled` "Cancelled"; `guestBadge` "Guest"; `guestsEmpty` "No tickets yet"; `guestsNoMatch` "No one matches"; `updatedAt` "Updated {time}"; `checkIn` "Check in"; `undoCheckIn` "Undo check-in"; `undoCheckInConfirm` "Undo the check-in for {name}?"; `checkedInOk` "{name} is checked in"; `alreadyCheckedIn` "Already checked in at {time}" (+ `alreadyCheckedInGate` "Already checked in at {time}, {gate}"); `checkInRefused` "Can't check in: this ticket is {status}"; `checkInNoConnection` "Not checked in — no connection. Try again."; `checkInClosed` "Check-in opens one day before the event"; `call` "Call"; `registeredOn` "Registered {date}".

- [ ] **Step 1:** Move the four existing tabs to their files with no behaviour change; `melos run test` in organizer_app passes unchanged. Commit `organizer app: one file per event tab`.
- [ ] **Step 2:** Extend `FakeApi`: `attendeesList` (default 6 rows: 2 VALID, 2 CHECKED_IN, 1 VOID, 1 complimentary with `holder: null`), `attendees()`, `crewManualCheckin()` (flips the row, returns `ScanOutcome` ACCEPTED; second call ALREADY_CHECKED_IN with `checkedIn.at/gate`; `failCheckIn` flag throws `ApiException` network), `crewUndo()`.
- [ ] **Step 3:** Write `guests_tab_test.dart` (fails first): header shows "2 of 5 checked in" (dead rows excluded from total); order not-in → in → cancelled; search "0991" filters by phone digits; filter chip hides in and cancelled; tapping a VALID row then Check in calls the API with gate `Organizer app`, shows `checkedInOk`, row becomes Checked in; ALREADY_CHECKED_IN shows the info text, not an error; network failure shows `checkInNoConnection` and the row stays Not in; Undo asks to confirm then flips back; finance role: sheet has no Check in/Undo; event outside the window: no Check in, `checkInClosed` shown; attendee with no phone has no Call; unknown status `TRANSFERRED` renders as Cancelled; 3,000 generated attendees pump and search within the test timeout and only a screenful of rows is built (`find.byType(ListTile).evaluate().length < 40`).
- [ ] **Step 4:** Implement `GuestsTab` (`ListView.builder`, `RefreshIndicator`, sheet via `showModalBottomSheet(isScrollControlled: true)`; Call uses `launchUrl(Uri(scheme: 'tel', path: phone))`, on web shows `SelectableText`). After any action `ref.invalidate(attendeesProvider(k))` and `attendanceProvider(k)`.
- [ ] **Step 5:** Add Guests tab screens to the 2.0× sweep map (`list`, `sheet`, `search no match`). `melos run analyze && melos run test`. Commit `organizer app: Guests tab with check-in and undo`.

### Task 4: Seats tab

**Files:**
- Create: `mobile/apps/organizer_app/lib/screens/event/seats_tab.dart`
- Modify: `event_screen.dart`, `providers.dart`, arb files
- Test: `test/seats_tab_test.dart`, FakeApi additions

**Interfaces:**
- Consumes: Task 1 seating methods and `SeatsChanged`; Task 2 `SeatMapView`, `SeatLayout.fromJson`, `SeatLayout.seatByKey`.
- Produces: `orgSeatingProvider`, `guestTicketsProvider` (`FutureProvider.family<…, EventKey>`); `SeatsTab({required EventKey k, required bool canEdit})`; `SeatState orgSeatState(String status)` = `AVAILABLE→available`, `GUEST_HOLD→held`, `UNSOLD→unavailable`, everything else `taken`. Keys `tabSeats`, `seatsHold`, `seatsRelease`, `seatsIssue`, `seatsClear`, `holdLabel`, `guestName`, `guestPhone`, `guestLabel`, `issueConfirm`, `guestRevoke-<id>`.

The Seats tab is in the `TabBar` only when `orgSeatingProvider(k)` has data with `hasMap`; while loading it is absent (tab count is derived, so use a `DefaultTabController` keyed on the count). Selectable: `AVAILABLE` and `GUEST_HOLD` seats with `canEdit`. Action rule: all selected AVAILABLE → Hold (gold); all GUEST_HOLD → Issue (gold) + Release (outline), Issue disabled with hint when any selected seat has `ticketTypeId == null`; mixed → hint only; more than 200 → actions disabled with hint. One selected GUEST_HOLD seat shows its `holdLabel`.

English strings: `tabSeats` "Seats"; `seatsSelected` "{count} seats selected"; `clear` "Clear"; `holdForGuests` "Hold for guests"; `holdLabelField` "Label (e.g. Sponsor)"; `releaseSeats` "Release"; `releaseConfirm` "Put {count} seats back on sale?"; `issueGuestTickets` "Issue guest tickets"; `guestNameField` "Guest name"; `guestPhoneField` "Guest phone"; `guestLabelField` "Label (optional)"; `issueHelp` "The guest finds the tickets in the Event 360 app after signing in with this number. No SMS is sent."; `issueConfirmText` "Issue {count} guest tickets to {phone}?"; `seatsMixedHint` "Select only free seats or only held seats"; `seatsNoTypeHint` "Some held seats have no ticket type"; `seatsTooMany` "Select 200 seats or fewer"; `seatsChanged` "Some of those seats changed. The map has been updated."; `heldLabel` "Held: {label}"; `legendAvailable` "On sale"; `legendHeld` "Held for guests"; `legendSold` "Sold"; `legendGuest` "Guest tickets"; `guestList` "Guest tickets"; `revoke` (existing key) ; `revokeGuestConfirm` "Revoke the guest ticket for {name}?"; `guestRevoked` "Revoked"; `phoneInvalid` "Enter a Myanmar mobile number"; `viewOnlySeats` "You can view seats but not change them".

- [ ] **Step 1:** FakeApi: a 3-row seated layout (reuse the fixture from user_app tests or Task 2) with AVAILABLE, SOLD, GUEST_HOLD (label "Sponsor"), UNSOLD and one GUEST_HOLD seat with null type; `orgSeating`, `guestTickets`, `holdSeats`, `releaseSeats`, `issueGuestTickets`, `revokeGuestTicket` mutate it; `nextSeatsChanged` makes the next action throw `SeatsChanged(['<key>'])` after flipping that seat to SOLD.
- [ ] **Step 2:** Write `seats_tab_test.dart` (fails first): no Seats tab when `layout` is null; tab present with a map; `orgSeatState` mapping for all six statuses; tapping an AVAILABLE seat selects it and shows Hold only; Hold requires a label, calls the API, map refreshes, selection cleared; selecting two GUEST_HOLD seats shows Issue (the single gold button) and Release; Release confirms then calls the API; Issue sheet validates name and phone, shows `issueConfirmText` with the typed number, then calls the API and the guest list gains rows; mixed selection shows the hint and no action; a SOLD seat cannot be selected; the null-type held seat disables Issue with `seatsNoTypeHint`; `SeatsChanged` shows `seatsChanged`, refreshes and drops that seat from the selection; revoke confirms, calls the API, row shows Revoked and loses its button; a checked-in guest ticket has no Revoke; finance: taps select nothing, no action bar, `viewOnlySeats` shown; 201 selected seats disables actions with `seatsTooMany` (drive selection through a test-only constructor argument or by tapping in a larger fixture).
- [ ] **Step 3:** Implement `SeatsTab`: map in a fixed-aspect area (min 320 dp high) inside a `CustomScrollView` with legend, selection bar pinned at the bottom of the tab while a selection exists, guest list as a sliver. Phone validation client-side mirrors the user app's login field rule (reuse the helper from core if exported; else `^(\+?95|0)9\d{7,9}$` after stripping spaces/dashes) — the server remains the authority, a 400 maps to `phoneInvalid` under the field.
- [ ] **Step 4:** Add Seats screens to the 2.0× sweep (map, selection bar with two actions, hold sheet, issue sheet, confirm dialog, guest list). `melos run analyze && melos run test`. Commit `organizer app: Seats tab with holds and guest tickets`.

### Task 5: Waitlist card, offered seats, wording sheet

**Files:**
- Modify: `overview_tab.dart`, `providers.dart`, arb files, `docs/i18n/seating-my-review.csv`
- Test: `test/widget_test.dart`

**Interfaces — Consumes:** Task 1 `waitlistCounts`, `SeatCounts.offered`. **Produces:** `waitlistProvider`; keys `waitlistCard`.

English strings: `waitlistTitle` "Waitlist"; `waitlistLine` "{waiting} waiting · {offered} with an offer"; `seatsOffered` "Held for waitlist offers".

- [ ] **Step 1:** Tests (fail first): card lists only types with `waiting + offered > 0` and shows `waitlistLine`; hidden when total is 0; the seat counts block shows `seatsOffered` with the summed `offered` when non-zero; a failing `waitlistCounts` hides the card without breaking Overview.
- [ ] **Step 2:** Implement; pull-to-refresh also invalidates `waitlistProvider`.
- [ ] **Step 3:** Append every new organizer-app string from Tasks 3–5 to `docs/i18n/seating-my-review.csv` (columns `key,english,myanmar,where`, `where` = `organizer app`).
- [ ] **Step 4:** `melos run analyze && melos run test`. Commit `organizer app: waitlist card and offered seat count`.

### Task 6: Dev run-through

- [ ] **Step 1:** After the branch is on dev, open `https://app.dev.event360.app/organizer/` — sign-in on dev needs an organizer account; none may be created by the agent. If no credentials are available in the environment, capture the flow locally instead: run the API against the local test database with a seeded organizer and the seated sample layout, serve the organizer web build against it, and drive it with Playwright at 390×844 in en and my: Guests list → check in → undo; Seats → hold two seats → issue one guest ticket → revoke; Overview waitlist card.
- [ ] **Step 2:** Save screenshots to `docs/design/organizer-event-night/` and commit.
