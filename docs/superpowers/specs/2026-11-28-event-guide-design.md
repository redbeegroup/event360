# Event guide for ticket holders — design (round 1 of 3)

Date: 2026-11-28. Status: awaiting approval.

This is the first of three rounds inspired by a conference companion app the owner reviewed. Round 2 (groups and
tracks, richer info hub, fuller session pages) and round 3 (who's attending, company directory, needs and leads)
are designed separately, later. Nothing here should make those harder.

## Why

Event 360 looks after a buyer up to the moment they hold a ticket, and again at the door. In between — on the day,
at the venue, often with poor signal — the app offers the same event page as before the sale, online only. A ticket
holder should be able to open one screen that answers: is it on, where do I go, what's happening now, did the
organizer say anything, where is my ticket.

## Goals

- A guide screen per event for people holding a ticket to it, useful before, during and after the event.
- It works with no signal on the installed app, like tickets do.
- Finding a session, performer or answer inside one event takes one search.
- Works for every event type using only what organizers already enter. No new organizer work.

## Not in this round

- Anything organizers must newly fill in (tracks, per-session dress codes, Wi-Fi fields, exhibitors): round 2 and 3.
- Offline on the web preview. The installed app only.
- Personal agendas, session reminders, ratings, photo galleries.
- Changing the public event page for people without a ticket (other than adding search).

## Must not happen

- The guide showing anything to someone who holds no ticket for that event (announcements are for ticket holders).
- A ticket that has been checked in being shown as "Cancelled" (today's bug).
- Stale saved information presented as current: a saved copy is always labelled with when it was saved.
- Saved event data surviving sign-out on a shared phone.
- Any change to buying, tickets, QR codes or check-in.

## Decisions made with the owner

- Scope of round 1: the guide ("Today"), offline event information, search within an event; all event types.
- The guide is offered by a card on the Tickets tab and a banner on the home screen on the day of the event; the
  app does not open straight into it.
- The checked-in ticket bug is fixed in this round.

## Approaches considered

1. **A separate guide screen built from the existing event data, cached on the phone (chosen).** One new screen,
   one small cache next to the existing ticket cache, two additive server fields and one new read-only endpoint.
2. **Turn the existing event page into the guide when the viewer holds a ticket.** Less navigation, but the event
   page is built around selling (ticket picker bar, price, waitlist) and is already the app's largest screen;
   mixing both roles makes each worse. Rejected.
3. **A downloadable offline "pack" per event with a service worker for the web.** Would give the web preview offline
   too, but is a much larger change to how the web build is served. Rejected for this round.

## What gets built

### Server (additive, `apps/api`)

- `GET /v1/me/events/:eventId/announcements` — signed-in user who holds at least one ticket for the event with
  status VALID or CHECKED_IN. The event is checked first (unknown → 404), then the ticket (none → 403). Returns the
  organizer's announcements for that event (the existing `Announcement` rows), newest first, at most 50:
  `{ id, title, titleMy, body, bodyMy, createdAt }`. Read-only; no change to how announcements are sent or to the
  inbox.
- `GET /v1/me/tickets`: each ticket gains `checkedInAt` (ISO time or null): the latest check-in's scan time that is
  not a duplicate and was not undone, fetched for all the user's tickets in one query. The existing fields,
  including `qr: null` for tickets that are not VALID, are unchanged.
- No other server change. The event detail endpoint is used as is; it already sends session ids.

### App (`mobile/packages/core`, `mobile/apps/user_app`)

**The guide** — route `/event/:id/guide`. Only for a signed-in user whose tickets (live or saved copy) include a
VALID or CHECKED_IN ticket for that event; anyone else is sent to the event page.

Sections, top to bottom, each shown only when it has content:
1. Header: event title, date, and a status line —
   before the start: "Starts in 3 days" / "Starts in 3 hours" / "Starts in 20 minutes";
   between start and end: "On now";
   after the end: "Ended";
   cancelled event: "This event was cancelled" (then only tickets and announcements are shown).
2. Your tickets: one row per ticket (type, seat or section), "Checked in at 19:02" once checked in, tap opens the
   ticket/QR.
   A single ticket shows its "Show ticket" button directly — the one gold button on the screen.
3. Now and next (events with two or more sessions): sessions running now, then up to three coming next, with time
   and location.
   A "Watch" button on a session that is live on stream (matched by session id through the existing streams
   endpoint), and a "Full schedule" link to the whole list grouped by day. After the end this section is hidden.
4. Venue: name, address, the organizer's directions text, and a Directions button that uses the venue's map pin
   (latitude/longitude) when present, else its map link, else a name search. Online-only events show the Watch
   entry instead.
5. Announcements for this event (the new endpoint), newest first, three shown with "See all".
6. Good to know: the practical info fields that are filled in, then FAQ.
7. After the end: a thank-you line, and the published recordings for ticket holders if any.

**Where it is offered**
- Tickets tab: tickets are grouped by event (one header per event with title, date, "Event guide" link; ticket rows
  under it). Order as today: pending payments, upcoming, past.
- On the day of the event — from 00:00 Yangon time on the start date (or 6 hours before the start, whichever is
  earlier) until the end — a card at the top of the Tickets tab and a banner on the home screen: "Happening today
  — {event}. Open your guide". With several events that day, one card each on Tickets and a single banner for the
  earliest on home.
- The ticket screen gains an "Event guide" link.
- The guide link stays on the event's group in the Tickets tab for 7 days after the end, then the group shows only
  the tickets (builder's call, confirmed with the owner's "reachable for a week").
- A ticket whose event ended earlier today moves to "Past" as it does now; the today card and the guide link still
  show until the rules above end them.
- Someone whose tickets for the event are all refunded or void has no guide; their ticket rows already say
  "Refunded"/"Cancelled". A ticket transferred away disappears from the list, as today.
- Signed-out users see no banner.

**Checked-in tickets** — the ticket screen and ticket rows show "Checked in" (with the time when known) for status
CHECKED_IN, not "Cancelled". No QR is shown for it, as today; a line explains "This ticket has been used to enter".

**Offline**
- Event details are saved on the phone (next to the ticket cache, same mechanism) for each event the user holds an
  upcoming ticket to, up to 10 events, fetched in the background after the tickets load and refreshed when the
  guide opens and every 5 minutes while it is open. Announcements for the event are saved with it.
- When a fetch fails for lack of network, the guide and the full schedule render from the saved copy with a line
  "Saved copy · updated {time}". If nothing was ever saved: "Connect once to save this event for offline use."
- Saved event data and announcements are removed on sign-out (today only the ticket cache is cleared there — this
  must be added) and when the event ended more than 7 days ago.
- The saved-copy line reads "Saved copy · updated {time}. Newer announcements may exist." when offline.
- Status lines use the phone's clock (as the rest of the app does).
- Directions, Watch and "See all" announcements need a connection and say so when offline.
- The web preview is unchanged: online only.

**Search within an event** — a search action on the guide and on the public event page. It searches, on the phone,
session titles, locations and descriptions; performer names and roles; FAQ questions and answers; practical info;
in both languages regardless of the app language. Results are grouped (Schedule, Line-up, FAQ, Good to know); a
result opens the matching item (session details sheet, performer sheet, the FAQ answer). Works offline on the
saved copy.

## Build notes

- `event360_core`: `ScheduleItem.id`; `MyTicket.checkedInAt`, `eventStatus`, `eventSlug` (the API already sends the
  last two; all three nullable and written to the ticket cache, so copies saved by older builds still load);
  `EventAnnouncement`; `Event360Api.eventAnnouncements(eventId)`; an `EventCache` store (JSON per event
  id with `savedAt`), built like the ticket cache.
- Pure helpers with unit tests: guide status line, the "today" window, now/next selection, in-event search.
- Strings in English and Myanmar, added to the wording review sheet. Times in Yangon time through the existing
  format helpers. One gold button per screen. The new screens join the 2× text sweep.
- Round 2 hooks: the guide's section list is data-driven so new sections (your track, info hub) slot in; nothing
  else is built ahead.

## Testing

- API e2e: announcements endpoint — holder gets the event's announcements in order; another event's are absent;
  no ticket → 403; only VOID/REFUNDED tickets → 403; signed out → 401; `checkedInAt` set after check-in and null
  again after undo; existing ticket fields unchanged.
- Unit: status line at each boundary; today window incl. events crossing midnight and multi-day events; now/next
  with missing end times and overlapping sessions; search across both languages.
- Widget: guide sections appear only with content; single-session, multi-session, seated, online, cancelled and
  ended events; no ticket → event page; checked-in ticket shows "Checked in" everywhere; Tickets tab grouping;
  today card and home banner inside and outside the window; offline — guide from saved copy with the label, never
  saved state, sign-out clears; search results and opening them; 2× sweep in both languages.
- Run-through on a local copy with screenshots in English and Myanmar, including airplane-mode behaviour as far
  as the web build allows, and the Android build's cache paths by unit test.

## Left to the builder

Widget structure, provider layout, cache key names, exact Myanmar wording, the look of the today card and banner
within the existing design tokens.
