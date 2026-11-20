# Event 360 operations runbook

What to do when something breaks, and how to do the routine jobs: deploy, roll back, restore a backup, rotate a secret.

Commands use `kubectl`. In Portainer, open **Kubernetes → talos-corexlab-portainer → kubectl shell** (top right). Swap `event360-prod` for `event360-dev` to act on dev.

## 1. The two environments

| | dev | prod |
|---|---|---|
| Namespace | `event360-dev` | `event360-prod` |
| Portainer stack | 76 (`event360-dev`) | 77 (`event360-prod`) |
| Hosts | `*.dev.event360.app` | `event360.app`, `www.`, `api.`, `ws.`, `portal.`, `app.` |
| Database | `event360` DB, schema `dev` | same DB, schema `prod` |
| Files | bucket `event360`, prefix `dev/` | prefix `prod/` |
| Login codes | shown on screen (`OTP_DEV_ECHO=true`), anyone can sign in as any phone | real SMS (SMSPoh) |
| Payments | Mock pay on | real providers only |

Keep real personal data out of dev, because anyone can sign in there as any phone number.

Workloads per namespace: `api` (runs migrations first), `worker` (reminders, payment reconciler, health monitor), `realtime`, `web` (portal), `site` (public website), `user-web` (Flutter web builds), `srs` (live ingest), `redis`, plus the CronJobs `backup-db` and `backup-restore-test`.

## 2. Deploy

**Dev** deploys itself. A push to `claude/relaxed-dirac-qj6kax` makes CI build images, commit `deploy(dev): <sha>`, and call the Portainer webhook.

**Prod** only changes on purpose:

1. Check the version works on dev (Admin → Operations should show all checks OK).
2. In `infra/manifests/envs.json`, set `environments.prod.imageTag` to the full commit SHA.
3. Run `node infra/manifests/generate.mjs` and `pnpm test:manifests`, then commit and push.
4. In Portainer, open stack **event360-prod** and click **Pull and redeploy** (or call `PUT /api/stacks/77/git/redeploy?endpointId=17`).
5. Watch the pods: `kubectl -n event360-prod get pods -w`. The `api` pods run the `migrate` init container first; its log should end with `Seed complete`.
6. Check `https://api.event360.app/readyz` returns `ready`, and Admin → Operations shows the new release and all checks OK.

Migrations only ever add things (columns, tables), so the previous version still runs on the new schema. That is what makes rollback safe.

## 3. Roll back

