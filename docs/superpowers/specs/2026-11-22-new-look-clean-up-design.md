# New-look clean-up — short design (approved 2026-11-22)

Why: sign-off of the visual refresh found six small display problems, now live on prod.
No behaviour changes except item 5. No new routes or endpoints.

1. Site seat map: labels of seated sections in the right half end at the section's right edge, so long names grow inward.
2. App Discover at 2x text size in Myanmar: reproduce, find the overflowing row, let it wrap or shrink.
3. Myanmar "Get tickets": "လက်မှတ်ယူမည်" in app and site (also reads right for free events).
4. App dark mode: lighter chip border so the outline is visible.
5. App, events with seats AND standing tickets: the gold button opens a chooser with "Pick seats" and
   "Standing tickets", each with its starting price. Seats-only and standing-only events unchanged.
6. App ticket picker sheet: scrolls and lifts above the keyboard so promo field and total stay visible.

Approaches: fix each in place (chosen) vs. a wider layout pass over large text sizes (more work, not asked for).
Checks: widget tests per fix, before/after screenshots EN and MY, dev first, prod on request.
