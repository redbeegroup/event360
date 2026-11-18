# Event 360

Event discovery, ticketing, on-site operations, live streaming and promotion platform for Myanmar.
Architecture and roadmap: [docs/adr/0001-platform-architecture.md](docs/adr/0001-platform-architecture.md).

| Path | What |
|---|---|
| `apps/api` | NestJS modular monolith (API / worker / realtime roles), Prisma + PostgreSQL |
| `apps/web` | Next.js portal — `/admin` and `/organizer` |
| `mobile/` | Flutter (melos): `user_app`, `organizer_app`, `crew_app` + shared packages |
| `infra/helm/event360` | Helm chart (api, worker, realtime, web, PgBouncer, Redis) |
| `infra/argocd` | ArgoCD Applications for dev / staging / prod |
| `infra/k8s` | Namespaces and example secret shapes |

## Local development

Requires Node 22, pnpm 10, PostgreSQL 16 (and Redis from Phase 1).

```bash
pnpm install
```

```bash
cp apps/api/.env.example apps/api/.env   # point DATABASE_URL at your local Postgres
```

```bash
cd apps/api && pnpm prisma migrate dev && pnpm prisma db seed && pnpm dev
```

API docs (Swagger) at http://localhost:3000/docs. Portal: `cd apps/web && pnpm dev` → http://localhost:3001.

Dev login: `POST /v1/auth/otp/request {"phone":"09..."}` returns `devCode` when `OTP_DEV_ECHO=true`.

## Deploying to Kubernetes

1. Apply `infra/k8s/namespaces.yaml`.
2. Create the `event360-secrets` and `event360-pgbouncer` secrets (shape in `infra/k8s/secrets.example.yaml`) via External Secrets or Sealed Secrets. `DIRECT_DATABASE_URL` points at the external PostgreSQL cluster (used by migrations); `DATABASE_URL` points at PgBouncer.
3. Set `image.registry` and `domain` in the `values-<env>.yaml` files.
4. Apply `infra/argocd/event360-<env>.yaml`. Migrations run as a Helm pre-upgrade Job.

## Hostnames

| Environment | API | WebSocket | Portal |
|---|---|---|---|
| prod | api.event360.corexlab.net | ws.event360.corexlab.net | portal.event360.corexlab.net |
| staging | api.staging.event360.corexlab.net | ws.staging.event360.corexlab.net | portal.staging.event360.corexlab.net |
| dev | api.dev.event360.corexlab.net | ws.dev.event360.corexlab.net | portal.dev.event360.corexlab.net |

Streaming (Phase 5b): `ingest.event360.corexlab.net` (RTMP/SRT), `media.event360.corexlab.net` (HLS playback), `watch.event360.corexlab.net` (web player).
