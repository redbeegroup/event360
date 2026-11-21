# Event 360 visual refresh — design

**Status:** approach chosen by the user ("option 1": one shared look, approved from mockups, rolled out app by app). Mockups approved 2026-11-22. This document awaits approval.

**Mockups (the visual authority):** https://claude.ai/artifact/FXtQSRkRDKM7Phjdtjp8zp
- Six artboards: App Discover, App Event page, App Choose tickets, App My ticket, Website Event page, Portal Event dashboard.
- Their HTML source is committed under `docs/design/visual-refresh/` (see "Reference files").

## Why
The user wants Event 360 to look more professional, "like Eventbrite", across every surface: the buyer app, the Crew app, the Organizer app, the organizer/admin portal and the public site.

Today the surfaces don't look like one product:
- the site is navy and gold with its own fonts;
- the portal is purple;
- the Flutter apps use default Material 3 with a violet seed.

## Goals
1. One Event 360 visual language (colours, type, shape, spacing, components), applied to all five surfaces.
2. The buyer app's main screens follow the approved mockups' layout: Discover, event page, ticket picker, ticket.
3. The portal and site adopt the same tokens and the mockups' page structure. For the portal that means a side menu, stat tiles and tables in cards; for the site, a bold title, info cards and a ticket box.
4. No behaviour changes. Every existing feature, text and flow keeps working, in English and Myanmar.

