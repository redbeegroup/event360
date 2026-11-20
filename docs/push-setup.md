# Push notifications (Firebase) setup

Event 360 sends notifications to the **in-app inbox** always. Push (Android) is added once Firebase is set up;
event changes and cancellations also go by **SMS** (SMSPoh, when SMS is enabled).

| Notification | Inbox | Push | SMS |
|---|---|---|---|
| Ticket ready (free registration or paid order) | ✓ | ✓ | |
| Day-before reminder | ✓ | ✓ | |
| Event time/venue changed | ✓ | ✓ | ✓ |
| Event cancelled | ✓ | ✓ | ✓ |
| Live stream started (once per session) | ✓ | ✓ | |
| Order refunded | ✓ | ✓ | |
| Organizer announcement (max 3 per event per day) | ✓ | ✓ | |

## 1. Create the Firebase project (once)
1. https://console.firebase.google.com → **Add project** → name it `event360` (Google Analytics not needed).
2. **Project settings → General → Your apps → Add app → Android**, twice:
   - package `net.corexlab.event360` (prod app)
   - package `net.corexlab.event360.dev` (dev app)

   You do not need to download `google-services.json`; the app gets its config from build variables.
3. Note from **Project settings → General**: *Project ID*, *Web API key*, and each Android app's *App ID*
   (`1:…:android:…`); from **Cloud Messaging**: the *Sender ID*.

## 2. App builds (GitHub repository variables — not secrets, this is public client config)
GitHub → repo **Settings → Secrets and variables → Actions → Variables → New repository variable**:

| Variable | Value |
|---|---|
| `FIREBASE_PROJECT_ID` | Project ID |
| `FIREBASE_API_KEY` | Web API key |
| `FIREBASE_SENDER_ID` | Sender ID |
| `FIREBASE_ANDROID_APP_ID` | App ID of `net.corexlab.event360` |
| `FIREBASE_ANDROID_APP_ID_DEV` | App ID of `net.corexlab.event360.dev` |

The next CI run builds APKs with push. Without them the app still works (inbox only).

## 3. Server key (portal)
1. Firebase → **Project settings → Service accounts → Generate new private key** (downloads a JSON file).
2. Portal → **Admin → Settings → Push notifications**: upload the file, tick **Send push notifications**, save.
   The private key is stored encrypted (`SETTINGS_KEY`) and never shown again. Do this on dev and on prod.
3. Install the new APK, sign in (allow notifications), then press **Send a test to my devices**.

Device tokens that Firebase reports as no longer valid are removed automatically.
