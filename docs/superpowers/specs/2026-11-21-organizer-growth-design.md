# Organizer growth tools — design

**Status:** approach chosen by the user ("option 1": all four, smallest useful version each), 2026-11-21. Waitlist SMS: user chose "A" (SMS on, one per offer, admin switch). Design awaiting approval.

## Why
Organizers need to sell more tickets and to trust Event 360 with their money. These four tools target the gaps the code has today:
- a sold-out type just stops selling;
- prices can't change by date on one ticket type;
- there is no automatic quantity discount;
- organizers can't see what they are owed. Only admins see balances (Admin → Finance).

## Goals
1. **Waitlist.** Buyers can join a waitlist for a sold-out ticket type. When tickets come back, people are offered them in order.
2. **Timed prices.** A ticket type's price can step up on dates (early bird → regular → late). This works for standing and seated types.
3. **Group discount.** An automatic per-event discount for buying N or more tickets in one order.
4. **Payouts summary.**
   - Organizers see per-event and total sales, commission, refunds, paid out and still owed.
   - Admins record payouts they have made outside the system.

## Non-goals
- Paying organizers through a provider. Payouts stay "report only", as decided in Phase 2.
- Waitlists for free events. Free types can be joined, but this is not a design driver.
- Price steps for free types.
- Stacking a group discount with a promo code.
- Push-based waitlist delivery. Firebase isn't set up yet; push is used automatically once it is.

## Anti-goals
- A waitlist that lets someone outside the line grab freed tickets during an offer window. That makes the waitlist pointless.
- A price change mid-checkout that charges the buyer differently from the price they saw.
- Payout numbers that disagree with the admin balances report, which is built from the ledger.

## Constraints
- **Existing payments rules:**
  - Money is BigInt MMK.
  - The fee/commission comes from `FeeService` on the discounted subtotal and is frozen on the order.
  - The order price is frozen in `order_items.unit_price_mmk`.
  - The ledger lives in `ledger.ts`, with accounts `organizer_payable:<org>`, `platform_commission` and `provider_clearing:<P>`.
- **Lock order** (seat-claims.ts header). Any new row lock must fit into it: user → event row → payment → order → standing ticket types in id order → promo → seats → seated types.
- **Text:** all text in English and Myanmar. New Myanmar strings also go into `docs/i18n/seating-my-review.csv`.
- **Notifications:** sent through `NotifyService`, which covers inbox, push when configured, and optional SMS. SMS costs money on prod.

## Approaches considered
- **All four, smallest version each (chosen).** They share checkout pricing and organizer screens, so checkout is reworked only once.
- **Revenue first** (prices and discounts now, waitlist and payouts later). Faster first release, but checkout pricing would be touched twice.
- **Trust first** (payouts and waitlist now). Rejected because the pricing tools are the quickest wins.

## Design

### 1. Timed prices
- **Data:** a new `TicketPriceStep { ticketTypeId, startsAt, priceMmk }`, unique on (ticketTypeId, startsAt). `TicketType.priceMmk` stays as the price before the first step.
- **Current price:** the price of the latest step with `startsAt <= now`, or the base price. One shared function, `currentPrice(tt, steps, now)`, is used by:
  - the public event endpoints;
  - the seats endpoint `types[].priceMmk`;
  - `createOrder`;
  - `previewPromo`.
- The public event response adds `nextPrice: { priceMmk, startsAt } | null` so apps and the site can show "Price rises to X on <date>".
- **No mid-checkout surprises:**
  - The price is read when the order is created and frozen in `unit_price_mmk`. A step that passes during the 10-minute hold doesn't change that order.
  - Late payment keeps the frozen price.
- **Organizer UI:** in the event page's ticket type editor, add, edit and remove steps (date-time in Yangon time, price). Steps must be in the future when created, and on a paid type only. The organizer can't remove a step that is already in effect; that would rewrite history.
- **Ordering:** a type's seated colour and order are by price (`SEAT_PALETTE` by price order). Use the *current* price there.
- **Micro-caches:** the public event list and detail are cached 10 s, which is acceptable at a step boundary. The order uses the live price.

