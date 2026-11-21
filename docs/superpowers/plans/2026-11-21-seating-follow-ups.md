# Seating Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** close five reserved-seating gaps: portal map zoom, promo codes in the app seat picker, a dashboard seat-map preview, a promo use returned on free-ticket cancel, and Myanmar wording consistency with a review sheet.

**Architecture:** five independent tasks over the existing seating code:
- API: tickets.service cancel path.
- Portal: `SeatMapView`, `SeatsManager`, and the organizer event page/dashboard.
- Flutter: `seat_picker_screen.dart`, plus `Event360Api.checkPromo` gaining `seats`.
- i18n files across all apps.

**Tech Stack:** NestJS + Prisma (Postgres), Next 15 portal and site, Flutter (Riverpod 3), melos.

**Spec:** docs/superpowers/specs/2026-11-21-seating-follow-ups-design.md

## Global Constraints
- All user-facing text in English and Myanmar.
- Refunds keep promo uses. Only a free-ticket cancel that leaves the whole order with no VALID tickets returns a use, and never below 0.
- Zoom range: Fit (whole map) up to 8×. Zoom is kept across data refreshes.
- Box-select is Shift+drag on desktop. Touch screens use a "Select area" toggle. Plain drag pans.
- Preview statuses: available, checkout hold, guest hold, sold. Clicking opens the Seats tab. No new endpoint; reuse `GET seating`.
- Review sheet path: `docs/i18n/seating-my-review.csv`, with columns `key,english,myanmar,where`.
- Never push. Commit locally; the controller pushes.

## Review Focus
1. **Zoomed clicks:** a click at 3× zoom selects the seat under the cursor, not one offset by the transform. Test this in Task 1's Playwright check: zoom in, then click a known seat and assert its key.
2. **Stale promo after a seat change:** after the buyer changes seats, the old discount must not be shown or sent unchecked. Covered by a Task 2 widget test.
3. **Partial cancel of a 2-ticket promo order:** no use is returned until the last ticket is cancelled. Covered by a Task 4 e2e test.
4. **Admin refund of a promo order:** the use stays. Covered by a Task 4 e2e test.
5. **Unseated events:** the dashboard preview and zoom controls must not render, and nothing must error. Covered by a Task 3 Playwright step on an unseated event.

---

### Task 1: Portal map zoom

**Files:**
- Modify: `apps/web/app/components/SeatMapView.tsx`, `apps/web/app/components/SeatsManager.tsx`, `apps/web/app/components/SeatMapEditor.tsx` (only if it needs a prop change), `apps/web/app/lib/i18n.ts`.

**Interfaces:**
- Produces new `SeatMapView` props:
  - `zoomable?: boolean`, default true;
  - `boxSelect?: 'shift' | 'always' | 'off'`, default `'off'`;
  - `height?: number`, the viewport height in px.
- The existing `onToggle`, `onSectionClick`, `onRowClick`, `lang`, `ariaLabel` and `stageLabel` props are unchanged.
- Task 3 uses `zoomable={false}` for the preview.

- [ ] **Step 1: Implement zoom.**
  - Use a viewBox-based transform held in state (scale 1 = Fit, max 8).
  - Controls: +, −, Fit buttons; wheel zoom around the cursor; pinch with two pointers; drag to pan with the pointer.
  - Seat and row hit-testing must stay correct at every scale.
  - Keep the transform when props.data changes.
- [ ] **Step 2: Move rubber-band selection into `SeatMapView`, behind `boxSelect`.**
  - `'shift'` starts a box only with Shift held.
  - `SeatsManager` passes `'shift'`, or `'always'` while its new "Select area / ပိုင်းခြားရွေးရန်" toggle is on (for touch).
  - Plain drag otherwise pans.
- [ ] **Step 3: Verify.**
  - `cd apps/web && npx tsc --noEmit && npx next build`.
  - Playwright, against a local API on port 3901 with a local DB, a published theatre map and a seated event:
    - zoom to about 3× with the + button;
    - click a seat whose key you read from its `<title>`, and assert it is the selected seat;
    - Shift+drag selects several seats;
    - a plain drag changes the viewBox and selects nothing.
  - Screenshots go to the scratchpad dir named in the dispatch.
- [ ] **Step 4: Commit** `feat(portal): zoom and pan on seat maps`.

### Task 2: Promo code in the app seat picker

**Files:**
- Modify: `mobile/packages/core/lib/src/api.dart` (`checkPromo` gains an optional `List<String> seats = const []`, sent as `seats` when non-empty), `mobile/apps/user_app/lib/screens/seat_picker_screen.dart`, the `.arb` files, `mobile/apps/user_app/test/widget_test.dart`.

**Interfaces:**
- Consumes: `POST /v1/events/:id/promo-check {code, items, seats}`, which already accepts seats (apps/api/src/modules/payments/payments.module.ts:145), and `createOrder(..., promoCode:, seats:)`.

- [ ] **Step 1: Write the failing widget tests.**
  - `seat picker applies promo and sends it with the order`: with the fake API returning a discount, the bar shows the discounted total, and `createOrder` receives `promoCode`.
  - `changing seats re-checks promo`: after toggling a seat, `checkPromo` is called again with the new seats. The old discount is hidden until the check returns.
  - `invalid promo shows reason`: the API's reason text is shown, and no promoCode is sent.
