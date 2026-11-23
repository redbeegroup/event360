# Organizer App: Business View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Sales tab with a searchable order list on each event, and an organization Payouts screen, in the organizer phone app.

**Architecture:** Two new read-only organizer endpoints (order list with keyset paging, order detail) and one index in the payments module; models and client methods in `event360_core`; `sales_tab.dart` and `payouts_screen.dart` in the organizer app, following the Guests tab's patterns.

**Tech Stack:** NestJS + Prisma (Postgres), Flutter, Riverpod 3, go_router, gen-l10n (en, my).

**Spec:** `docs/superpowers/specs/2026-11-23-organizer-app-business-view-design.md`

## Global Constraints

- Server additions are read-only: no change to how orders, payments, refunds or payouts are created or settled; no existing route or response changes.
- Order list/detail scope: `totalMmk > 0` and `channel != 'COMP'`, event must belong to `:orgId` (else 404); roles `ORG_VIEWERS`.
- Never returned to organizers: full buyer phone (always `maskPhone`), `reviewNote`, `providerRef`, refund `reason`/`reference`/`error`, any user id.
- Payouts: visible to `ORG_OWNER` and `ORG_FINANCE` only, in menu and route.
- View only in the app: no action buttons on orders or payouts.
- Migration additive; passes the CI drift check; lock order in `seat-claims.ts` untouched (no locks taken).
- Every new string in `app_en.arb` and `app_my.arb` and in `docs/i18n/seating-my-review.csv` (`where` = `organizer app`); Myanmar natural, no uppercase styling.
- New screens pass the 2.0× overflow sweep (en, my, 390×844); layout of existing screens at 1.0× unchanged except Overview's new "All orders" link and the extra tab.
- `flutter analyze` zero warnings; `flutter test` passes in core, ui, organizer_app, user_app; `apps/api` `npx tsc --noEmit && npx jest` passes.
- No changes to `SeatMapView`, `SeatMapPainter`, `SeatState`, or anything under `mobile/apps/user_app`, `apps/web`, `apps/site`.
- Commit footer on every commit:
  `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01CsYsPiiALYTiE9YyJ6GZPD`.

## Review Focus

- Paging with many orders created in the same millisecond, or orders arriving while the user scrolls: no repeats, no gaps. (Task 1 test; Task 3 de-duplicates by id.)
- A search that looks like a phone number typed the local way (`09…`, with spaces) against numbers stored as `+959…`; a search of one or two digits; a search containing `%` or `_`. (Task 1)
- An organizer of organization A requesting an order id that belongs to organization B's event, through A's own event id. (Task 1)
- Search typed quickly while a slower earlier request is still in flight: the list must show the latest query's results. (Task 3)
- An organization with no sales and no payouts; a negative owed amount; a voided payout. (Task 4)

---

### Task 1: Organizer order list and detail endpoints

**Files:**
- Modify: `apps/api/prisma/schema.prisma` (Order: `@@index([eventId, createdAt, id])`), new migration `apps/api/prisma/migrations/<next timestamp>_orders_event_created_idx/migration.sql`
- Modify: `apps/api/src/modules/payments/payments.service.ts` (beside `eventSales`), `payments.module.ts` (beside the organizer sales route)
- Test: `apps/api/test/org-orders.e2e-spec.ts`

**Interfaces — Produces:**

