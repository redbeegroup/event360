# Payment safety fixes — design (short, approved 2026-11-22)

1. **Never expire a payment the provider reports as paid.**
   - Code: `PaymentsService.sweep()` (apps/api/src/modules/payments/payments.service.ts ~721-754).
   - When the provider query returns SUCCEEDED and `applyStatus` throws, the catch block must NOT call `applyStatus(EXPIRED)`.
   - Expiry for `tooOld` only happens when the provider says PENDING, or when the query itself failed (unreachable).
   - A SUCCEEDED-but-failing payment is retried on later passes.
   - After 2 h it also flags the order: needsReview, appending (not overwriting) the note "Provider reports paid (ref …) but settling failed: check".
2. **Poisoned holds can't starve expiry.**
   - The expired-holds query orders by `holdExpiresAt` ascending.
   - An order whose `releaseHold` throws is skipped for 10 minutes (per pod, in memory) and logged.
3. **Lighter user lock.**
   - In `WaitlistService.join`, `PaymentsService.createOrder` and `GuestsService.issue`, change the user-row lock from `FOR UPDATE` to `FOR NO KEY UPDATE`.
   - It still serialises one buyer's own actions, but no longer conflicts with the FK KEY SHARE that ticket inserts take.
   - Update the lock-order header in seat-claims.ts.

**Tests (API e2e), written first:**
- **Provider SUCCEEDED, applyStatus throws, payment > 2 h old:**
  - the payment is not EXPIRED;
  - the order is flagged for review;
  - a later pass, once applyStatus works, settles it.
- **One poisoned expired order:** another expired order still expires, and the poisoned one is skipped on the next pass.
- **join and settle for the same user in parallel:** no deadlock. Use the existing gate helper.

**Non-goals:** any change to provider adapters or refund logic.
