# Organizer Growth Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add timed prices, group discounts, a waitlist with reserved offers, and an organizer payouts summary to Event 360.

**Architecture:**
- The pricing helpers live in a new `pricing.ts` beside `promo.ts`. `createOrder`/`previewPromo` and every public price output use them.
- The waitlist is a new API module. It hooks into every path that frees stock, inside that path's transaction, and its sweeper turns reservations into offers.
- Payouts are ledger journals plus a `Payout` table, read through the same balances code the admin report uses.

**Tech Stack:** NestJS 10 + Prisma 6 (Postgres), Next 15 portal and site, Flutter (Riverpod 3), melos.

**Spec:** docs/superpowers/specs/2026-11-21-organizer-growth-design.md. Read the "Decisions after the builder check" section; it overrides the earlier sections where they differ.

## Global Constraints
- Money is BigInt MMK. Commission comes from `FeeService` on the discounted subtotal and is frozen on the order. Unit price is frozen in `order_items.unit_price_mmk`.
- Lock order (apps/api/src/modules/seating/seat-claims.ts header), extended:
  user → event row → payment → order → standing ticket types (id order) → promo → seats (seat_key order) → seated ticket types (id order) → waitlist entries (createdAt, id order).
- All user-facing text is in English and Myanmar. New Myanmar strings get rows in `docs/i18n/seating-my-review.csv` (key,english,myanmar,where).
- **Waitlist:**
  - Offers last 30 minutes.
  - One active entry per user per type.
  - Quantity is 1..maxPerOrder.
  - The waitlist closes at the type's sales end or the event start.
  - SMS is sent once per offer, only when SMS is enabled and the admin setting "Waitlist SMS" (default on) is on. Inbox and push are always used.
- **Group discount:**
  - Counts paid-type tickets only and applies to the paid subtotal.
  - Never applies to COMP orders.
  - When a promo code is also given, the larger discount wins. The promo use is taken only when the promo wins.
- **Timed prices:**
  - Steps only on paid types, and created only in the future.
  - Steps already in effect can't be removed.
  - Seat colours and palette order stay by base `priceMmk`.
- **Payouts:**
  - The ledger account `organizer_payable:<org>` is the authority.
  - New account `payouts_cash`.
  - Voids reverse the journal; payouts are never deleted.
  - A negative "owed" is shown as "You owe Event 360 X".
- Never push. Commit locally only; the controller pushes.

## Review Focus
1. **Price step during a checkout hold.** The buyer pays the frozen price, on on-time and on late payment. (Task 1 e2e.)
2. **Parallel buyers when one ticket frees up while a waitlist exists.** Nobody outside the line gets it, and there is no oversell. (Task 4 e2e: 20 parallel public orders against a freed ticket with one WAITING entry, all 409.)
3. **Offer expires while the offeree is at checkout with a hold.** Their existing hold stands until its own expiry. No double counting of `offered` and `held`. (Task 4 e2e.)
4. **Group discount + promo where they tie.** The promo is not applied and its use is not taken. (Task 2 e2e.)
5. **Payout recorded, then a refund.** Owed goes negative and the organizer page shows "You owe Event 360". (Task 6 e2e.)

---

### Task 1: Timed prices (API)

**Files:**
- Modify: `apps/api/prisma/schema.prisma`, with a new migration `20261128010000_price_steps`.
- Create: `apps/api/src/modules/payments/pricing.ts`, `pricing.spec.ts`.
- Modify:
  - the payments service (`createOrder`, `previewPromo`);
  - public event outputs in `apps/api/src/modules/events/events.service.ts`;
  - public seats `types[]` in `apps/api/src/modules/seating/event-seats.service.ts`;
  - the organizer ticket-type endpoints, wherever ticket types are created or edited (grep `ticketType.create`).
- Test: `apps/api/test/growth.e2e-spec.ts` (new).

**Interfaces:**
- Produces:
  - `model TicketPriceStep { id, ticketTypeId, startsAt DateTime, priceMmk BigInt }`, `@@unique([ticketTypeId, startsAt])`.
  - `currentPrice(base: bigint, steps: {startsAt: Date; priceMmk: bigint}[], now: Date): bigint`.
  - `nextStep(steps, now): {startsAt: Date; priceMmk: bigint} | null`.
  - Public ticket-type JSON gains `priceMmk` (current), `basePriceMmk` and `nextPrice: {priceMmk, startsAt} | null`.
  - Organizer endpoints: `PUT /v1/organizations/:orgId/events/:id/ticket-types/:ttId/price-steps` with body `{steps:[{startsAt, priceMmk}]}`. It replaces the future steps, keeps the steps in effect, and returns 400 for past or duplicate dates or a free type.

