# Organizer app: the business view — design

Date: 2026-11-23. Status: awaiting approval.

## Why

Round one made the organizer app useful at the door. Away from the venue an organizer wants to know how an event is
selling, find a particular order when a buyer calls, and see what Event 360 owes them. Today the app shows revenue as
one number and the last ten orders; everything else needs the portal.

## Goals

- Per event: sales totals, sales per ticket type, and every paid-for order, searchable.
- Per organization: what was earned, what was paid out, what is owed, and the payout history.
- An organizer can answer "did my payment go through?" from their phone, including the awkward cases Event 360 has
  flagged for review (paid but sold out, paid twice, amount mismatch).

## Not in this round

- Refunds, cancelling orders, resending tickets, or any other action on an order (view only).
- CSV export (stays on the portal).
- Orders across all events of an organization in one list.
- Charts over time.
- Free registrations and guest tickets in the order list (those people are in the Guests tab).

## Must not happen

- A manager seeing payouts (owners and finance only, as the server and portal already enforce).
- A buyer's full phone number in the order list or order details. Phones are masked exactly as the portal's sales
  section does (`maskPhone`).
- The new server endpoint exposing another organization's orders, internal review notes, provider references or
  who recorded a payout.
- Any change to how orders, payments or payouts are created or settled. The server addition is read-only.

## Decisions made with the user

- Scope: a Sales tab per event with an Orders list, and an organization Payouts screen.
- Orders: paid-for orders only; search by buyer name, phone or order number; filters Paid, Refunded, Waiting for
  payment, Not completed; a badge on orders Event 360 has flagged for review.
- Buyer phones masked; search still matches the full number. The Guests tab is unchanged.
- View only. No CSV.

## Approaches considered

1. **A new organizer orders endpoint with cursor paging, searched on the server (chosen).** Events can have thousands
   of orders; the list loads 30 at a time and search runs in the database, so a masked phone can still be found by
   its full digits. Cost: one new read-only endpoint, a detail endpoint and one database index.
2. **Raise `sales.recent` from 20 to "all" and filter in the app.** No new endpoint, but the whole order history
   would travel on every Overview refresh, and searching masked phones by number would be impossible. Rejected.
3. **Reuse the admin finance orders endpoint with an organization filter.** It has no paging, no item details, and
   returns review notes and provider references meant for platform staff. Rejected.

## What gets built

### Server (read-only additions, `apps/api`, payments module)

`GET /organizations/:orgId/events/:eventId/orders` — roles OWNER, MANAGER, FINANCE (`ORG_VIEWERS`); 404 when the
event is not in that organization.

- Scope: orders of the event with `totalMmk > 0` and `channel != 'COMP'`.
- Query: `status` = `paid` (PAID) | `refunded` (REFUNDED) | `pending` (PENDING_PAYMENT) | `incomplete` (FAILED,
  EXPIRED, CANCELLED); omitted = all of those. `q` (trimmed, max 60): matches buyer display name (contains,
  case-insensitive), buyer phone (digits of `q`, at least 4, contained in the stored number; a leading `09` also
  matches numbers stored as `+959…`: phones are stored in E.164, so strip the leading `0` before matching), or the
  order number (first 8 characters of the order id, case-insensitive prefix; `id` is a uuid column, so this needs
  `id::text ILIKE` in raw SQL or an equivalent — builder's choice). An unknown `status` value is a 400. `limit` default 30, max 100. `cursor` opaque.
- Order: `createdAt` descending, then `id` descending (keyset paging; no offset).
- Response: `{ orders: OrderRow[], nextCursor: string | null }` with
  `OrderRow = { id, number, status, needsReview, createdAt, paidAt, totalMmk, discountMmk, quantity,
  buyer: { name: string | null, phone: string | null /* masked */ } }`. `number` is the first 8 characters of the id,
  upper-cased.

`GET /organizations/:orgId/events/:eventId/orders/:orderId` — same roles and scope; 404 otherwise. Returns the row
plus `subtotalMmk`, `commissionMmk`, `promoCode` (the code text or null), `groupDiscountBp`,
`items: [{ ticketTypeId, name, nameMy, quantity, unitPriceMmk, seats: [{ label, labelMy }] }]`,
`payments: [{ provider, status, createdAt }]` (newest first, at most 5),
`refunds: [{ status, amountMmk, createdAt, completedAt }]`, and `tickets: { total, valid, checkedIn, void }`.
Seat labels come from the event's seats by `OrderItem.seatKeys` (as the buyer's own order view does), falling back
to the key. Not returned: `reviewNote`, `providerRef`, refund `reason`/`reference`/`error`, any user id.
`holdExpiresAt` is included on rows with status PENDING_PAYMENT.

