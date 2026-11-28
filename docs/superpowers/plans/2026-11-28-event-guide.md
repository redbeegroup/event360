# Event Guide (round 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-event guide for ticket holders in the buyer app (status, tickets, now/next, venue, announcements, good-to-know, thank-you), available offline, with search inside an event; and the checked-in ticket shown correctly.

**Architecture:** Two additive server pieces (ticket holder announcements endpoint, `checkedInAt` on my tickets). Models, an event cache and pure helpers in `event360_core`. In the buyer app: a guide screen built from the existing event payload, a grouped Tickets tab, a today card and home banner, and a client-side search.

**Tech Stack:** NestJS + Prisma; Flutter, Riverpod 3, go_router, shared_preferences, gen-l10n (en, my).

**Spec:** `docs/superpowers/specs/2026-11-28-event-guide-design.md`

## Global Constraints

- No change to buying, tickets, QR codes, check-in, or any existing API field or route. Server additions are read-only.
- Announcements endpoint: event checked first (unknown → 404), then a VALID or CHECKED_IN ticket held by the caller (none → 403); signed out → 401.
- The guide is reachable only with a VALID or CHECKED_IN ticket for that event (live list or saved copy); otherwise redirect to `/event/:id`.
- A saved copy is always labelled with its save time. Saved events and announcements are removed on sign-out and 7 days after the event ended. At most 10 events saved.
- Web build: online only; no service worker.
- `MyTicket.checkedInAt`, `eventStatus`, `eventSlug` are nullable and round-trip through the ticket cache; a cache written by an older build must still load.
- Times in Yangon time through the existing helpers in `lib/app/format.dart`; status uses the device clock through an injectable `now`.
- Exactly one gold button per screen/sheet. Existing screens unchanged at 1.0× except where this plan changes them (Tickets tab grouping, ticket screen states and link, home banner, search action on the event page).
- Every new string in `app_en.arb` and `app_my.arb` and in `docs/i18n/seating-my-review.csv` (`where` = `user app`); Myanmar natural, no uppercase styling.
- New screens pass the 2.0× overflow sweep (en, my, 390×844). `flutter analyze` zero warnings; `flutter test` passes in core, ui, user_app, crew_app, organizer_app; `apps/api` `npx tsc --noEmit && npx jest` passes.
- No changes under `mobile/apps/organizer_app`, `mobile/apps/crew_app`, `apps/web`, `apps/site`; shared `event360_core` changes must be additive for them.
- No `dart format` on existing files. Commit footer on every commit:
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01CsYsPiiALYTiE9YyJ6GZPD`.

## Review Focus

- A phone with no signal on event day that has never opened the event while online: the guide says "Connect once to save this event", the ticket QR still works. (Tasks 4, 5)
- An event whose sessions cross midnight or span several days; an event with one session; an event with none. (Task 2 helpers, Task 4)
- A ticket checked in at the door, then the app refreshed: shows "Checked in", never "Cancelled"; undone at the door → valid again with its QR. (Tasks 1, 3)
- A holder of tickets to two events on the same day; a signed-out user; a user whose only ticket was refunded opening `/event/:id/guide` directly. (Tasks 4, 5)
- A saved copy written by this build read after an app update that adds fields, and an older ticket cache read by this build. (Task 2)

---

### Task 1: Server — holder announcements and `checkedInAt`

**Files:**
- Modify: `apps/api/src/modules/notifications/inbox.controller.ts` (or the module that owns `Announcement`; add a `me` route beside the buyer inbox routes), `apps/api/src/modules/tickets/tickets.service.ts` (`/me/tickets`)
- Test: `apps/api/test/event-guide.e2e-spec.ts`

**Interfaces — Produces:**
- `GET /v1/me/events/:eventId/announcements` → `Array<{ id: string; title: string; titleMy: string | null; body: string; bodyMy: string | null; createdAt: string }>`, newest first, max 50.
- Each item of `GET /v1/me/tickets` gains `checkedInAt: string | null` = latest `scannedAt` among that ticket's check-ins with `isDuplicate: false` and `undoneAt: null`; one `findMany` for all the user's ticket ids (no per-ticket query).

- [ ] **Step 1:** Write `event-guide.e2e-spec.ts` (bootstrap like `notifications.e2e-spec.ts`): holder gets the event's two announcements newest first with exactly those six keys; announcements of another event absent; a signed-in user with no ticket → 403; a user whose only ticket is VOID → 403; unknown event id → 404 (also for a non-holder); signed out → 401; a guest (comp) ticket holder → 200; after a transfer the old holder → 403 and the new holder → 200; `/me/tickets`: `checkedInAt` null before check-in, an ISO time equal to the scan time after a crew check-in, null again after undo; a duplicate scan does not change it; every pre-existing key of a ticket item is still present with the same value (snapshot the keys before the change by listing them in the test).
- [ ] **Step 2:** Run it — fails (404 route, missing field).
- [ ] **Step 3:** Implement both. **Step 4:** `npx tsc --noEmit && npx jest` (whole suite) passes. Commit `api: announcements for ticket holders, check-in time on my tickets`.

### Task 2: Core — models, event cache, guide helpers

**Files:**
- Modify: `mobile/packages/core/lib/src/models.dart`, `api.dart`, `notifications.dart` (or a new `guide.dart` exported from the package barrel)
- Create: `mobile/packages/core/lib/src/guide.dart`, `event_cache.dart`
- Test: `mobile/packages/core/test/guide_test.dart`, `event_cache_test.dart`, `models_guide_test.dart`

**Interfaces — Produces:**

```dart
// models.dart (additive)
class ScheduleItem { final String? id; ... }                       // parsed from 'id'
class MyTicket { final DateTime? checkedInAt; final String? eventStatus, eventSlug; bool get isCheckedIn => status == 'CHECKED_IN'; ... } // in fromApi, toJson, fromJson
class EventAnnouncement { final String id, title, body; final String? titleMy, bodyMy; final DateTime createdAt;
  factory EventAnnouncement.fromJson(Map<String, dynamic> j); Map<String, dynamic> toJson(); }