- [ ] **Step 1:** Write the unit tests in `pricing.spec.ts`:
  - `currentPrice` with no steps returns the base;
  - just before a step returns the base;
  - at the step returns the step price;
  - after two steps returns the latest;
  - `nextStep` returns the first future step.
- [ ] **Step 2:** Write the e2e tests in `growth.e2e-spec.ts`:
  - `price steps change the public price and the order price`;
  - `price is frozen for an order created before a step, also on late payment`. Use the mock provider. Move the clock by setting the step's `startsAt` through the API, then a direct DB update to the past.
  - `price-steps endpoint rejects past dates, free types, and removing a step in effect`.
- [ ] **Step 3:** Run them. They should fail. Then implement, and run `cd apps/api && npx jest test/growth.e2e-spec.ts src/modules/payments`.
- [ ] **Step 4:** Run the full API suite (`npx jest`). Commit `feat(pricing): timed ticket prices`.

### Task 2: Group discount (API)

**Files:**
- Modify: the schema, with migration `20261128020000_group_discounts`. Add `GroupDiscount` and `Order.groupDiscountBp Int?`.
- Modify: `pricing.ts`, `payments.service.ts` (`createOrder`, `previewPromo`), and the organizer endpoints in `apps/api/src/modules/orgtools/orgtools.module.ts`, next to the promo codes.
- Test: `growth.e2e-spec.ts`.

**Interfaces:**
- Produces:
  - `model GroupDiscount { id, eventId, minQuantity Int, percentBp Int }`, `@@unique([eventId, minQuantity])`.
  - `bestGroupTier(tiers: {minQuantity:number; percentBp:number}[], paidQty: number): number /* bp, 0 if none */`.
  - `GET` and `PUT /v1/organizations/:orgId/events/:id/group-discounts` with body `{tiers:[{minQuantity (2..100), percentBp (100..9000)}]}`. `PUT` replaces all tiers.
  - The order and promo-preview responses gain `discountSource: 'GROUP' | 'PROMO' | null`.
  - The public event JSON gains `groupDiscounts: [{minQuantity, percentBp}]`.

- [ ] **Step 1:** Write the unit tests for `bestGroupTier`: no tiers, below the lowest tier, exactly at a tier, and between tiers.
- [ ] **Step 2:** Write the e2e tests:
  - `group discount applies on paid quantity`. Use 5+ → 10% with 3 paid + 2 free tickets, and expect no discount.
  - `larger of group and promo wins; promo use only taken when promo wins`. Cover both directions, and a tie, where the promo is not applied.
  - `commission is computed on the discounted subtotal`.
  - `group discount never applies to comps`.
- [ ] **Step 3:** Watch the tests fail. Implement, then run the tests.
- [ ] **Step 4:** Run the full suite. Commit `feat(pricing): group discounts`.

### Task 3: Pricing UI (portal, app, site)

**Files:**
- Modify:
  - Portal: `apps/web/app/organizer/[orgId]/events/[id]/page.tsx` (the ticket-type editor gets a price-steps list; the promotions area gets a group-discount list), `apps/web/app/organizer/actions.ts` and `apps/web/app/lib/i18n.ts`.
  - App: `mobile/packages/core/lib/src/models.dart` (`TicketType.nextPrice`, `basePriceMmk`; `EventDetail.groupDiscounts`; `PromoCheck.discountSource`), `mobile/apps/user_app/lib/screens/event_detail_screen.dart`, `seat_picker_screen.dart` and the `.arb` files.
  - Site: `apps/site/app/[lang]/e/[slug]/page.tsx` and `apps/site/app/lib/i18n.ts`.

**Interfaces:** consumes the Task 1 and 2 endpoints and JSON fields.

- [ ] **Step 1:** Write the failing widget tests:
  - `price rise hint shows next price and date`;
  - `group discount line appears at the threshold and the hint below it`;
  - `group discount and promo: only the larger shows, labelled`.
