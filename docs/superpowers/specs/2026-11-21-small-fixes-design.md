# Small fixes after seating follow-ups — design (short, approved 2026-11-21)

**Why:** close the leftover items from the seating follow-ups before new feature work.

1. **Promo rejected at order time, in Myanmar.**
   - `createOrder` currently throws `BadRequestException(r.reason)` (apps/api/src/modules/payments/payments.service.ts:165).
     - Change it to a 400 body `{ message: r.reason, reasonCode: r.reasonCode }`.
     - Old clients keep reading `message`.
   - The Flutter `ApiException` carries `reasonCode` from the error body.
   - The seat picker and the event-detail checkout sheet map it with `promoReasonText` (mobile/apps/user_app/lib/app/promo_text.dart). Any other error falls back to today's behaviour.
   - Tests:
     - API e2e: order with a used-up code gives 400 with `reasonCode: 'USED_UP'`.
     - Widget test: in MY, a used-up code at order time shows the Myanmar text.
2. **Late payment counts the promo use.**
   - In the late-payment branch of settle (payments.service.ts ~519-560), when an order that used a promo code becomes PAID after its hold expired, increment `promo_codes.used` by 1.
     - Expiry had given the use back, so this re-takes it.
     - Do it even if this pushes `used` above `max_uses`: the buyer has paid and the discount was valid at order time.
   - This applies to both late-payment outcomes, tickets issued and the "sold out, needs review" path, because the order is PAID either way.
     - A later admin refund keeps the use, as already decided.
   - Tests (API e2e):
     - A code with uses left goes 1 → 0 on expiry, then back to 1 on late pay.
     - A code at its limit ends above the limit, with the order PAID.
3. **Revoked comp seat takes the current rule.**
   - `GuestsService.revoke` (apps/api/src/modules/seating/guests.service.ts ~173) puts the seat back to GUEST_HOLD and keeps its old `ticket_type_id`.
     - Set `ticket_type_id` from the current `event_sections` rules instead: a row rule wins over a section rule, otherwise NULL. Use the same rule lookup as `returnSeatsToSale` in seat-claims.ts, and share the SQL fragment rather than copy it.
     - The seat stays GUEST_HOLD with its label.
     - Recount the old and the new type.
   - Test (API e2e): reassign the comp's row to another type, revoke, and the seat is GUEST_HOLD with the new type id. Counters are correct.
4. **Missing app tests** (seat picker promo re-check):
   - A poll that changes a selected seat's price or type triggers a re-check.
   - A code applied before the event loads is checked once the event resolves.

**Non-goals:** minimum app version check (goes with shipping the apps); any refund behaviour change.

**Build:** one task by an implementer, a task review, push to dev, prod only when asked.
