# Organizer app clean-up — short design (approved 2026-11-23)

Why: leftovers from the event-night and business-view rounds that an organizer would notice. No new features.
Server changes only add fields; nothing existing changes shape.

## Server (apps/api, additive)
- `GET …/events/:id/sales`: each `ticketTypes[]` item gains `nameMy: string | null`.
- `GET /organizations/:orgId/payouts/summary`: each `events[]` item gains `titleMy: string | null`. The CSV is unchanged.
- Organizer refusals gain a machine code beside the existing English `message` (response body field `reasonCode`,
  same convention as the buyer-side reasonCodes; message text unchanged):
  - seating hold/release/comps 409s: `SEATS_NOT_AVAILABLE`, `SEATS_NOT_HELD`, `SEATS_MUST_BE_HELD_FIRST`,
    `NO_SEAT_MAP`, `EVENT_ENDED` (cancelled or completed);
  - guest ticket revoke: `GUEST_ALREADY_CHECKED_IN`, `GUEST_ALREADY_REVOKED`, `GUEST_TICKET_NOT_FOUND` (404);
  - crew undo 409 "not checked in": `NOT_CHECKED_IN`.
- Portal (`apps/web/app/lib/i18n.ts`), Myanmar only: `pyTitle` "ငွေထုတ်ပေးမှုများ", `pyPaidOut` "ထုတ်ပေးပြီးငွေ",
  `pyHistory` "ငွေထုတ်ပေးမှု မှတ်တမ်း", `pyNone` "ငွေထုတ်ပေးမှု မရှိသေးပါ။" — the same wording the app now uses, so
  Payouts and Payments differ. Check every other `py*` Myanmar string and the admin finance payout strings for the
  old word and align them.

## App (mobile/packages/core, mobile/apps/organizer_app)
Clearer errors
- `ApiException` exposes `statusCode` and `reasonCode` (if it doesn't already). One helper
  `String errorText(L10n t, Object error)` used by every organizer screen's load-error and action-error path:
  401 → `sessionEnded` "Please sign in again"; 403 → `noAccess` "You no longer have access to this";
  404 → `notAvailable` "This is no longer available"; known `reasonCode` → its own string; network/timeout →
  the existing connection text; anything else → the existing generic text. Raw server English is never shown.
- A 401 that survives the token refresh signs the user out and returns to the sign-in screen with the
  `sessionEnded` message (one place: the session notifier / API client hook, not per screen).
- Load-error states for 403/404 show the message without a Retry button (retry cannot help); connection errors
  keep Retry.
Myanmar and numbers
- Sales and Payouts use `nameMy` / `titleMy` when the app language is Myanmar and the value exists.
- Counts in strings (`guestsCount`, `seatsSelected`, `seatsViewGuests`, legend counts, `soldOf`, `ticketCount`,
  `ticketsCheckedIn`, waitlist line, recipients) go through `formatAmount` so they get separators and the same digit
  style as money.
- Guest-ticket issue confirm dialog: button label on one line (shorter label or stacked full-width buttons); the
  phone number never breaks across lines (non-breaking spaces).
- Orders filter chips: the last chip is fully reachable in Myanmar (trailing padding at least the fade width).
Figures that look contradictory
- Overview tile "Orders" → `ordersAndRegistrations` "Orders and registrations" (en + my).
- Payouts by-event: the "Discounts given" line is separated from the sum (spacing, smaller footnote style).
Smaller rough edges
- Guest rows and the attendee sheet: when the seat label already starts with the ticket type name, don't print the
  type name twice.
- Seats tab kept alive across tab switches (selection, zoom, sub-view).
- Guests: after a failed refresh with earlier data, a persistent "Couldn't refresh. Showing earlier data." line
  (existing `refreshFailed`), cleared on the next success.
- Attendee sheet: top padding so the name doesn't touch the rounded edge.

Not included: the open menu covering the first event row; the tab strip scrolling in Myanmar.
Approaches: one shared `errorText` helper and additive server fields (chosen) vs per-screen fixes (drifts) vs
translating server messages on the server by Accept-Language (bigger change across the API; not needed).
Checks: API e2e for the new fields and codes; widget tests per item; 2x text sweep stays green; local run-through
re-shoot of the affected screens in en and my; dev first, prod on request.