- [ ] **Step 2:** Run `cd mobile && melos run test`. Expected: FAIL.
- [ ] **Step 3: Implement.** Add an "Add promo code" link in the bottom bar. It opens a small field with Apply and Remove buttons. Debounce the re-check by about 300 ms after seat changes.
- [ ] **Step 4:** Run `melos run analyze && melos run test`. Expected: PASS (infos only).
- [ ] **Step 5: Commit** `feat(app): promo codes in the seat picker`.

### Task 3: Dashboard seat-map preview

**Files:**
- Modify: `apps/web/app/organizer/[orgId]/events/[id]/page.tsx`, and `dashboard/page.tsx` if the event dashboard lives there (put the preview wherever the organizer's event overview counts are shown), `apps/web/app/lib/i18n.ts`.
- Optionally create: `apps/web/app/components/SeatMapPreview.tsx`, a server/client-light wrapper around `SeatMapView`.

**Interfaces:**
- Consumes:
  - `GET /v1/organizations/:orgId/events/:id/seating`, which returns the layout, seats with status, and type colours (see apps/api/src/modules/seating/event-seats.service.ts);
  - `SeatMapView` with `zoomable={false}`.

- [ ] **Step 1: Implement.**
  - For seated events, render a preview about 320 px tall, coloured by status:
    - available #3fae6a;
    - checkout hold #f2b84b;
    - guest hold #7a6cf0;
    - sold #9aa0a6.
  - Next to it, show a legend with counts, and wrap it in a link to `/organizer/[orgId]/events/[id]/seats`.
  - Render nothing for unseated events.
- [ ] **Step 2: Verify.**
  - Run typecheck and build.
  - Take Playwright screenshots of a seated event with some sold and held seats, and of an unseated event showing no preview and no console errors.
- [ ] **Step 3: Commit** `feat(portal): seat map preview on the event dashboard`.

### Task 4: Return the promo use on free-ticket cancel

**Files:**
- Modify: `apps/api/src/modules/tickets/tickets.service.ts` (`cancel`, ~line 144).
- Test: `apps/api/test/seating.e2e-spec.ts`, or the e2e spec where free-ticket cancel is tested.

**Interfaces:**
- Consumes: `promo_codes.used`. This is the same decrement SQL as `payments.service.ts:419`: `UPDATE promo_codes SET used = GREATEST(used - 1, 0) WHERE id = $1`.

- [ ] **Step 1: Write the failing e2e tests.**
  - `cancelling the last ticket of a 100% promo order gives the use back`:
    - a code with kind PERCENT, value 100 and maxUses 1;
    - buy 1 ticket, so the order is free;
    - a second buyer gets 'This code has been used up';
    - the first buyer cancels; the code's `used` is 0;
    - the second buyer can now use it.
  - `partial cancel keeps the use`: the order has 2 tickets. Cancel 1 and `used` is still 1. Cancel the second and `used` is 0.
  - `admin refund keeps the use`: a paid order with a 50% code, refunded by an admin. `used` is unchanged.
- [ ] **Step 2:** Run `cd apps/api && npx jest test/<spec>`. Expected: the first two tests FAIL and the refund test passes.
- [ ] **Step 3: Implement.** Inside the cancel transaction, after the order's status becomes CANCELLED because no VALID tickets remain, decrement `promo_codes.used` once when `order.promoCodeId` is set. It runs in the same transaction, under the existing order row lock.
- [ ] **Step 4:** Run the full API suite: `npx jest`. Expected: PASS.
- [ ] **Step 5: Commit** `fix(tickets): give a promo use back when a free order is fully cancelled`.

### Task 5: Myanmar wording consistency and review sheet

**Files:**
- Modify:
  - `apps/web/app/lib/i18n.ts`
  - `apps/site/app/lib/i18n.ts`
  - `mobile/apps/*/lib/l10n/app_my.arb` (regenerate l10n)
  - Myanmar strings in `apps/api/src/modules/seating/*`, if any
- Create: `docs/i18n/seating-my-review.csv`

**Interfaces:** none (text only). Keys are unchanged.

- [ ] **Step 1: Build a term table.**
  - List the Myanmar renderings currently used for: seat, row, section, stage, available, sold, sold out, held for guests, complimentary/guest ticket, best available, choose seats, wheelchair, restricted view, venue, seat map.
  - Pick one rendering per term: the most frequent one, or the most standard one if there's a tie.
  - Record the table at the top of the CSV as rows with key `TERM:<english>`.
- [ ] **Step 2: Apply the chosen terms** to every seating-related Myanmar string in all the files above.
- [ ] **Step 3: Write `docs/i18n/seating-my-review.csv`.**
  - Include every Myanmar string added or changed by reserved seating and by this plan, one row each: `key,english,myanmar,where`. `where` is one of `portal`, `site`, `user_app`, `crew_app`, `organizer_app`, `api`.
  - Quote fields as RFC 4180 CSV, UTF-8 without a BOM.
- [ ] **Step 4: Verify.**
  - `cd mobile && melos run analyze && melos run test`.
  - Portal and site: `npx tsc --noEmit && npx next build`.
  - `python3 -c "import csv;rows=list(csv.reader(open('docs/i18n/seating-my-review.csv',encoding='utf-8')));assert rows[0]==['key','english','myanmar','where'];print(len(rows))"`
- [ ] **Step 5: Commit** `chore(i18n): consistent Myanmar seating terms and review sheet`.
