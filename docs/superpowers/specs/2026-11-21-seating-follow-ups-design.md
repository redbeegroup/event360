# Reserved seating follow-ups — design (short)

**Why:** reserved seating is live on prod. These close the gaps found while building it, before organizers run real seated events.

## Scope
1. **Portal map zoom.**
   - `SeatMapView` gets these controls:
     - +, − and Fit buttons;
     - mouse-wheel and pinch zoom;
     - drag to pan, plus Fit on load.
   - Zoom range: Fit down to 1× (whole map), up to 8×. The zoom level is kept while the data refreshes.
   - Box-select in the organizer's Guests mode moves to Shift+drag. Touch screens get a "Select area" toggle, which makes one-finger drag draw the box instead of panning.
   - Click and tap to select stay the same. The admin editor, Assign mode and the print-free views all get zoom.
2. **Promo code in the app seat picker.**
   - The bottom bar gets an "Add promo code" field.
   - The code is checked with the existing promo preview, which already accepts `seats`. The bar then shows the discount and the new total.
   - The code is sent with `createOrder`.
   - If the selection changes, the code is checked again. An invalid code shows the API's reason, in English and Myanmar.
3. **Dashboard seat-map preview.**
   - On the organizer event page in the portal, seated events get a small, read-only `SeatMapView` coloured by status: available, checkout hold, guest hold, sold.
   - It shows the counts beside it, and clicking it opens the Seats tab.
   - It reuses `GET seating`; there is no new endpoint.
4. **Give back a promo use on free-ticket cancel.**
   - When cancelling a ticket leaves its whole order cancelled (no VALID tickets left), and the order used a promo code, the API decrements `promo_codes.used`. This happens in the same transaction, never below 0.
   - **Refunds keep the use** (user decision, 2026-11-21).
   - E2E tests cover:
     - a 100% code with maxUses 1: cancel, and the code works again;
     - partial cancel of a 2-ticket order does not give the use back until the last ticket is cancelled;
     - an admin refund does not give the use back.
5. **Myanmar wording pass.**
   - Make the terms consistent across the API (PDF/labels), the portal, the site and the 3 apps. Seat, row, section, guest hold, complimentary, best available and sold out should each use the same Myanmar word everywhere.
   - Produce a review sheet, `docs/i18n/seating-my-review.csv`. Columns: key, English, Myanmar, app/screen. It lists every Myanmar string added by reserved seating, for a native speaker to correct.
   - Corrections they send back are applied in a later change.

## Non-goals
- A native-quality translation; I can't provide that.
- Zoom in the public site's static SVG.
- Changing refund behaviour.

## Approach
One plan with five independent tasks, built subagent-driven as before. Checks:
- API: e2e tests.
- Portal: typecheck/build and Playwright screenshots.
- App: widget tests.

The only other approach considered was splitting these into separate releases. That isn't worth it: each task is small and independent.

## Left to the builder
- Zoom implementation: an SVG viewBox transform vs a CSS transform. Use whichever keeps hit-testing and the row hit-rects correct.
- Exact preview size.
- Where the promo field sits in the seat picker bar.