```ts
// PaymentsService
orgOrders(orgId: string, eventId: string, q: { status?: 'paid'|'refunded'|'pending'|'incomplete'; q?: string; cursor?: string; limit?: number }):
  Promise<{ orders: OrgOrderRow[]; nextCursor: string | null }>
orgOrder(orgId: string, eventId: string, orderId: string): Promise<OrgOrderDetail>

type OrgOrderRow = { id: string; number: string; status: OrderStatus; needsReview: boolean; createdAt: Date; paidAt: Date | null;
  holdExpiresAt: Date | null /* only when PENDING_PAYMENT */; totalMmk: number; discountMmk: number; quantity: number;
  buyer: { name: string | null; phone: string | null /* maskPhone */ } }
type OrgOrderDetail = OrgOrderRow & { subtotalMmk: number; commissionMmk: number; promoCode: string | null; groupDiscountBp: number | null;
  items: { ticketTypeId: string; name: string; nameMy: string | null; quantity: number; unitPriceMmk: number; seats: { label: string; labelMy: string | null }[] }[];
  payments: { provider: string; status: string; createdAt: Date }[];            // newest first, max 5
  refunds: { status: 'PENDING'|'SUCCEEDED'|'FAILED'|'MANUAL'; amountMmk: number; createdAt: Date; completedAt: Date | null }[];
  tickets: { total: number; valid: number; checkedIn: number; void: number } }
```

Routes: `GET /organizations/:orgId/events/:eventId/orders` and `GET …/orders/:orderId`, `ORG_VIEWERS`, query validated by a DTO (`status` enum → 400 otherwise; `q` trimmed max 60; `limit` 1–100 default 30). `number` = first 8 chars of id upper-cased. Status map: `paid`→PAID; `refunded`→REFUNDED; `pending`→PENDING_PAYMENT; `incomplete`→FAILED, EXPIRED, CANCELLED; omitted → all six. Order `createdAt desc, id desc`; cursor = base64url of `createdAt ISO|id`; a malformed cursor → 400. Fetch `limit + 1` to compute `nextCursor`.

`q` matching (OR): buyer `displayName` contains (insensitive); phone — take the digits of `q`, if it starts with `09` drop the leading `0`, if it starts with `959` keep it, and when at least 3 digits remain match `phone contains`; order number — when `q` is 1–8 hex characters, `id::text ILIKE q || '%'`. Escape `%` and `_` in user input for the LIKE. Implementation choice for the id prefix: one raw query for matching ids combined with the Prisma `where`, or the whole list in `$queryRaw`.