- [ ] **Step 2:** Implement the app UI. In the checkout sheet and the seat picker bar, show:
  - "Group discount −X" when it applies;
  - "Buy N+ tickets to save Y%" when a tier exists and isn't reached.
- [ ] **Step 3:** Implement the portal editors and the site display:
  - the price under each ticket type shows "Rises to X on <date>";
  - the tiers appear in the tickets panel.
- [ ] **Step 4:** Verify:
  - `cd mobile && melos run analyze && melos run test`;
  - for portal and site, `npx tsc --noEmit && npx next build`;
  - portal Playwright screenshots of both editors against a local API (local DB only).
- [ ] **Step 5:** Commit `feat(ui): timed prices and group discounts`.

### Task 4: Waitlist core (API)

**Files:**
- Modify: the schema, with migration `20261128030000_waitlist`. It adds:
  - `WaitlistEntry`;
  - `WaitlistStatus` with values WAITING, OFFERED, PURCHASED, EXPIRED and LEFT;
  - `TicketType.offered Int @default(0)`;
  - the `SeatStatus.WAITLIST_HOLD` value;
  - `EventSeat.waitlistEntryId uuid?`;
  - a partial unique index on (ticket_type_id, user_id) WHERE status IN ('WAITING','OFFERED').
- Create: `apps/api/src/modules/waitlist/waitlist.service.ts` and `waitlist.module.ts`.
- Modify:
  - every path that frees stock: `releaseHold`, `refundOrder`, `TicketsService.cancel`, `GuestsService.release`, organizer quota raise, and `returnSeatsToSale` callers;
  - availability checks in `createOrder`, `registerFree` and `seat-claims`/best-available;
  - `recountTicketTypes`, which counts WAITLIST_HOLD into `offered`;
  - the payments sweeper, which runs `waitlist.assignOffers()` and `waitlist.expireOffers()`;
  - NotifyService usage;
  - the SMS settings, which get a `waitlistSms` boolean with default true.
- Test: `apps/api/test/waitlist.e2e-spec.ts`.

**Interfaces:**
- Produces:
  - `reserveFreed(tx, ticketTypeId: string, qty: number): Promise<number /* qty moved to offered */>`. Standing types: called after a path frees qty, under that path's existing ticket-type row lock. It moves up to the WAITING demand into `offered`.
  - `reserveFreedSeats(tx, seatIds: string[]): Promise<string[] /* seats kept as WAITLIST_HOLD */>`. Seated types: called by `returnSeatsToSale` before it marks seats AVAILABLE.
  - `assignOffers(now)` and `expireOffers(now)`, both run by the sweeper.
  - Endpoints:
    - `POST /v1/ticket-types/:id/waitlist {quantity}` returns `{entryId, position}`. It returns 409 unless the type is sold out for the public, or after sales close.
    - `DELETE /v1/ticket-types/:id/waitlist`.
    - `GET /v1/me/waitlist` returns the user's entries with status, position, `offerExpiresAt`, offered qty and offered seat keys.
  - `createOrder` accepts `waitlistEntryId`. Only the owner of an OFFERED, unexpired entry may use it. It allows up to the offered qty of that type, taken from `offered` (standing) or from the entry's WAITLIST_HOLD seats (seated). On success the entry becomes PURCHASED and any unused offered stock is passed on.
  - Organizer `GET .../events/:id/waitlist` returns counts per type.

- [ ] **Step 1:** Write the failing e2e tests in `waitlist.e2e-spec.ts`:
  - `join only when sold out; one active entry per user; quantity within maxPerOrder`;
  - `freed standing ticket is reserved for the line: 20 parallel public orders all 409, offeree can buy`;
  - `offer expires after 30 minutes and moves to the next entry` (set `offerExpiresAt` in the past and run `expireOffers`);
  - `offer expiring while the offeree holds a checkout does not double count`;
  - `seated: freed seats become WAITLIST_HOLD for the offeree; best-available and public claims skip them; offeree buys them`;
  - `partial offer when fewer seats free than wanted`;
  - `no WAITING entries: freed stock returns to public sale as today`;
  - `waitlist closes at sales end; remaining entries expire with an inbox message`;
  - `offer notification: inbox always; SMS only when SMS enabled and waitlistSms on` (stub fetch as the SMS tests do; never send real SMS).
- [ ] **Step 2:** Watch the tests fail. Implement with the lock order from Global Constraints. Run the waitlist, seating and payments e2e tests.
- [ ] **Step 3:** Run the full API suite 3 times. Commit `feat(waitlist): reserved offers for sold-out ticket types`.