Migration (additive): index on `orders (event_id, created_at, id)`.

`sales` and `payouts/summary` are used as they are.

### App: Sales tab on the event screen

Tab order: Overview, Guests, Seats (when there is a map), **Sales**, Door, Announce, Promos. Shown to everyone who
can open the event.

- Totals (from `sales`): Paid orders, Gross sales, Commission, Net to you, Refunded (count · amount). Wording follows
  the portal. "Gross sales" here counts paid orders only (after discounts); a caption says so, because the Payouts
  screen's per-event figure is before refunds. Net is the same number in both places. All amounts in MMK through
  the app's existing money formatter.
- Ticket types (paid types only): name, current price, "next price {amount} on {date}" when scheduled, sold of
  quantity with the existing bar, revenue. An event with no paid ticket type shows "This event has no paid tickets"
  instead of totals and list.
- **Orders** section: search field, filter chips (All, Paid, Refunded, Waiting for payment, Not completed), list
  loading 30 at a time as the user scrolls, pull to refresh. Row: buyer name (else masked phone), order number,
  quantity, total, time, status badge; a "Being reviewed" badge whenever `needsReview` is set, whatever the status.
  A buyer with neither name nor phone shows as "Walk-up". "Waiting for payment" rows show when the hold runs out.
- Tap a row → order sheet: number, status, buyer name and masked phone, created and paid times, each item with
  quantity, unit price and seats, subtotal, discount (with the promo code or "Group discount" when present), total,
  commission, payment attempts (wallet and result), refunds (amount and state), and how many of its tickets are
  checked in. When `needsReview`: a neutral note "Event 360 is reviewing this payment. If money needs to go back
  to the buyer, we will refund it." (The flag covers several cases — paid but sold out, paid twice, amount
  mismatch — and the reason text is internal, so the app does not guess.) Refund states are shown in plain words:
  PENDING and FAILED → "Refund in progress", MANUAL → "Event 360 is returning it by hand", SUCCEEDED → "Refunded".
  Refunds are always for the whole order.
- Overview keeps its ten recent orders and gains an "All orders" link that opens the Sales tab.

### App: Payouts screen

Opened from the events list menu, entry visible only to owners and finance (`OrgMembership.canSeePayouts`); the route
redirects anyone else to the events list. Data: `payouts/summary` for the selected organization.

- Tiles: Earned, Paid out, Owed to you; when owed is negative, "You owe Event 360 {amount}" instead.
- When `reconciled` is false: the portal's reconcile note.
- The organization's name is shown under the title (the screen follows the organization selected on the events
  list).
- By event: title, net, expandable to "Sales before refunds" (the summary's gross), discounts, commission, refunded.
- Payout history: date, amount, method (Bank transfer, KBZPay, WavePay, Cash, Other), reference, note; voided
  payouts struck through with "Voided" and the reason. Empty state "No payouts yet."

## Build notes

- Server: methods beside `eventSales` in the payments service; controller routes beside the existing organizer sales
  routes; `maskPhone` from `common/util.ts`; seat labels through the same helper the guest list uses. e2e tests in
  `apps/api/test`.
- `event360_core`: models `EventSales`, `SalesTicketType`, `OrgOrderRow`, `OrgOrderPage`, `OrgOrderDetail`,
  `PayoutSummary`, `PayoutEventRow`, `PayoutRow`; API methods `eventSales`, `eventOrders`, `eventOrder`,
  `payoutSummary`; `OrgMembership.canSeePayouts`. `recentOrders` stays for Overview.
- Organizer app: `sales_tab.dart`, `payouts_screen.dart`, route `/payouts`; strings in English and Myanmar, added to
  the wording review sheet; the new screens join the 2× text sweep.
- The list uses the same patterns as the Guests tab: lazy list, busy guards, snackbars through the tab's messenger.

## Testing

- API e2e: scope (other organization's event → 404; comp and free orders excluded), each status filter, search by
  name, by full phone digits against a masked result, by order number, paging through 70 orders with no repeats or
  gaps including ties on `createdAt`, masked phone in list and detail, forbidden fields absent, roles (crew and
  outsiders 403), detail of a seated order shows seat labels, a paid-not-issued order shows `needsReview`.
- App widget tests: totals and per-type rows; no-paid-types state; search, each filter, paging on scroll, pull to
  refresh; order sheet contents incl. the refund note; Payouts tiles incl. negative owed, voided payout, empty
  history; menu entry and route hidden from managers; 2× sweep in English and Myanmar.
- Run-through on a local copy with screenshots, as in round one.

## Left to the builder

Widget structure, provider layout for paging, exact Myanmar wording, cursor encoding, and how the order sheet lays
out long item lists.