### 2. Group discount
- **Data:** `GroupDiscount { eventId, minQuantity, percentBp }`. Several tiers per event are allowed (5+ → 10%, 10+ → 15%), unique on (eventId, minQuantity).
- **Applies to:** paid orders on the total ticket count of the order (all types, seated and standing). The best matching tier wins.
- **Interaction with promo codes:**
  - If a promo code is also given, the larger discount applies and the other is ignored.
  - The promo use is only taken when the promo is the one applied.
  - `previewPromo` and the order response say which discount applied (`discountSource: 'GROUP' | 'PROMO'`).
- **Stored on the order:** `Order.discountMmk` already exists. Add `groupDiscountBp` so reports can attribute it. Commission is on the discounted subtotal, as with promos.
- **UI:**
  - Organizer: the event page's Promotions area gets a "Group discount" list (min tickets, %).
  - Buyers: the app checkout sheet and seat picker show "Group discount −X" automatically, plus a hint "Buy N+ tickets to save Y%" when a tier exists.
  - The site event page shows the tiers.

### 3. Waitlist
- **Data:**
  - `WaitlistEntry { id, ticketTypeId, userId, quantity (1..maxPerOrder), status: WAITING | OFFERED | PURCHASED | EXPIRED | LEFT, offeredAt, offerExpiresAt, orderId?, createdAt }`.
  - Unique on (ticketTypeId, userId) for active statuses.
  - Position is the order of `createdAt`.
- **Join:**
  - Requires sign-in.
  - Only allowed while the type is sold out for the public: no availability, or all availability reserved for offers.
  - Shows the user's place in line. "Leave waitlist" is available.
- **Offers, standing types:**
  - When availability appears (hold expiry, refund, free cancel, quota raised), the sweeper offers to the next WAITING entries whose quantity fits the free count.
  - Offered quantity is **reserved**: a new `TicketType.offered` counter, included in availability (`sold + held + offered + q <= quota`).
  - The offer lasts **30 minutes**.
  - Notifications go through NotifyService: inbox, push and **SMS**. SMS is sent only if SMS is enabled. Its short English text says "Tickets for <event> are available for you until <time>. Open Event 360."
  - When the offeree buys, `offered` moves to `held` in the same transaction as the order. If the offer expires, `offered` is released and the next person is offered.
  - An offeree may buy fewer than offered; the rest is released.
- **Offers, seated types:**
  - Freed seats are put in a new seat status `WAITLIST_HOLD`, with `ticket_type_id` and `waitlistEntryId`, for the offered quantity.
  - The offeree's seat picker shows those seats as theirs. They can keep them or swap to any other available seats of the same type.
  - On expiry the seats return to sale through `returnSeatsToSale`, then the next entry is offered.
  - `recountTicketTypes` counts WAITLIST_HOLD in `offered`.
- **Fairness:** while offers are outstanding, public availability excludes reserved quantity and seats. "Best available" skips WAITLIST_HOLD.
- **Organizer:** the event page shows a waitlist count per type, and the dashboard shows waitlist size. There is no manual reordering in v1.
- **Limits:**
  - One active entry per user per type.
  - The waitlist closes when sales end or the event starts. Remaining entries expire with an inbox message "Tickets didn't become available".

### 4. Payouts summary
- **Data:** `Payout { id, organizationId, amountMmk, paidAt, method (BANK | KBZPAY | WAVEPAY | CASH | OTHER), reference, note, createdById, voidedAt?, voidReason? }`.
- **Recording a payout (admin):** writes a ledger journal: debit `organizer_payable:<org>`, credit `payouts_cash`, a new account.
- **Voiding a payout (admin):** writes the reversing journal. Payouts are never deleted.
- **Organizer view:** a "Payouts" page for OWNER and FINANCE roles. It shows:
  - Totals: earned (net after commission and refunds), paid out, owed. These come from the same ledger as the admin balances report, so the numbers match.
  - A per-event table: gross, discounts, commission, refunds, net.
  - The payout history.
  - A CSV export.
