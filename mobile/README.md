# Event 360 — Flutter workspace

Apps: `apps/user_app` (Event 360), `apps/organizer_app`, `apps/crew_app`.
Shared packages: `packages/core` (config, API, auth), `packages/ui` (design system), `packages/ticketing` (QR verify).

## First-time setup
Platform folders (android/ios) are not committed yet. Generate them once per app:

```bash
dart pub global activate melos
melos bootstrap
for a in user_app organizer_app crew_app; do (cd apps/$a && flutter create --platforms=android,ios --org com.event360 .); done
```

Run against a local API:

```bash
cd apps/user_app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```
