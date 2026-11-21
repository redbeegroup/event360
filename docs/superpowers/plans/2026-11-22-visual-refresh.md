# Visual Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** give all five Event 360 surfaces one professional look (navy + gold, pill buttons, bold display type), following the approved mockups, with no behaviour changes.

**Architecture:** design tokens live in two places: `Event360Theme` plus shared widgets in `mobile/packages/ui` for the three Flutter apps, and CSS custom properties in each Next app's `globals.css` for the portal and site. Screens are then restyled surface by surface on top of those tokens.

**Tech Stack:** Flutter (Material 3, Riverpod 3), Next 15 (plain CSS), `@fontsource` fonts.

**Spec:** docs/superpowers/specs/2026-11-22-visual-refresh-design.md.
- Its "Decisions after the builder check" section overrides earlier text.
- Mockup sources are in `docs/design/visual-refresh/*.dc.html`. Read their inline styles for exact sizes.

## Global Constraints
- **Tokens:** night `#1b1e4b`, gold `#f2b632`, gold-ink `#3b2a00`, paper `#f7f8fc`, card `#ffffff`, ink `#15172e`, ink-2 `#33364f`, muted `#555a78`, line `#dde0ee`, tint `#e9eaf5`, success text `#1f6f5c` (inline) / `#14594a` on `#d9f2e9` (badges), amber-ink `#8a4b00`, danger `#b42318`.
- **Dark tokens:** paper `#111326`, card `#1a1d38`, ink `#eef0fa`, muted `#a6abc8`, line `#2c3054`, and navy filled buttons become `#8f96e8` with dark text.
- **Fonts:** Bricolage Grotesque (display, 700/800), Figtree (body), Noto Sans Myanmar fallback.
- **Myanmar:** weight 700 where Latin is 800, titles one step smaller (28→24, 20→18) at line height 1.5, body line height 1.55, badges not uppercased or tracked.
- **Buttons:**
  - Shape: pills, primary height 52–54, secondary 44.
  - Roles: gold filled is the single main action per screen (never two). Navy filled is for other primary actions, navy outline for secondary, bold navy text link for tertiary.
- **Cards:** radius 14–16, 1 px line border, no elevation. Soft shadow only on floating elements.
- **Accessibility:** touch targets ≥ 44 px; text contrast ≥ 4.5:1 (3:1 at 24 px+).
- **Scope:** no behaviour changes, no new API endpoints, no new routes. Seat and ticket-type colours on seat maps are unchanged.
- **Text:** every new or changed label is in English and Myanmar. Each new Myanmar string gets a row in `docs/i18n/seating-my-review.csv` (key,english,myanmar,where).
- **Tests:** existing tests keep passing. Update a test only where it asserts on a deliberately changed label or visual.
- **Git:** never push. Commit locally; the controller pushes.

## Review Focus
1. **Myanmar text at 360 dp** on Discover, the event page, the ticket picker and the ticket: nothing clips or overflows. Overflow tests are in Tasks 2–4.
2. **Two gold buttons on one screen**, for example the event page bar plus the waitlist offer banner. Only the main action is gold. Review checklist in Tasks 3 and 4.
3. **Dark mode** on the portal (`prefers-color-scheme: dark`) and `Event360Theme.dark()`: text is still readable. Contrast table in Tasks 1 and 6.
4. **Narrow portal** (390 px): the side menu collapses and tables scroll in their box. Playwright phone screenshots in Tasks 6 and 7.
5. **Events with no cover image, long titles, or no venue**: rows and cards still lay out without overflow. Widget tests in Task 2.

---

### Task 1: Shared Flutter theme and widgets

**Files:**
- Modify: `mobile/packages/ui/lib/event360_ui.dart`, `mobile/packages/ui/pubspec.yaml`.
- Add fonts: `mobile/packages/ui/fonts/BricolageGrotesque-*.ttf` (700, 800), `Figtree-*.ttf` (400, 500, 600, 700), plus their OFL licence texts. Take the font files from the `@fontsource` packages already in `node_modules`, or from the upstream Google Fonts repos. Use static TTF instances.
- Create: `mobile/packages/ui/lib/src/tokens.dart`, `mobile/packages/ui/lib/src/widgets.dart`.
- Test: `mobile/packages/ui/test/theme_test.dart`.

