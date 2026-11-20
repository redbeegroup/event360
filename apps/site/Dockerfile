# Build from repo root: docker build -f apps/site/Dockerfile .
FROM node:22-alpine AS build
RUN corepack enable
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/site/package.json apps/site/
RUN pnpm install --frozen-lockfile --filter @event360/site...
COPY apps/site apps/site
RUN cd apps/site && pnpm build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build /repo/apps/site/.next/standalone ./
COPY --from=build /repo/apps/site/.next/static ./apps/site/.next/static
COPY --from=build /repo/apps/site/public ./apps/site/public
USER 1000
EXPOSE 3000
CMD ["node", "apps/site/server.js"]