// api.dart
Future<List<EventAnnouncement>> eventAnnouncements(String eventId);    // GET /me/events/$eventId/announcements
Future<Map<String, dynamic>> eventRaw(String idOrSlug);                // same request as event(), returns the JSON map for caching

// event_cache.dart — storage-agnostic so it is unit-testable
abstract class KeyValueStore { String? getString(String key); Future<void> setString(String key, String value); Future<void> remove(String key); Iterable<String> keys(); }
class SavedEvent { final Map<String, dynamic> event; final List<EventAnnouncement> announcements; final DateTime savedAt; }
class EventCache {
  EventCache(this.store, {DateTime Function()? now});
  static const prefix = 'event_cache_v1_'; static const maxEvents = 10;
  SavedEvent? read(String eventId);                                   // null on missing or unreadable JSON (never throws)
  Future<void> write(String eventId, Map<String, dynamic> event, List<EventAnnouncement> announcements);
  Future<void> clearAll();                                            // sign-out
  Future<void> prune({required Set<String> keepEventIds});            // drops events not in the set or ended > 7 days ago; keeps at most maxEvents (most recently saved)
}

// guide.dart — pure functions, all take `now` (UTC) explicitly
enum GuidePhase { before, onNow, ended, cancelled }
GuidePhase guidePhase({required DateTime startsAt, required DateTime endsAt, String? status, required DateTime now});
({int value, String unit}) startsIn(DateTime startsAt, DateTime now);   // unit: 'days' | 'hours' | 'minutes'; rounded down; minimum 1 minute
bool isEventToday({required DateTime startsAt, required DateTime endsAt, required DateTime now});
  // true from min(00:00 Yangon on the start date, startsAt - 6h) until endsAt