**Interfaces — produces:**
- `class E360Colors` with static consts named after the tokens: `night`, `gold`, `goldInk`, `paper`, `card`, `ink`, `ink2`, `muted`, `line`, `tint`, `success`, `successBadgeInk`, `successBadgeBg`, `amberInk`, `danger`.
- `Event360Theme.light({Locale? locale})` and `Event360Theme.dark({Locale? locale})`. For `locale.languageCode == 'my'` they apply the Myanmar type rules.
- Text theme mapping:
  - `headlineMedium` = screen title 28/800;
  - `titleLarge` = section title 20/700;
  - `titleMedium` = row title 16/700;
  - `bodyLarge` 15;
  - `bodySmall` 13.
- `ButtonStyle E360Buttons.gold`, `.navy`, `.outline`: pill, with the heights from Global Constraints.
- Widgets:
  - `E360Badge(String label, {E360BadgeKind kind})`, kinds `gold`, `neutral`, `success`, `dark`;
  - `PrimaryActionBar({required Widget summary, required Widget action})`;
  - `InfoRow({required IconData icon, required String title, String? subtitle, VoidCallback? onTap})`;
  - `StepperButton({required IconData icon, VoidCallback? onPressed, required String semanticLabel})`, 44 px round;
  - `E360Mark({double size = 28})`;
  - `Pill`, kept and restyled as `E360Badge.neutral`.

- [ ] **Step 1:** Write the failing tests in `theme_test.dart`:
  - light scheme primary is `E360Colors.night` and scaffold background is `paper`;
  - a `FilledButton` with `E360Buttons.gold` is at least 52 high with a stadium shape;
  - the `my` locale title style has weight 700 and size 24;
  - `StepperButton` has a 44×44 hit area and its semantics label;
  - `E360Badge` does not uppercase in `my`.
- [ ] **Step 2:** Run `cd mobile/packages/ui && flutter test`. Expected: FAIL.
- [ ] **Step 3:** Implement. Write a contrast table for every text/background token pair, light and dark, in the task report.
- [ ] **Step 4:** Run `cd mobile && melos run analyze && melos run test`. All three apps must still pass with the new theme; fix compile breaks only.
- [ ] **Step 5:** Commit `feat(ui): Event 360 design tokens, theme and shared widgets`.

### Task 2: Buyer app — Discover, tabs, event rows

**Files:**
- Modify: `mobile/apps/user_app/lib/screens/home_screen.dart`, `explore_screen.dart`, `lib/widgets/event_card.dart`, the app shell with the bottom navigation (find it via `NavigationBar`), `lib/main.dart` (pass the locale to the theme), and the `.arb` files.
- Test: `mobile/apps/user_app/test/widget_test.dart`.

**Interfaces:**
- Consumes: Task 1's theme and widgets.
- Produces:
  - `EventRow(EventSummary e)`: compact row with an 84 px image.
  - `FeaturedEventCard(EventSummary e)`.
  - `DiscoverSearchPill({String? city, VoidCallback onTap, VoidCallback onFilters})`.

  All three go in `lib/widgets/`.

Layout reference: `docs/design/visual-refresh/Main.dc.html`. Data rules: spec decision 7.

- [ ] **Step 1:** Write the failing widget tests:
  - `discover shows search pill, category chips, a featured event and popular rows`;
  - `featured event is not repeated in popular`;
  - `tapping a category chip opens Explore filtered to it`;
  - `event row lays out with no cover image, a very long title and no venue at 360 dp in EN and MY`. No overflow; use the existing overflow-test pattern.
  - `tabs read Discover, Explore, Tickets, Account`.
- [ ] **Step 2:** Run the tests. Expected: FAIL. Implement.
- [ ] **Step 3:** Run `melos run analyze && melos run test`. Commit `feat(app): Discover screen and new event rows`.

### Task 3: Buyer app — event page and ticket picker