### Task 5: Waitlist UI (app, portal)

**Files:**
- Modify:
  - Core: `mobile/packages/core/lib/src/api.dart` (`joinWaitlist`, `leaveWaitlist`, `myWaitlist`, and `createOrder(..., waitlistEntryId:)`) and `models.dart`.
  - User app: `event_detail_screen.dart` (on a sold-out type, "Join waitlist" with a quantity picker, then "You're #N in line · Leave"), `seat_picker_screen.dart` (offered seats preselected and marked "Reserved for you", with a countdown), a home/My Tickets banner "Tickets are waiting for you — 23:41 left", and the `.arb` files.
  - Portal: the event page (waitlist count per type), the dashboard (waitlist size) and Admin → Settings → SMS (the "Waitlist SMS" toggle), with i18n.

**Interfaces:** consumes the Task 4 endpoints.

- [ ] **Step 1:** Write the failing widget tests:
  - `join waitlist on sold-out type shows position`;
  - `leave waitlist`;
  - `offer banner shows countdown and opens checkout with waitlistEntryId`;
  - `seat picker preselects offered seats`.
- [ ] **Step 2:** Implement the app and portal parts. Verify with `melos run analyze && melos run test`, the portal tsc and build, and Playwright screenshots of the portal counts and the SMS toggle.
- [ ] **Step 3:** Commit `feat(ui): waitlist`.

### Task 6: Payouts (API)

**Files:**
- Modify: the schema, with migration `20261128040000_payouts`, which adds `Payout` and `PayoutMethod`.
- Modify: `apps/api/src/modules/payments/ledger.ts` (account `payouts_cash`), the admin finance endpoints in `payments.module.ts` (the balances code at about lines 275-290), and the organizer endpoints.
- Test: `apps/api/test/payouts.e2e-spec.ts`.

**Interfaces:**
- Produces, admin only:
  - `POST /v1/admin/finance/organizations/:orgId/payouts {amountMmk, paidAt, method, reference, note}`;
  - `POST /v1/admin/finance/payouts/:id/void {reason}`;
  - `GET /v1/admin/finance/organizations/:orgId/payouts`.
- Produces for organizers, OWNER and FINANCE roles (check the role names used by OrgAccessService):
  - `GET /v1/organizations/:orgId/payouts/summary` returns `{earnedMmk, paidOutMmk, owedMmk, events:[{eventId,title,grossMmk,discountMmk,commissionMmk,refundsMmk,netMmk}], payouts:[…]}`;
  - `GET …/payouts/summary.csv`.
- The admin balances response gains `paidOutMmk` and `owedMmk`, computed with the same function.

- [ ] **Step 1:** Write the failing e2e tests:
  - `recording a payout journals payable→payouts_cash and lowers owed`;
  - `voiding reverses it`;
  - `organizer summary equals admin balances for the same org`;
  - `refund after payout makes owed negative`;
  - `roles: org FINANCE/OWNER can read; MANAGER/CREW 403; only platform admin can record/void`;
  - `COMP orders excluded from per-event figures`.
- [ ] **Step 2:** Watch the tests fail, implement, then run the full suite. Commit `feat(finance): organizer payouts summary`.

### Task 7: Payouts UI and dev samples

**Files:**
- Modify:
  - portal: a new `apps/web/app/organizer/[orgId]/payouts/page.tsx` plus the nav link (OWNER/FINANCE only);
  - Admin → Finance, which gets a "Record payout" form with a confirm step (it warns but still allows an amount above owed) and a payout list with Void;
  - i18n.
- Create: `infra/samples/sample-growth.js`, dev only. It is modelled on `infra/samples/sample-seated.js`:
  - adds price steps to `sample-seated-gala` (VIP 45,000 → 55,000 on 2026-12-15);
  - adds group tiers (5+ → 10%) to it;
  - does nothing else.

**Interfaces:** consumes the Task 6 endpoints.

- [ ] **Step 1:** Implement the pages. Verify with the portal tsc and build, and Playwright screenshots of the organizer Payouts page (including a negative owed) and the admin record/void flow against a local API.
- [ ] **Step 2:** Run `node --check infra/samples/sample-growth.js`. Commit `feat(portal): payouts pages; dev growth sample`.