bool guideLinkVisible({required DateTime endsAt, required DateTime now});     // until endsAt + 7 days
({List<ScheduleItem> now, List<ScheduleItem> next}) nowAndNext(List<ScheduleItem> sessions, DateTime now, {int nextCount = 3});
class GuideHit { final String group; /* 'schedule' | 'lineup' | 'faq' | 'info' */ final int index; final String title; final String? snippet; }
List<GuideHit> searchEvent(EventSummary event, String query);          // case-insensitive, both languages, trims; empty query → []
```

Yangon offset is fixed +6:30 (same as the app's `toYangon`); put the constant in core so helpers and app agree.

- [ ] **Step 1:** Tests. Models: `ScheduleItem.id` parsed and absent → null; `MyTicket` with and without the three new keys from API JSON; `toJson`→`fromJson` round trip; a cache entry JSON lacking the new keys loads with nulls. Cache: write/read round trip; unreadable JSON → null; `clearAll` removes only prefixed keys; `prune` drops ended-8-days-ago, keeps ended-6-days-ago, keeps only `keepEventIds`, caps at 10 by most recent `savedAt`. Helpers: `guidePhase` at start−1s / start / end−1s / end and `status: 'CANCELLED'`; `startsIn` 3 days, 3 hours, 20 minutes, 30 seconds → 1 minute; `isEventToday` for a 19:00 event at 00:00 and 23:59 Yangon the day before and at 00:00 on the day, for a 03:00 event (window opens 21:00 the previous day), for a 3-day event on day 2, after the end; `nowAndNext` with overlapping sessions, sessions on the next day, none running, fewer than three next, a single session; `searchEvent` matching an English query against Myanmar-language fields' English counterparts and a Myanmar query against `titleMy`, FAQ answers, performer roles, practical info, with no duplicate hits.
- [ ] **Step 2:** Run — fails. **Step 3:** Implement. **Step 4:** `flutter analyze` zero warnings and `flutter test` in core, then `flutter test` in organizer_app and crew_app (unchanged, must pass). Commit `core: event guide models, cache and helpers`.

### Task 3: Tickets tab grouping, checked-in state, ticket screen

**Files:**
- Modify: `mobile/apps/user_app/lib/screens/tickets_screen.dart`, `ticket_screen.dart`, `lib/app/providers.dart` (only what grouping needs), arb files, CSV
- Test: `mobile/apps/user_app/test/widget_test.dart` (or a new `tickets_grouping_test.dart`)

**Interfaces:** Consumes Task 2 `MyTicket` fields, `guideLinkVisible`. Produces keys `ticketGroup-<eventId>`, `groupGuideLink-<eventId>`, `ticketCheckedIn`, `ticketGuideLink`; the guide link navigates to `/event/<eventId>/guide` (route added in Task 4 — until then the route may 404 in manual use; tests assert the pushed location).

Behaviour: pending payments and the offer banner stay at the top as today. Tickets are grouped by event: a header (cover, title, date, "Event guide" link when the caller holds a VALID or CHECKED_IN ticket in that group and `guideLinkVisible`), then one row per ticket (type, seat, comp label, status). Groups are split into Upcoming and Past as today, using the group's event end. Row and ticket screen states: VALID → as today; CHECKED_IN → "Checked in" (+ "at {time}" when `checkedInAt` is known) and, on the ticket screen, the line "This ticket has been used to enter" in place of the QR; REFUNDED → "Refunded"; anything else → "Cancelled". Ticket screen Directions uses `Venue.mapsUri` when the ticket carries venue coordinates/map link, else today's name search; the ticket screen gains the "Event guide" link under the same rule as the group header.

English strings: `eventGuide` "Event guide"; `checkedIn` "Checked in"; `checkedInAt` "Checked in at {time}"; `ticketUsed` "This ticket has been used to enter".

- [ ] **Step 1:** Tests (fail first): two tickets for one event render one group with two rows; groups ordered upcoming by start then past; a CHECKED_IN ticket shows `checkedIn`/`checkedInAt` on the row and the ticket screen, no QR, the `ticketUsed` line, and never the cancelled text; a VOID ticket still shows Cancelled, REFUNDED shows Refunded; guide link present for a valid ticket of an event that ended 6 days ago and absent at 8 days and for a group with only refunded tickets; tapping the link pushes `/event/<id>/guide`; the offline (from cache) banner still shows; pending payment tiles and offer banner unchanged.
- [ ] **Step 2:** Implement. **Step 3:** 2.0× sweep entries for the grouped Tickets tab and the checked-in ticket screen. **Step 4:** `flutter gen-l10n`, analyze, test. Commit `user app: tickets grouped by event, checked-in tickets shown as checked in`.

### Task 4: The guide screen

**Files:**
- Create: `mobile/apps/user_app/lib/screens/event_guide_screen.dart`, `lib/app/guide_providers.dart`
- Modify: `lib/app/router.dart` (route `/event/:id/guide` with the ticket redirect), `lib/app/providers.dart` (clear the event cache on sign-out), arb files, CSV
- Test: `mobile/apps/user_app/test/event_guide_test.dart`, FakeApi additions, sweep entries

**Interfaces:** Consumes Tasks 1–3. Produces `eventCacheProvider` (an `EventCache` over SharedPreferences), `guideProvider` (`FutureProvider.family<GuideData, String>` where `GuideData { EventSummary event; List<EventAnnouncement> announcements; DateTime? savedAt /* non-null when served from the saved copy */; bool neverSaved }`), `nowProvider` (`Provider<DateTime Function()>`, overridable in tests). Keys: `guideStatus`, `guideTickets`, `guideShowTicket`, `guideNow`, `guideNext`, `guideFullSchedule`, `guideVenue`, `guideDirections`, `guideAnnouncements`, `guideSeeAllAnnouncements`, `guideInfo`, `guideThanks`, `guideSavedCopy`, `guideNeverSaved`.

`guideProvider`: fetch `eventRaw` + `eventAnnouncements`; on success write the cache and return live data; on a network error return the saved copy (with `savedAt`) or `neverSaved`; on 403/404 from announcements with a live event, show the event with no announcements; other errors → the screen's error state with Retry. While the screen is visible, refetch every 5 minutes (timer cancelled on dispose; no refetch while offline is known from the last attempt less than 30 s ago).

Sections and rules exactly as the spec's "The guide" list. The section list is built as data (`List<GuideSection>` with an id and a builder) so later rounds can insert sections. The one gold button: "Show ticket" when the user has exactly one usable ticket; with several, rows are tappable and the screen has no gold button. Announcements show three, "See all" opens a sheet with the full list. Offline: Directions, Watch and See all are disabled with the note `needsConnection`.

English strings: `guideStartsInDays` "Starts in {count, plural, =1{1 day} other{{count} days}}" (same for hours, minutes); `guideOnNow` "On now"; `guideEnded` "Ended"; `guideCancelled` "This event was cancelled"; `yourTickets` "Your tickets"; `showTicket` "Show ticket"; `nowTitle` "Now"; `nextTitle` "Next"; `fullSchedule` "Full schedule"; `announcements` "Announcements"; `seeAll` "See all"; `goodToKnow` (reuse the existing key if present); `guideThanks` "Thank you for coming"; `recordings` (reuse if present); `savedCopy` "Saved copy · updated {time}. Newer announcements may exist."; `neverSaved` "Connect once to save this event for offline use."; `needsConnection` "Needs a connection".

- [ ] **Step 1:** FakeApi: `eventRaw`, `eventAnnouncements` (settable, 403, network failure), streams with a live session; fixtures: single-session concert, 3-day multi-session festival, seated gala with two tickets, online-only event, cancelled event, ended event with a recording.
- [ ] **Step 2:** Tests (fail first), with `nowProvider` pinned: status line for before (days/hours/minutes), on now, ended, cancelled; sections absent when empty (no sessions → no now/next; no announcements → no section; no practical info and no FAQ → no good-to-know); single ticket → one gold "Show ticket" opening `/ticket/:id`; two tickets → two rows, no gold button, seat labels shown, a checked-in one says so; now/next for the festival at a pinned time, a live session shows Watch, "Full schedule" lists by day; venue Directions uses the map pin; online-only shows Watch and no venue; cancelled shows only tickets and announcements; ended shows `guideThanks` and the recording, hides now/next; no usable ticket (none, or only refunded) → redirected to `/event/:id`; signed out → login; network failure with a saved copy → content plus `guideSavedCopy` with the time, Directions/Watch/See all disabled with `needsConnection`; network failure and nothing saved → `guideNeverSaved`; announcements 403 → guide without announcements; a successful load writes the cache (assert through the provider); sign-out clears it; the 5-minute refetch fires once per interval and stops after dispose.
- [ ] **Step 3:** Implement. **Step 4:** Sweep entries (festival on now; seated two tickets; cancelled; ended; saved copy; never saved). **Step 5:** `flutter gen-l10n`, analyze, test. Commit `user app: event guide for ticket holders`.

### Task 5: Today card, home banner, background saving

**Files:**
- Modify: `tickets_screen.dart`, `home_screen.dart`, `lib/app/guide_providers.dart`, arb files, CSV
- Test: `mobile/apps/user_app/test/today_test.dart`

**Interfaces:** Consumes `isEventToday`, `EventCache`, `myTicketsProvider`. Produces `todayEventsProvider` (events from the user's usable tickets for which `isEventToday`, earliest first), `eventSaverProvider` (after tickets load online: for up to 10 upcoming events with a usable ticket, fetch and write any not saved in the last hour, sequentially, errors ignored; then `prune`). Keys: `todayCard-<eventId>`, `homeTodayBanner`.

English strings: `happeningToday` "Happening today"; `openGuide` "Open your guide".

- [ ] **Step 1:** Tests (fail first), `nowProvider` pinned: card shows inside the window and not the day before or after the end; two events today → two cards on Tickets (earliest first) and one home banner for the earliest; signed out → no banner; only refunded tickets → no card; tapping pushes `/event/<id>/guide`; after tickets load online the saver writes each upcoming event once (FakeApi counters), skips ones saved within the hour, never more than 10, and prunes an event that ended 8 days ago; a failing fetch for one event does not stop the others; nothing is fetched when the tickets came from the offline cache.
- [ ] **Step 2:** Implement (the saver must not delay or break the Tickets tab; it runs after the first frame). **Step 3:** Sweep entries (Tickets with a today card; home with the banner). **Step 4:** gen-l10n, analyze, test. Commit `user app: today card, home banner, events saved for offline`.

### Task 6: Search within an event

**Files:**
- Create: `mobile/apps/user_app/lib/widgets/event_search.dart`
- Modify: `event_guide_screen.dart`, `event_detail_screen.dart` (search action in the pinned top bar and the cover's action row), arb files, CSV
- Test: `mobile/apps/user_app/test/event_search_test.dart`

**Interfaces:** Consumes `searchEvent`. Produces `showEventSearch(BuildContext, EventSummary)` (a full-height sheet with a field and grouped results) ; keys `eventSearchAction`, `eventSearchField`, `searchHit-<group>-<index>`.

Tapping a hit closes the search and opens the item: a session → the session details sheet (title, time, location, description); a performer → the existing performer sheet; an FAQ → a sheet with the answer; info → a sheet with that practical-info field. No network use.

English strings: `searchThisEvent` "Search this event"; `searchEventHint` "Sessions, line-up, questions"; `searchNoResults` "Nothing found for “{query}”"; group titles reuse existing section titles (schedule, line-up, FAQ, good to know).

- [ ] **Step 1:** Tests (fail first): the action exists on the guide and on the event page; typing finds a session by location, a performer by role, an FAQ by a word in its answer, a practical-info field; a Myanmar query finds a Myanmar title while the app is in English; results are grouped with titles; no results state; tapping each kind of hit opens the right sheet; works from a saved copy with the network failing.
- [ ] **Step 2:** Implement. **Step 3:** Sweep entries (results, no results). **Step 4:** gen-l10n, analyze, test in user_app; `flutter test` in core, crew_app, organizer_app. Commit `user app: search within an event`.

### Task 7: Run-through on a local copy

- [ ] **Step 1:** Local API + user web build (as in earlier run-throughs), signed in as a buyer by phone OTP (dev echo) with: a ticket to a multi-session event set to be happening now (move its dates), two seated tickets to an event later today, a ticket to an event that ended yesterday with a recording, a ticket to a cancelled event; organizer announcements on the first.
- [ ] **Step 2:** Playwright 390×844, en and my: home banner; Tickets tab grouped with today cards; guide in each state; announcements sheet; full schedule; check a ticket in through the crew endpoint → refresh → "Checked in at …" on the guide, the row and the ticket screen; undo → valid again; search with hits of each kind; block the network (route abort) → saved copy label and disabled actions; clear site data → "Connect once…". Verify with captured responses that the announcements endpoint returns 403 for a second buyer without a ticket.
- [ ] **Step 3:** Screenshots to `docs/design/event-guide/`, commit; list every visual problem seen.