- [ ] **Step 1:** Write `org-orders.e2e-spec.ts` (follow `payouts.e2e-spec.ts` for app bootstrap, org/owner/manager/finance creation and mock-paid orders). Cases: list returns paid orders newest first with `number`, masked phone (`/^09\d{2}•••\d{3}$/`) and no key named `reviewNote`, `providerRef`, `userId`, `phone` containing 8+ consecutive digits anywhere in the JSON; comp order and free CONFIRMED order absent; each `status` value returns only its statuses, `status=bogus` → 400; `q` by display name fragment (case-insensitive); `q=09 7xx xxx xxx` (the buyer's number typed locally with spaces) finds the order; `q=12` (2 digits, not hex-only-match) does not match by phone; `q` = first 8 chars of an id finds exactly that order; `q=%` returns nothing rather than everything; 70 orders (insert rows directly with 10 sharing one `createdAt`) paged with `limit=30` → 30+30+10, ids all distinct, order strictly `(createdAt desc, id desc)`, last `nextCursor` null; an order inserted between page 1 and page 2 does not cause a repeat; malformed cursor → 400; event of another org through own orgId → 404; order of another org's event through own event id → 404; crew member and outsider → 403; manager and finance → 200; detail of a seated order has seat labels and `tickets` counts; detail of an order with a FAILED then SUCCEEDED payment lists both newest first; a `needsReview` order returns `needsReview: true` and no note; PENDING_PAYMENT row carries `holdExpiresAt`, PAID row has it null.
- [ ] **Step 2:** Run `cd apps/api && npx jest test/org-orders.e2e-spec.ts` — fails (404 routes).
- [ ] **Step 3:** Add the index + migration (`CREATE INDEX "orders_event_id_created_at_id_idx" ON "orders"("event_id","created_at","id");` — check the real table/column names), run the CI drift command from `.github/workflows/ci.yml`.
- [ ] **Step 4:** Implement `orgOrders`, `orgOrder`, DTO and routes. Seat labels: resolve `OrderItem.seatKeys` through the event's seats as the buyer's own order view does in `payments.service.ts` (search for `seatKeys` near the order view), falling back to the key.
- [ ] **Step 5:** `npx tsc --noEmit && npx jest` (whole suite) passes. Commit `api: organizer order list and detail`.

### Task 2: Core models and API methods

**Files:**
- Modify: `mobile/packages/core/lib/src/org.dart`, `api.dart`
- Test: `mobile/packages/core/test/org_business_test.dart`

**Interfaces — Consumes:** Task 1 JSON; existing `sales` and `payouts/summary` JSON (read the services for exact fields). **Produces:**

```dart
// OrgMembership
bool get canSeePayouts => role == 'ORG_OWNER' || role == 'ORG_FINANCE';

class EventSales { final List<SalesTicketType> types; final int paidOrders, grossMmk, commissionMmk, netMmk, refundedOrders, refundedMmk;
  bool get hasPaidTypes; /* any type with priceMmk > 0 or basePriceMmk > 0 */ }
class SalesTicketType { final String id, name; final int priceMmk, basePriceMmk, quota, sold, revenueMmk; final int? nextPriceMmk; final DateTime? nextPriceAt; }
class OrgOrderRow { final String id, number, status; final bool needsReview; final DateTime createdAt; final DateTime? paidAt, holdExpiresAt;
  final int totalMmk, discountMmk, quantity; final String? buyerName, buyerPhone; }
class OrgOrderPage { final List<OrgOrderRow> orders; final String? nextCursor; }
class OrgOrderItem { final String name; final String? nameMy; final int quantity, unitPriceMmk; final List<({String label, String? labelMy})> seats; }
class OrgOrderDetail { final OrgOrderRow row; final int subtotalMmk, commissionMmk; final String? promoCode; final int? groupDiscountBp;
  final List<OrgOrderItem> items; final List<({String provider, String status, DateTime createdAt})> payments;
  final List<({String status, int amountMmk, DateTime createdAt, DateTime? completedAt})> refunds; final int ticketsTotal, ticketsValid, ticketsCheckedIn, ticketsVoid; }
class PayoutSummary { final int earnedMmk, paidOutMmk, owedMmk; final bool reconciled; final List<PayoutEventRow> events; final List<PayoutRow> payouts; }
class PayoutEventRow { final String eventId, title; final int grossMmk, discountMmk, commissionMmk, refundsMmk, netMmk; }
class PayoutRow { final String id, method; final int amountMmk; final DateTime paidAt; final String? reference, note, voidReason; final DateTime? voidedAt; bool get isVoided => voidedAt != null; }

// Event360Api
Future<EventSales> eventSales(String orgId, String eventId);                 // GET …/sales (recentOrders() stays as is)
Future<OrgOrderPage> eventOrders(String orgId, String eventId, {String? status, String? q, String? cursor, int limit = 30});
Future<OrgOrderDetail> eventOrder(String orgId, String eventId, String orderId);
Future<PayoutSummary> payoutSummary(String orgId);                           // GET /organizations/$orgId/payouts/summary
```

- [ ] **Step 1:** Tests: `fromJson` for each model from literal JSON copied from the server shapes (incl. `nextPrice: null`, `buyer.name: null`, voided payout, negative `owedMmk`, empty lists); `canSeePayouts` true for owner and finance, false for manager and crew; `eventOrders` sends only non-null query params (assert the request path/query with the adapter stub used by `org_event_night_test.dart`).
- [ ] **Step 2:** Run — fails. **Step 3:** Implement. **Step 4:** `flutter test` in core passes, `flutter analyze` zero warnings. Commit `core: organizer sales, orders and payouts models`.

### Task 3: Sales tab with order list and order sheet

**Files:**
- Create: `mobile/apps/organizer_app/lib/screens/event/sales_tab.dart`
- Modify: `event_screen.dart` (tab after Seats), `overview_tab.dart` ("All orders" link), `lib/app/providers.dart`, arb files, `docs/i18n/seating-my-review.csv`
- Test: `mobile/apps/organizer_app/test/sales_tab_test.dart`, FakeApi + sweep additions in `test/widget_test.dart`

**Interfaces:** Consumes Task 2. Produces `eventSalesProvider` (`FutureProvider.family<EventSales, EventKey>`); `SalesTab({required EventKey k})`; `String orderStatusText(L10n t, String status)` (reuse/extend the existing `orderStatusLabel`); `String refundStateText(L10n t, String status)` (PENDING, FAILED → in progress; MANUAL → by hand; SUCCEEDED → refunded). Keys: `tabSales`, `salesTotals`, `orderSearch`, `orderFilter-all|paid|refunded|pending|incomplete`, `orderRow-<id>`, `orderSheet`, `allOrdersLink`.

Order list state lives in the tab's `State` (not a provider): `query`, `status`, `rows`, `nextCursor`, `loading`, `error`, and a request sequence number so a slower earlier response is dropped. Search is debounced 350 ms. Loading more triggers when the list is within 300 px of its end; rows are de-duplicated by id when appended. Pull to refresh reloads totals and the first page.

English strings (Myanmar by the implementer): `tabSales` "Sales"; `paidOrders` "Paid orders"; `grossSales` "Gross sales"; `grossCaption` "Paid orders only, after discounts"; `commission` "Commission"; `netToYou` "Net to you"; `refundedLine` "{count} · {amount}"; `refunded` "Refunded"; `noPaidTickets` "This event has no paid tickets"; `nextPriceLine` "Next price {amount} on {date}"; `soldOf` "{sold} of {quota} sold"; `revenue` "Revenue"; `orders` "Orders"; `allOrders` "All orders"; `orderSearchHint` "Search name, phone or order number"; `filterAll` "All"; `filterPaid` "Paid"; `filterRefunded` "Refunded"; `filterPending` "Waiting for payment"; `filterIncomplete` "Not completed"; `orderNumber` "Order {number}"; `walkUp` "Walk-up"; `beingReviewed` "Being reviewed"; `reviewNote` "Event 360 is reviewing this payment. If money needs to go back to the buyer, we will refund it."; `holdUntil` "Hold ends {time}"; `ordersEmpty` "No orders yet"; `ordersNoMatch` "No orders match"; `loadMoreFailed` "Couldn't load more. Tap to retry."; `orderCreated` "Ordered {time}"; `orderPaid` "Paid {time}"; `subtotal` "Subtotal"; `discount` "Discount"; `discountPromo` "Discount ({code})"; `discountGroup` "Group discount"; `total` "Total"; `payments` "Payments"; `refunds` "Refunds"; `refundInProgress` "Refund in progress"; `refundByHand` "Event 360 is returning it by hand"; `refundDone` "Refunded"; `wholeOrderRefund` "Refunds are always for the whole order."; `ticketsCheckedIn` "{inCount} of {total} tickets checked in"; `seatsLine` "Seats: {seats}".

- [ ] **Step 1:** FakeApi: `sales` JSON (two paid types, one with `nextPrice`), `ordersData` (75 generated rows over all statuses, one `needsReview`, one with no name, one with neither name nor phone), `eventOrders` honouring status/q/cursor/limit and recording calls, optional per-call delay, `failOrdersOnce`; `eventOrder` returning items with seats, a promo discount, two payments, one refund.
- [ ] **Step 2:** Write `sales_tab_test.dart` (fails first): totals and caption; per-type row with next price line; event with no paid types shows `noPaidTickets` and no order list; first page shows 30 rows' worth lazily and scrolling loads the next page exactly once per page with no duplicate ids; filter chip sends the status and resets the list; typing sends one request after the debounce with `q`; a slow response for "ab" arriving after a fast one for "abc" does not replace the "abc" results; pull to refresh refetches; `needsReview` row shows `beingReviewed`; nameless row shows the masked phone, the one with neither shows `walkUp`; pending row shows `holdUntil`; load-more failure shows `loadMoreFailed` and a tap retries; tapping a row opens the sheet with number, masked phone, items with seats, `discountPromo`, total, both payments, `refundInProgress`/`refundDone` wording, `wholeOrderRefund`, tickets line, and `reviewNote` only for the flagged order; the sheet has no buttons other than close; Overview's `allOrdersLink` switches to the Sales tab; finance and manager both see the tab.
- [ ] **Step 3:** Implement. Put Sales after Seats in the dynamic tab list in `event_screen.dart` (keep the open tab stable when Seats appears late — extend the existing test). **Step 4:** Add Sales screens to the 2.0× sweep (totals, list with flagged row, filters, order sheet, no-paid-types state). **Step 5:** `flutter gen-l10n`, `flutter analyze` (zero warnings), `flutter test`. Commit `organizer app: Sales tab with orders`.

### Task 4: Payouts screen

**Files:**
- Create: `mobile/apps/organizer_app/lib/screens/payouts_screen.dart`
- Modify: `lib/app/router.dart` (route `/payouts` with redirect), `screens/events_screen.dart` (menu entry), `providers.dart`, arb files, CSV
- Test: `mobile/apps/organizer_app/test/payouts_screen_test.dart`, FakeApi + sweep additions

**Interfaces:** Consumes Task 2 `payoutSummary`, `canSeePayouts`. Produces `payoutSummaryProvider` (`FutureProvider.family<PayoutSummary, String /* orgId */>`); `PayoutsScreen`; keys `menuPayouts`, `payoutTile-earned|paidOut|owed`, `payoutEvent-<eventId>`, `payoutRow-<id>`.

English strings: `payouts` "Payouts"; `earned` "Earned"; `paidOut` "Paid out"; `owedToYou` "Owed to you"; `youOwe` "You owe Event 360 {amount}"; `reconcileNote` — copy the portal's reconcile note text from `apps/web/app/lib/i18n.ts` (the key used on the organizer payouts page when `reconciled` is false), en and my; `byEvent` "By event"; `salesBeforeRefunds` "Sales before refunds"; `discounts` "Discounts"; `payoutHistory` "Payout history"; `noPayouts` "No payouts yet."; `voided` "Voided"; `methodBANK` "Bank transfer"; `methodKBZPAY` "KBZPay"; `methodWAVEPAY` "WavePay"; `methodCASH` "Cash"; `methodOTHER` "Other"; `reference` "Reference"; `noSalesYet` "No sales yet".

- [ ] **Step 1:** FakeApi `payoutSummary` (two events, three payouts incl. one voided with a reason), settable to empty and to negative owed. Tests (fail first): tiles show the three amounts; negative owed shows `youOwe` with the absolute amount instead of the owed tile value; `reconciled: false` shows the note, true hides it; event row shows net and expands to the four lines; history rows show date, amount, method label, reference, note; voided row is struck through with `voided` and the reason; empty summary shows `noSalesYet` and `noPayouts`; the organization name is under the title; owner and finance see `menuPayouts`, manager does not; navigating to `/payouts` as a manager lands on the events list; switching organization and reopening shows the other organization's data; pull to refresh refetches; load error shows the retry state.
- [ ] **Step 2:** Implement. **Step 3:** Add to the 2.0× sweep (full summary, empty, negative owed). **Step 4:** `flutter gen-l10n`, analyze, test. Commit `organizer app: Payouts screen`.

### Task 5: Run-through on a local copy

- [ ] **Step 1:** Local API (with Task 1) + organizer web build as in the event-night run-through; seed paid orders across statuses (mock payments), one refunded, one flagged for review, a recorded payout and a voided one (local platform admin).
- [ ] **Step 2:** Playwright at 390×844, en and my: Sales totals; order list; each filter; search by name, by phone typed `09…`, by order number; scrolled to a second page; order sheet (plain, seated with discount, refunded, flagged); Payouts as owner; Payouts with negative owed if cheap; manager account with no Payouts entry. Verify the numbers on screen against the database (gross, commission, net, owed).
- [ ] **Step 3:** Screenshots to `docs/design/organizer-business-view/`, commit; list every visual problem seen.
