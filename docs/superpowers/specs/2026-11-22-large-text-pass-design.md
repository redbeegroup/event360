# Large-text pass — short design (approved 2026-11-22)

Why: at 2x system text size, parts of the apps are cut off or unreachable. No behaviour changes.

1. Ticket picker sheet (user app): above a text-scale threshold the footer (discounts, total, buy button) scrolls with
   the content instead of staying pinned, so every ticket card is reachable. At normal sizes it stays pinned.
2. Sold-out badge row in Myanmar at 2x: the badge may drop to its own line instead of overflowing.
3. Every screen of the user app, crew app and organizer app: widget tests open each screen at 390x844, text scale 2.0,
   in English and Myanmar, and fail on any overflow. Fix findings by wrapping, shrinking or scrolling.
4. Two test flakes seen once each: the seated waitlist test "a seated join that raced a release…" and a run where the
   local test database had lost its categories (seating suite failed reading `children`). Find the cause; fix it if it is
   in our tests or code.

Not included: site and portal; text sizes above 2x.
Approaches: fix per screen under an overflow test sweep (chosen) vs capping the app's text scale (hides the user's
accessibility setting; rejected).
Constraints: exactly one gold button per screen; layout at 1.0x text must not change; analyzer has no warnings.
