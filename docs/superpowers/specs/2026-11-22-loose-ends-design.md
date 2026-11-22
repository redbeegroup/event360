# Loose ends — short design (approved 2026-11-22)

Why: four open items left from the organizer growth and payment safety work.

## 1. Waitlist offer notices must not be lost
Today: offers commit, then `notifyOffers` fires notices fire-and-forget; a restart in between loses inbox, push and SMS.
- Write the inbox `Notification` row for `waitlist_offer` inside the same transaction that moves the entry WAITING -> OFFERED.
- New nullable column `waitlist_entries.offer_notified_at`. After commit, and on every sweep pass, select
  `status = OFFERED AND offer_notified_at IS NULL AND offer_expires_at > now`, claim each with a conditional update
  (mark first), then send push and SMS (awaited, errors logged).
- Decision (user): mark first, then send. Never two SMS for one offer; a crash between mark and send loses that one
  SMS/push, the inbox notice is already stored.
- A reopened offer does not clear the column, so it never re-sends the offer SMS. Admin switch `waitlistSms` unchanged.
- Expired / closed / reopened notices stay as they are (not made durable).

## 2. Late payment after the offer ran out
- `notifyExpired` / `notifyClosed`: when the entry has an order with a payment still in flight (not SUCCEEDED/FAILED),
  use different wording: reserved tickets were released; if the payment still goes through, tickets are issued if any
  are left, otherwise a refund. If the order is already PAID, send nothing.
- `settle`, branch where the money arrived but no tickets could be issued (order flagged for refund): notify the buyer
  "payment received, tickets sold out, refund on its way" (inbox + push, no SMS). Applies to every such order, not only
  waitlist ones.
- EN and MY texts.

## 3. Payout for an organizer with no sales yet
Server already accepts it; the admin Finance page only lists organizers with ledger rows.
- Admin organization page gets a "Record payout" form (existing `RecordPayout` component, owed taken from the payout
  summary, 0 for a new organizer, existing overpayment warning). Add an admin summary endpoint only if none is usable.
- `balances()` unchanged.

## 4. Flaky "day-before reminder" test
- Test neutralises other due events first and asserts on its own event.
- `sendReminders` batch gets `orderBy startsAt asc`.

Approaches: claim marker reusing the `reminderSentAt` pattern (chosen) vs a general outbox table (more machinery than
four notices need) vs send-then-mark (can double-send SMS; rejected by the user).

Constraints: keep the lock order in seat-claims.ts (waitlist entries last); no real SMS in tests; no provider calls
inside transactions; migrations additive.