**Files:**
- Modify: `mobile/apps/user_app/lib/screens/event_detail_screen.dart` (the page and its ticket sheet), `lib/widgets/discount_lines.dart`, `total_amounts.dart`, `waitlist_offer.dart` (styles only), and the `.arb` files.
- Test: `widget_test.dart`.

Layout references: `AppEvent.dc.html`, `AppTickets.dc.html`.

- The action in `PrimaryActionBar` follows the EXISTING logic for which button applies.
- "Good to know" shows only data the app already has: price rise, group tiers, refund policy text if present.

- [ ] **Step 1:** Write the failing tests:
  - `event page shows the bottom bar with price range and the right action`, covering seated, standing paid, free, and sold out with waitlist;
  - `good to know lists price rise and group discount when present, and is hidden when empty`;
  - `ticket picker cards have steppers, scarcity line and sold-out badge with Join waitlist`;
  - `only one gold button is on screen when an offer banner is visible`;
  - `event page and ticket picker have no overflow at 360 and 412 dp in EN and MY`.
- [ ] **Step 2:** Run the tests. Expected: FAIL. Implement.
- [ ] **Step 3:** Run `melos run analyze && melos run test`. Commit `feat(app): event page and ticket picker in the new look`.

### Task 4: Buyer app — tickets and remaining screens