## Non-goals
- New features. Eventbrite's "Saved" hearts, "Follow organizer" and friends are **not** part of this. No new API endpoints.
- A new logo or new brand colours. The navy + gold already on the site is the brand.
- Dark mode redesign. Where dark themes exist today (the portal's `prefers-color-scheme`, `Event360Theme.dark()`), they must stay legible with the new tokens, but they get no bespoke design.
- Pixel-copying any other company's app. Mobbin references are used for layout patterns only: Eventbrite, Swiggy, Meetup, Square.

## Anti-goals
- A restyle that breaks Myanmar text. Myanmar glyphs need about 1.55 line height. Labels must not clip or overflow at 360 dp width.
- Losing accessibility: touch targets ≥ 44 px, text contrast ≥ 4.5:1 (3:1 for 24 px+ text).
- Regressing tested behaviour. Widget and e2e tests keep passing; tests are updated only where they assert on visuals that deliberately changed.

## Design language (tokens)

**Colours:**

| Token | Value | Use |
|---|---|---|
| night | `#1b1e4b` | brand navy: primary buttons, selected states, headers on dark screens |
| gold | `#f2b632` | the ONE main action on a screen ("Get tickets", "Continue to payment"), highlight badges, the active-tab marker |
| gold-ink | `#3b2a00` | text on gold |
| paper | `#f7f8fc` | page background |
| card | `#ffffff` | cards, bars, sheets |
| ink | `#15172e` | main text |
| ink-2 | `#33364f` | body paragraphs |
| muted | `#555a78` | secondary text |
| line | `#dde0ee` | borders, dividers |
| tint | `#e9eaf5` | neutral chips, selected menu rows |
| jade | `#1f6f5c` text on `#d9f2e9` | success, "Free", "Published" |
| amber-ink | `#8a4b00` | scarcity lines such as "48 tickets left" |
| danger | keep existing `#b42318` | errors |

Seat-map ticket-type colours stay as they are (API palette).

**Type:**
- Display font: Bricolage Grotesque (700/800) for titles and big numbers.
- Body font: Figtree (400–700).
- Myanmar fallback: Noto Sans Myanmar, always. Myanmar text keeps the existing 1.55 line height.
- Flutter:
  - Bundle the two Latin fonts as assets in `event360_ui`. Both are SIL OFL; add the licence files. Bundle them the same way NotoSansMyanmar is bundled. No runtime font download.
  - Type scale: screen title 28/800, section title 20/700, row title 16/700, body 15/400, meta 13–14, badge 12/700 uppercase with +0.04em tracking.

**Shape and spacing:**
- Buttons: pills, with height 52–54 for primary and 44 for secondary.
- Cards: radius 14–16 with a 1 px `line` border and no elevation. Only floating elements (search pill, round image buttons, the site ticket box) get a soft shadow.
- Chips and badges: full pills.
- Spacing: 20 px screen gutters on phones; 8/12/16/24 spacing steps.

**Button roles:**
- Gold filled: the single main action of a screen.
- Navy filled: other primary actions.
- Navy outline: secondary actions.
- Text link (navy, bold): tertiary actions.
- Never two gold buttons on one screen.

**Icons:** keep Material icons in Flutter, outlined style. The portal and site keep their current icon approach.

## Per-surface scope

### 1. Shared Flutter theme (`mobile/packages/ui`)
- Rewrite `Event360Theme` around the tokens. Use an explicit `ColorScheme`, not `fromSeed`. Cover text, button, chip, input, card, app bar, navigation bar and bottom sheet themes.
- Add shared widgets used by more than one app:
  - `E360Badge` (gold / neutral / success / dark "Sold out");
  - `PrimaryActionBar`: the sticky bottom bar with a left summary and a button;
  - `InfoRow`: an icon tile with two lines;
  - `StepperButton`: the round − / + button.
- `Pill` is kept as an alias or migrated.

### 2. Buyer app (`mobile/apps/user_app`)
- **Home → "Discover".**
  - Header with the mark and a language button.
  - Search pill ("Find things to do / in <city>") with a filter button. Tapping it opens the existing Explore search and filters.
  - Category chips.
  - One featured card. Rule: the soonest upcoming event with a cover image.
  - "Popular" compact rows: an 84 px square image, title, date · time · venue, then price or "Free".
  - The existing sections (free events, upcoming) keep their data and take the new row and card styles.
- **Bottom tabs.** The same four destinations, relabelled Discover / Explore / Tickets / Account, with the gold active marker.
- **Event page.**
  - Full-width cover with round back, calendar and share buttons.
  - Badges, a bold title and "By <organizer>".
  - Info rows.
  - "Overview" with "Read more".
  - "Good to know" cards. These show existing data only: price-rise hint, group discount tiers, refund policy, age and duration fields where present.
  - Ticket type list.
  - The existing schedule, lineup, gallery, FAQ and map sections, restyled.
  - `PrimaryActionBar` showing the price range (or "Free") and the date, with the gold action. The action is "Choose seats", "Get tickets", "Register" or "Join waitlist", per the existing logic.
- **Ticket picker sheet.** One card per ticket type with steppers. The selected card gets a 2 px navy border. Scarcity and limit lines, a sold-out badge with "Join waitlist", an "Add promo code" link, and a total bar with the gold "Continue to payment".
- **Seat picker, checkout, waiting-for-payment, waitlist offer sheet.** Same tokens and bars; no layout redesign beyond the shared components.
- **My tickets and ticket screen.**
  - Ticket screen: navy background, a white ticket card with a tear line, a detail grid (date, doors, venue, seat), the real QR, and an offline note. Actions: add to calendar, directions, and the existing cancel/watch buttons.
  - Max screen brightness behaviour is kept.
- **Login, language, profile, notifications, organizer page, watch screen.** Tokens and component styles only.

### 3. Public site (`apps/site`)
- It already uses the navy/gold tokens and fonts. Align it with the mockup:
  - a white header with a search pill and an "Open the app" pill;
  - event page: large rounded cover, badges, a 44 px title, When/Where cards, "Good to know" cards, and a ticket box with the gold "Get tickets";
  - event cards and listing pages with the same card and row styles.
- Keep SSR, SEO markup, the static seat-map SVG and both languages.

### 4. Portal (`apps/web`)
- Replace the purple tokens in `globals.css` with the shared tokens. Add the two fonts with `next/font` or self-hosted files, the same way the site loads them.
- Layout:
  - A left side menu. Organizer: Events, Payouts, Team, Organization profile. Admin: the existing admin sections. It collapses to a top menu on narrow screens.
  - Page header with breadcrumb, title, status badge and actions.
  - Stat tiles.
  - Tables inside cards, with horizontal scroll on small screens.
- Forms, buttons, badges, tabs, the seat-map editor and seats manager chrome, the print pages (unchanged layout) and the login/invite pages take the new styles.
- Reduce the ~150 inline `style={{…}}` uses where they set colours or radii, so tokens apply. Don't refactor structure beyond what the restyle needs.

### 5. Crew and Organizer apps
- Both pick up the shared theme automatically.
- **Crew.** Scan screen with a clear viewfinder frame. Result card colours mapped to tokens: jade accepted, amber already-checked-in, danger invalid. The seat text stays large. Pill buttons.
- **Organizer.** Event list rows and overview tiles follow the portal's stat-tile style.
- Check every screen of both apps for contrast and overflow in English and Myanmar.

## Rollout order
Each step is separately reviewable and deployable:
1. Shared Flutter theme and widgets.
2. Buyer app.
3. Site.
4. Portal.
5. Crew and Organizer apps.
6. Screenshots of every surface in English and Myanmar for sign-off.

Dev first. Prod only when the user asks.

## Testing
- **Flutter:**
  - Existing widget tests pass.
  - Add golden-free checks: no overflow at 360 and 412 dp in EN and MY for Discover, event page, ticket picker and ticket screen. Use the existing overflow-test pattern.
  - `melos run analyze` clean (infos only).
- **Portal and site:** `tsc`, `next build`, and Playwright screenshots of the key pages at desktop and phone widths, in EN and MY.
- **API:** untouched, so the API suite is not expected to change.
- **Contrast:** check each text/background token pair against the ratios above. A short script or table goes in the task report.

## Reference files
- Commit the six mockup sources from the canvas (`*.dc.html`) and `canvas.json` to `docs/design/visual-refresh/`, so implementers read exact values offline.
- They are references, not shipped code.

## Decisions after the builder check (controller's calls)
1. **Portal menu maps to existing pages only.**
   - Organizer side menu:
     - Events → `organizer/[orgId]`;
     - Payouts → `organizer/[orgId]/payouts`, shown to OWNER and FINANCE only, as today;
     - Organization profile → `organizer/[orgId]/profile`.
   - There is no separate Team page. Staff invites stay where they are on the organization page, so "Team" in the mockup is dropped.
   - An event's own pages (Edit, Dashboard, Seats) appear as tabs under the event title.
   - Admin menu: Organizations, Events, Venues, Finance, Ops, Settings. These are the existing pages.
   - No new routes.
2. **Token table beats mockup where they differ.**
   - Mockups are the authority for layout and proportion. The token table is the authority for exact colours.
   - Success text: use `#14594a` on `#d9f2e9` for badges and `#1f6f5c` for inline text such as "Free". Both pass contrast.
   - Web titles keep fluid `clamp()` sizes that reach the mockup size at desktop width.
   - Display weight is 800 for h1 and 700 for h2.
3. **Myanmar type.**
   - Myanmar text uses Noto Sans Myanmar at weight 700 where Latin uses 800. No synthetic bold.
   - Titles in Myanmar are one step smaller (28 → 24, 20 → 18) with 1.5 line height.
   - Badges are not uppercased or letter-spaced in Myanmar.
   - Implement this as a locale-aware text theme in Flutter and `:lang(my)` rules on the web.
4. **Portal fonts.**
   - Use the same `@fontsource` packages as the site: self-hosted, no build-time Google fetch.
   - Remove Inter.
5. **Seat maps.**
   - Ticket-type colours and seat states are unchanged.
   - Only the surrounding chrome (legend, bars, buttons) takes the tokens.
6. **Copy.**
   - New or changed labels: tab names, "Find things to do", "Good to know", "Overview", "Read more", "Continue to payment" and so on.
   - Each is added in English and Myanmar by the implementer, reusing existing strings where one already says the same thing.
   - Every new Myanmar string gets a row in `docs/i18n/seating-my-review.csv` for the native-speaker review.
   - Widget tests that find text by a changed label are updated.
7. **Discover data.**
   - The search pill's second line shows the city filter the buyer last chose in Explore, else "in Myanmar". No location feature.
   - Category chips are the existing API categories (top level). Tapping one opens Explore filtered to it.
   - The featured event is not repeated in the "Popular" list.
   - `organizerName` is already in the event payload.
8. **Assets.**
   - The mark is the navy rounded square with a gold dot, drawn as a small widget or CSS shape. No new logo file.
   - "Open the app" keeps its current link.
   - Mockup photos are sample covers. Real screens use each event's cover.
   - The mockups show layout; existing copy and states remain the source of truth.
9. **Test harness.**
   - Portal and site screenshots use ad-hoc Playwright scripts against a local API, as in earlier work. There is no permanent screenshot suite.
10. **Dark mode.**
    - Derive the dark values by inverting the neutrals: paper `#111326`, card `#1a1d38`, ink `#eef0fa`, muted `#a6abc8`, line `#2c3054`.
    - Keep gold as the main action. Navy filled buttons become `#8f96e8` with dark text.
    - Check contrast. No bespoke dark designs.

## Left to the builder
- Exact widget decomposition and file layout inside each app.
- Which existing optional event fields feed the "Good to know" cards beyond the price rise and group discount.
- How the portal side menu collapses on phones.
- Loading and empty-state styling, consistent with the tokens.