1. Set `environments.prod.imageTag` back to the previous SHA (it's in `git log -- infra/manifests/envs.json`).
2. Regenerate, commit, push, and redeploy stack 77 as above.
3. Don't try to undo migrations. The old version ignores the new columns.

If only one workload is broken, you can also roll it back by itself until a proper fix ships:

```bash
kubectl -n event360-prod rollout undo deployment/api
```

The next GitOps redeploy puts the pinned version back.

## 4. Backups

- **Nightly** at 02:30 Myanmar time, `backup-db` dumps the environment's schema (`pg_dump -Fc`) to `s3://event360/<env>/backups/daily/YYYY-MM-DD.dump`.
- **Sundays**: the same dump is also copied to `backups/weekly/`.
- **Kept**: 14 daily and 8 weekly copies; older ones are deleted by the job.
- **Restore test**: on the 1st of each month at 04:30, `backup-restore-test` restores the newest dump into a throwaway Postgres inside the job, counts the rows in every table, and writes a report to `backups/restore-tests/YYYY-MM-DD.json`.
- **Where to look**: Admin → Operations → Database backups lists the files and the last restore test.
- **Alerts**: the `backups` check emails you if the newest dump is over 26 hours old or the last restore test failed.

Backups live on the same SeaweedFS as everything else. For protection against losing that server, copy `event360/prod/backups/weekly/` somewhere else now and then (another disk or cloud bucket).

**Run a backup now** (for example, before a risky change):

```bash
kubectl -n event360-prod create job --from=cronjob/backup-db backup-manual-$(date +%s)
```

**Run the restore test now:**

```bash
kubectl -n event360-prod create job --from=cronjob/backup-restore-test restore-test-manual-$(date +%s)
```

**See why a backup job failed:**

```bash
kubectl -n event360-prod get jobs | grep backup
kubectl -n event360-prod logs job/<job-name> --all-containers
```

## 5. Restore the database from a backup

Only do this for real data loss. It replaces the whole environment schema with the dump.

1. **Stop writes.** Scale the backend to zero:
   ```bash
   kubectl -n event360-prod scale deployment api worker realtime --replicas=0
   ```
2. **Download the dump** you want from SeaweedFS (`event360/prod/backups/daily/<date>.dump`) to a machine that can reach PostgreSQL at 172.16.16.39:5433, with PostgreSQL 18 client tools installed (the server is 18; older tools refuse to dump it).
3. **Keep the current state, just in case:**
   ```bash
   pg_dump "postgresql://dbuser_event360@172.16.16.39:5433/event360" -n prod -Fc -f before-restore.dump
   ```
4. **Replace the schema** (the dump recreates it):
   ```bash
   psql "postgresql://dbuser_event360@172.16.16.39:5433/event360" -c 'DROP SCHEMA prod CASCADE'
   pg_restore -d "postgresql://dbuser_event360@172.16.16.39:5433/event360" --no-owner --no-privileges --exit-on-error <date>.dump
   ```
5. **Start again** (2 replicas each on prod):
   ```bash
   kubectl -n event360-prod scale deployment api worker realtime --replicas=2
   ```
   The `api` migrate step applies any migrations newer than the dump.
6. **Check** Admin → Operations, and log in to the portal and the app.

Everything after the dump's time is lost: orders, tickets and check-ins. Payments that providers confirm afterwards arrive as webhooks for orders that no longer exist; they show up in the payment events table, and Finance must refund them by hand.

Recordings, uploads and images are in SeaweedFS, not in the dump, so they're unaffected.

## 6. Rotate a secret

Secrets live in the Kubernetes Secret `event360-secrets` in each namespace, never in git. Change a value in Portainer (**ConfigMaps & Secrets → event360-secrets → Edit**), then restart the pods that use it:

```bash
kubectl -n event360-prod rollout restart deployment api worker realtime web site
```

What each one does when changed:

| Key | Effect of changing it |
|---|---|
| `JWT_ACCESS_SECRET` | Access tokens stop working and the apps refresh them without anyone noticing. To sign **everyone** out instead, revoke the refresh tokens: `UPDATE prod.refresh_tokens SET revoked_at = now() WHERE revoked_at IS NULL;` |
| `QR_SIGNING_KEY` | **Every ticket QR code changes.** Old screenshots and the crew apps' offline caches stop matching until they refresh. Only rotate between events. |
| `SETTINGS_KEY` | **Sealed settings become unreadable**: SMS, payment, push and email passwords. Re-enter them all in Admin → Settings afterwards. Only rotate if it leaked. |
| `STREAM_HOOK_SECRET` | Restart `srs` too (`kubectl -n event360-prod rollout restart deployment srs`). Live streams in progress drop and must reconnect. |
| `REDIS_PASSWORD` / `REDIS_URL` | Change both together, then restart `redis` and the backend. |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | Create the new key in SeaweedFS first, update the Secret, restart, then delete the old key. |
| `DATABASE_URL` / `DIRECT_DATABASE_URL` | Change the password in PostgreSQL, update both (URL-encode special characters), restart. The backup jobs pick it up on their next run. |

Provider keys (SMSPoh, KBZPay, WavePay, Firebase, SMTP) are not in the Secret. Change them in **Admin → Settings**.

## 7. Alerts and what they mean

Alerts go to the addresses in **Admin → Settings → Email**. A check alerts after **3 failures in a row** (about 3 minutes), and you get a second email when it recovers. Subjects start with `[Event 360 prod]` or `[Event 360 dev]`. The checks run in the `worker` pods, so if every worker is down there are no alerts either. Opening `https://api.event360.app/readyz` from outside is a useful second opinion.

| Check | Means | First things to look at |
|---|---|---|
| `api` | The API's own readiness failed | `kubectl -n event360-prod get pods`; logs of `api` |
| `database` | PostgreSQL unreachable or slow | DB server at 172.16.16.39; connection limits; disk |
| `redis` | Redis not answering | `kubectl -n event360-prod get pods -l app.kubernetes.io/name=redis`; its volume |
| `storage` | SeaweedFS bucket not reachable | SeaweedFS server; S3 keys |
| `portal` / `website` / `web-app` | That web workload is not answering in the cluster | Pod status and logs of `web` / `site` / `user-web` |
| `live-ingest` | SRS not answering | `srs` pod; live streams can't start |
| `public-api` | The API is fine inside but not reachable via `api.event360.app` | NPMPlus, MikroTik, DNS, Traefik |
| `certificate` | The TLS certificate expires within 3 days | NPMPlus → SSL certificates → renew; check auto-renew is on |
| `backups` | Last dump over 26 h old, or the last restore test failed | Backup job logs (section 4) |
| `payments` | Payments stuck pending over 3 hours; the reconciler isn't running | `worker` pods; provider status |

**New error** emails are sent at most once every 10 minutes and list new error groups. Details are in **Admin → Operations → Errors**:
- Mark a group **fixed** once a fix is deployed. If it happens again, it reopens and you get another email.
- Reports from the apps and websites come through a public endpoint, so treat their text as untrusted. They are capped at 100 new groups per hour.

## 8. Rate limits

Every API route is limited per visitor IP: 120 requests a minute by default, tighter on login codes (30), staff login and invites (10), promo-code checks (10), image uploads (20) and ticket transfers (10).

Calls from inside the cluster or the LAN aren't limited: website server rendering, the portal's own calls, SRS hooks and the monitor. The portal passes the visitor's address on, so portal logins are still limited per person.

Limits are kept in memory per pod, so with 2 API pods the real ceiling is up to twice the number above. If many genuine users share one mobile carrier address during a big on-sale and get "Too many requests", raise the default in `apps/api/src/app.module.ts`.

## 9. Recurring tasks for a person

- **TLS certificate**: NPMPlus must keep auto-renew on. The `certificate` check warns 3 days before expiry.
- **Off-site backup copy**: copy the weekly dumps elsewhere every month or so.
- **Dependencies**: run `pnpm audit --prod` before big releases.
- **Dev data**: dev is public and anyone can sign in, so don't load real attendee data there.