**Files:**
- Modify: `ticket_screen.dart`, `tickets_screen.dart`, `checkout_screen.dart`, `seat_picker_screen.dart` (bars, chips and legend only; not the painter's seat colours), `login_screen.dart`, `language_screen.dart`, `profile_screen.dart`, `notifications_screen.dart`, `organizer_screen.dart`, `watch_screen.dart`, and the `.arb` files.
- Test: `widget_test.dart`.

Layout reference: `AppTicket.dc.html`.

- Keep the real QR widget, the max-brightness behaviour, and the cancel / watch / complimentary states.

- [ ] **Step 1:** Write the failing tests:
  - `ticket screen shows the detail grid (date, doors, venue, seat) and the QR on a navy background`;
  - `ticket screen has no overflow at 360 dp in EN and MY, with and without a seat`;
  - `existing ticket behaviours still present` (cancel when canCancel, complimentary label);
  - `login and language screens render with pill buttons` (a smoke test).
- [ ] **Step 2:** Run the tests. Expected: FAIL. Implement.
  - Go through every remaining screen for leftover Material defaults: lavender surfaces, 14 px radius buttons.
- [ ] **Step 3:** Verify and commit.
  - Run `melos run analyze && melos run test`.
  - Build the web app the way CI does. Take Playwright phone screenshots (EN and MY) of Discover, event page, ticket picker, seat picker, checkout and ticket against the local API.
  - Save them to the scratchpad `shots-vr4/`.
  - Commit `feat(app): tickets and remaining screens in the new look`.

### Task 5: Public site

**Files:**
- Modify: `apps/site/app/globals.css`, `apps/site/app/[lang]/layout.tsx` (header), `apps/site/app/[lang]/e/[slug]/page.tsx`, the events listing and home pages, `apps/site/app/components/*` as needed, `apps/site/app/lib/i18n.ts`.

Layout reference: `Site.dc.html`.

- Keep SSR, metadata/SEO, `SeatMapStatic` and both languages.
- Add the dark tokens only if the site already supports dark. Check first; if it doesn't, leave it light.

- [ ] **Step 1:** Implement:
  - a white header with a search pill and an "Open the app" pill;
  - the event page per the mockup: rounded cover, badges, fluid `clamp()` title reaching 44 px, When/Where cards, Good to know, and a ticket box with a gold "Get tickets";
  - event cards and rows in the listing;
  - `:lang(my)` type rules.
- [ ] **Step 2:** Run `cd apps/site && npx tsc --noEmit && npx next build`. Take Playwright screenshots at 1280 and 390 px wide, EN and MY, of home, listing, a seated event page and a free event page (local API). Save them to `shots-vr5/`. Check for no horizontal page scroll at 390.
- [ ] **Step 3:** Commit `feat(site): new look`.

### Task 6: Portal — tokens, fonts and layout shell

**Files:**
- Modify: `apps/web/app/globals.css`, `apps/web/app/layout.tsx` (fonts via `@fontsource` like the site; remove Inter), `apps/web/package.json`, the organizer and admin layouts (`apps/web/app/organizer/**/layout.tsx`, `apps/web/app/admin/layout.tsx`; create if missing), `apps/web/app/lib/i18n.ts`.
- Create: `apps/web/app/components/SideMenu.tsx`, `PageHeader.tsx`, `StatTile.tsx`, `EventTabs.tsx`.

**Interfaces — produces:**
- CSS classes:
  - buttons: `.btn`, `.btn-gold`, `.btn-navy`, `.btn-outline`;
  - `.badge` with `-gold`, `-neutral`, `-success` and `-dark` variants;
  - `.card`, `.stat-tile`, `.table-card`, `.side-menu`, `.page-header`.
- Components:
  - `<SideMenu items={[{href,label,active}]} />`
  - `<PageHeader breadcrumb title badge actions />`
  - `<StatTile label value unit />`
  - `<EventTabs orgId eventId active />`

Menu map: spec decision 1. Layout reference: `Portal.dc.html`.

- [ ] **Step 1:** Implement:
  - tokens (light and dark) and fonts;
  - the shell: side menu on wide screens, collapsing to a top menu below 760 px;
  - existing class names (`.card`, `.muted`, buttons) restyled so every page improves before Task 7 touches it.
- [ ] **Step 2:** Run `cd apps/web && npx tsc --noEmit && npx next build`. Take Playwright screenshots (local API, local-DB admin and organizer) of the organizer events list, admin home and login at 1280 and 390, light and dark. Save them to `shots-vr6/`. Put a contrast table for the dark tokens in the report.
- [ ] **Step 3:** Commit `feat(portal): design tokens, fonts and layout shell`.

### Task 7: Portal — pages

**Files:**
- Modify the pages under `apps/web/app/organizer/**` and `apps/web/app/admin/**` and the components `SeatMapEditor.tsx`, `SeatsManager.tsx` (chrome only), `PayoutAdmin.tsx`, `SeatMapPreview.tsx`, `ListEditor.tsx`, `ActionForm.tsx`, `CrewCheckin.tsx`, `LiveStudio.tsx`, and the login/invite pages.

**Interfaces — consumes:** Task 6's classes and components.

- [ ] **Step 1:** Apply the new page pattern to every page:
  - `PageHeader`, and `EventTabs` on an event's Edit / Dashboard / Seats pages;
  - stat tiles on dashboards and payouts;
  - tables inside `.table-card` with horizontal scroll;
  - forms with consistent field styles;
  - exactly one gold button per page (the main save or primary action).
  - Replace inline `style={{…}}` colour and radius values with classes or tokens.
  - Print pages keep their layout.
- [ ] **Step 2:** Run tsc and the build. Take Playwright screenshots at 1280 and 390, EN and MY, of: organizer events list, event edit, event dashboard, seats page, payouts, admin finance, admin venues editor, admin settings. Save them to `shots-vr7/`. Check for no horizontal page scroll at 390.
- [ ] **Step 3:** Commit `feat(portal): pages in the new look`.

### Task 8: Crew and Organizer apps

**Files:**
- Modify: `mobile/apps/crew_app/lib/**` (scan result card colours mapped to tokens, viewfinder frame, pill buttons, lists), `mobile/apps/organizer_app/lib/**` (event rows, overview tiles in the stat-tile style), both apps' `main.dart` (locale-aware theme), and the `.arb` files if labels change.
- Test: both apps' existing widget tests, plus one overflow test each at 360 dp in EN and MY for the crew result card and the organizer overview.

- [ ] **Step 1:** Write the two overflow tests. Run them. Implement.
- [ ] **Step 2:** Run `melos run analyze && melos run test`. Commit `feat(apps): crew and organizer apps in the new look`.

### Task 9: Sign-off screenshots (controller)

- [ ] After dev runs the final build, capture every surface in EN and MY from the dev URLs (app web build, crew web build, site, portal). Send the set to the user for sign-off.
