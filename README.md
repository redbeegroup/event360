# Event 360

Event discovery, ticketing, on-site operations, live streaming and promotion platform for Myanmar.
Architecture and roadmap: [docs/adr/0001-platform-architecture.md](docs/adr/0001-platform-architecture.md).

| Path | What |
|---|---|
| `apps/api` | NestJS modular monolith (API / worker / realtime roles), Prisma + PostgreSQL |
| `apps/web` | Next.js portal — `/admin` and `/organizer` |
| `mobile/` | Flutter (melos): `user_app`, `organizer_app`, `crew_app` + shared packages |
| `infra/manifests` | Generator (`generate.mjs`) + per-environment settings (`envs.json`) |
| `deploy/<env>/event360.yaml` | Generated manifests that Portainer GitOps applies — do not edit by hand |
| `infra/k8s` | Example secret shape |

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

## Deploying to Kubernetes (Portainer GitOps)

Cluster: Talos, managed in Portainer (environment `talos-corexlab-portainer`). Ingress is Traefik
(`172.16.16.180:80`) behind NPMPlus, which terminates TLS — see [docs/npmplus-setup.md](docs/npmplus-setup.md).

| Environment | Namespace | Database | Bucket |
|---|---|---|---|
| dev | `event360-dev` | `event360`, schema `dev` | `event360`, prefix `dev/` |
| prod | `event360-prod` | `event360`, schema `prod` | `event360`, prefix `prod/` |

1. Each namespace holds the Secret `event360-secrets` (shape: `infra/k8s/secrets.example.yaml`), created once in the cluster.
2. Portainer has one Git application per environment, tracking `deploy/<env>/event360.yaml`, polling every 5 minutes.
3. On every push, CI builds `ghcr.io/redbeegroup/event360-{api,web}` tagged with the commit SHA and the branch name.
   On `main`, CI also pins dev to the new SHA and commits the regenerated manifest, which Portainer then applies.
4. To promote to prod, open a PR that runs `node infra/manifests/generate.mjs --set-tag prod=<sha>`.
5. The API pod's init container runs `prisma migrate deploy` plus the idempotent seed before the app starts.

Changing deployment settings: edit `infra/manifests/envs.json` or `generate.mjs`, then run `pnpm manifests`.
CI fails if `deploy/` is stale.

## Hostnames

| Environment | API | WebSocket | Portal |
|---|---|---|---|
| prod | api.event360.app | ws.event360.app | portal.event360.app |
| dev | api.dev.event360.app | ws.dev.event360.app | portal.dev.event360.app |

Streaming (Phase 5b): `ingest.event360.app` (RTMP/SRT), `media.event360.app` (HLS playback), `watch.event360.app` (web player).
