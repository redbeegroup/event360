# Build from repo root: docker build -f apps/api/Dockerfile .
FROM node:22-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json apps/api/
RUN pnpm install --frozen-lockfile --filter @event360/api...
COPY apps/api apps/api
RUN cd apps/api && pnpm prisma generate && pnpm build && pnpm deploy --filter @event360/api --prod --legacy /out \
    && cp -r dist prisma assets /out/ && cd /out && npx prisma generate

FROM node:22-alpine
RUN apk add --no-cache openssl && addgroup -S -g 10001 app && adduser -S -u 10001 -G app app
WORKDIR /app
COPY --from=build --chown=10001:10001 /out /app
USER 10001
ENV NODE_ENV=production PORT=3000
EXPOSE 3000
# APP_ROLE=api|worker|realtime selects the workload (same image)
CMD ["node", "dist/main.js"]
