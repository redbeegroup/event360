import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/** DATABASE_URL with `connection_limit` replaced by DB_CONNECTION_LIMIT (per workload, set in the manifests). */
export function databaseUrl(url = process.env.DATABASE_URL, limit = process.env.DB_CONNECTION_LIMIT): string | undefined {
  if (!url || !limit || !/^\d+$/.test(limit)) return url;
  const u = new URL(url);
  u.searchParams.set('connection_limit', limit);
  if (!u.searchParams.has('pool_timeout')) u.searchParams.set('pool_timeout', '20');
  return u.toString();
}

/** Connects lazily so pods can start (and report readiness) before the DB is reachable. */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleDestroy {
  constructor() {
    const url = databaseUrl();
    super(url ? { datasources: { db: { url } } } : undefined);
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