- **Admin view:** Admin → Finance → balances gets "Record payout" (with confirm) and a payout list per organizer with Void. Recording more than is owed shows a warning but is allowed, for example to correct a mistake.

## Testing
- **API e2e for each part:**
  - **Timed prices:** a step boundary, with the price frozen during the hold and on late payment.
  - **Group discount:** tier choice, group vs promo (larger wins, promo use not taken when group wins), and commission on the discounted subtotal.
  - **Waitlist:**
    - join only when sold out;
    - an offer reserves quantity or seats, and the public can't take it;
    - offer expiry moves to the next person;
    - an offeree buying converts the reservation;
    - a seated swap;
    - closing at sales end;
    - no oversell under parallel claims.
  - **Payouts:**
    - record and void journals;
    - organizer totals equal the admin balances;
    - role checks: org FINANCE and OWNER only; recording is admin only.
- **Flutter widget tests:**
  - the price-step hint;
  - the group discount line;
  - join/leave waitlist and position;
  - the offer banner with a countdown;
  - a seat picker with offered seats.
- **Portal:** typecheck, build and Playwright screenshots of the new editors and the Payouts page.

## Decisions after the builder check (controller's calls unless marked)
1. **Waitlist reservation is immediate.** Every path that frees stock reserves it for the waitlist in the same transaction, while WAITING entries exist for that type. The paths are hold expiry or cancel, refund, free-ticket cancel, revoked comp released to sale, and a quota raise.
   - Standing types: the freed quantity moves to `offered`.
   - Seated types: the freed seats go to `WAITLIST_HOLD` (unassigned) instead of AVAILABLE.
   - The sweeper then assigns the reserved stock to entries in line order and sends offers.
   - There is no window in which the public can take freed stock.
   - New row locks follow the existing lock order. The waitlist entries are locked after seats (see the lock-order header in seat-claims.ts).
2. **Seated offers are the freed seats themselves.** There is no swapping in v1.
   - If fewer seats are freed than the next entry wants, that entry is offered what is there.
   - Unassigned `WAITLIST_HOLD` seats stay reserved until an entry takes them.
   - With no WAITING entries left, they return to sale through `returnSeatsToSale`.
3. **An offer is claimable only by its owner.**
   - The order-create request carries `waitlistEntryId`. The API checks the entry belongs to the user, is OFFERED and not expired.
   - The buyer may buy up to the offered quantity of that type, from `offered` or from their own WAITLIST_HOLD seats. They may add other types from normal sale.
   - Any unused offered stock goes to the next entry.
4. **Group discount counts paid-type tickets only.** It applies to the subtotal of paid items. It never applies to COMP orders.
5. **Payout totals come from the ledger.**
   - `organizer_payable:<org>` is the authority for earned, paid out and owed, the same source as the admin balances report.
   - The per-event table uses the same order aggregates the admin report uses today:
     - PAID and REFUNDED orders, excluding COMP;
     - refunds as the sale reversal;
     - commission net of refunds.
   - The page notes that the per-event figures are a sales breakdown.
   - A negative "owed" is shown as "You owe Event 360 X" with a note. It is not clamped.
6. **Seat colours are frozen.** The seated colour and palette order stay by the base `priceMmk`, so colours don't change when a price step passes. Price display uses the current price.
7. **Promo codes are applied to the current (stepped) price.** No minimum-spend rules exist.
8. **Waitlist SMS** (user decision: A).
   - One SMS per offer, sent only when SMS is enabled, plus inbox and push.
   - A new admin setting "Waitlist SMS" (on by default) can turn waitlist SMS off without disabling other SMS.

## Left to the builder
- Exact screen layouts and placement within existing pages.
- Sweeper cadence for offers. The existing 30 s payment sweeper loop is fine.
- Whether `TicketType.offered` is a column or derived. A column, maintained like `held`, is preferred for checkout speed.
