import { GetObjectCommand, HeadBucketCommand, ListObjectsV2Command, S3Client } from '@aws-sdk/client-s3';
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { connect as netConnect } from 'net';
import { connect as tlsConnect } from 'tls';
import { PrismaService } from '../prisma/prisma.service';
import { EmailService } from './email.service';

export interface Check {
  name: string;
  /** Resolves with a short detail when healthy; throws with the reason when not. */
  run: () => Promise<string | void>;
}

/** Alert after this many failed runs in a row (one run a minute) — rides out a single blip or a rolling deploy. */
export const FAIL_THRESHOLD = 3;
const TIMEOUT_MS = 8000;

async function httpCheck(url: string, want: (status: number) => boolean = (s) => s < 400) {
  const res = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!want(res.status)) throw new Error(`HTTP ${res.status}`);
  return `HTTP ${res.status}`;
}

/** Days until the TLS certificate served for `host` expires (connects to host:443 with SNI). */
export function certDaysLeft(host: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = tlsConnect({ host, port: 443, servername: host, timeout: TIMEOUT_MS }, () => {
      const cert = s.getPeerCertificate();
      s.end();
      if (!cert?.valid_to) return reject(new Error('no certificate'));
      if (!s.authorized) return reject(new Error(`certificate not valid for ${host}: ${s.authorizationError}`));
      resolve(Math.floor((new Date(cert.valid_to).getTime() - Date.now()) / 86400e3));
    });
    s.on('timeout', () => s.destroy(new Error('timeout')));
    s.on('error', reject);
  });
}

/** Redis PING over RESP (no client library needed). */
export function redisPing(url: string): Promise<string> {
  const u = new URL(url);
  return new Promise((resolve, reject) => {
    const sock = netConnect({ host: u.hostname, port: Number(u.port || 6379) });
    const timer = setTimeout(() => sock.destroy(new Error('timeout')), TIMEOUT_MS);
    let buf = '';
    sock.on('connect', () => {
      const pass = decodeURIComponent(u.password || '');
      const user = decodeURIComponent(u.username || '');
      const cmd = (...a: string[]) => `*${a.length}\r\n${a.map((x) => `$${Buffer.byteLength(x)}\r\n${x}\r\n`).join('')}`;
      if (pass) sock.write(user ? cmd('AUTH', user, pass) : cmd('AUTH', pass));
      sock.write(cmd('PING'));
    });
    sock.on('data', (d) => {
      buf += d.toString();
      if (buf.includes('-')) {
        clearTimeout(timer);
        sock.destroy();
        return reject(new Error(buf.trim().split('\r\n').find((l) => l.startsWith('-')) ?? 'redis error'));
      }
      if (buf.includes('+PONG')) {
        clearTimeout(timer);
        sock.end();
        resolve('PONG');
      }
    });
    sock.on('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}

/**
 * Health checks every minute (worker pods; one at a time across replicas via a Postgres advisory lock).
 * A check that fails FAIL_THRESHOLD times in a row opens an incident and emails the alert recipients;
 * the first success after that closes it and emails a recovery note.
 */
@Injectable()
export class MonitorService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MonitorService.name);
  private timer?: NodeJS.Timeout;
  private readonly s3: S3Client;
  private readonly bucket: string;
  readonly backupPrefix: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly email: EmailService,
  ) {
    this.s3 = new S3Client({
      endpoint: config.get('S3_ENDPOINT'),
      region: config.get('S3_REGION') ?? 'us-east-1',
      forcePathStyle: true,
      credentials: { accessKeyId: config.get('S3_ACCESS_KEY_ID') ?? 'x', secretAccessKey: config.get('S3_SECRET_ACCESS_KEY') ?? 'x' },
    });
    this.bucket = config.get('S3_BUCKET') ?? 'event360';
    this.backupPrefix = `${(config.get<string>('S3_PREFIX') ?? 'dev').replace(/\/+$/, '')}/backups`;
  }

  onModuleInit() {
    if (process.env.APP_ROLE === 'worker' && process.env.NODE_ENV !== 'test') {
      this.timer = setInterval(() => this.runOnce().catch((e) => this.logger.warn(`monitor: ${e.message}`)), 60_000);
      setTimeout(() => this.runOnce().catch(() => undefined), 15_000).unref();
    }
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** The list of checks for this environment (overridable in tests). */
  checks(): Check[] {
    const c = (k: string) => this.config.get<string>(k);
    const domain = c('PUBLIC_DOMAIN');
    const list: Check[] = [
      { name: 'api', run: () => httpCheck('http://api:3000/readyz') },
      { name: 'database', run: async () => void (await this.prisma.$queryRaw`SELECT 1`) },
      { name: 'redis', run: () => (c('REDIS_URL') ? redisPing(c('REDIS_URL')!) : Promise.resolve('not configured')) },
      {
        name: 'storage',
        run: async () => {
          await this.s3.send(new HeadBucketCommand({ Bucket: this.bucket }));
          return this.bucket;
        },
      },
      { name: 'portal', run: () => httpCheck('http://web:3000/login') },
      { name: 'live-ingest', run: () => httpCheck('http://srs:1985/api/v1/versions') },
      { name: 'backups', run: () => this.backupCheck() },
      { name: 'payments', run: () => this.paymentsCheck() },
    ];
    if (c('SITE_ENABLED') === 'true') list.push({ name: 'website', run: () => httpCheck('http://site:3000/healthz') });
    if (c('USER_WEB_ENABLED') === 'true') list.push({ name: 'web-app', run: () => httpCheck('http://user-web/') });
    if (domain) {
      // The way users reach us: DNS → NPMPlus (TLS) → Traefik → service
      list.push({ name: 'public-api', run: () => httpCheck(`https://api.${domain}/readyz`) });
      list.push({
        name: 'certificate',
        run: async () => {
          const hosts = [`api.${domain}`, `portal.${domain}`, ...(c('SITE_ENABLED') === 'true' ? [domain] : [])];
          const days = await Promise.all(hosts.map((h) => certDaysLeft(h)));
          const min = Math.min(...days);
          if (min < 3) throw new Error(`TLS certificate expires in ${min} day(s) — check NPMPlus renewal`);
          return `${min} day(s) left`;
        },
      });
    }
    return list;
  }

  /** Latest nightly backup must be under 26 hours old (none yet = fine until the first run). */
  async backupCheck() {
    const r = await this.s3.send(new ListObjectsV2Command({ Bucket: this.bucket, Prefix: `${this.backupPrefix}/daily/` }));
    const latest = (r.Contents ?? []).filter((o) => o.Key?.endsWith('.dump')).sort((a, b) => (b.LastModified?.getTime() ?? 0) - (a.LastModified?.getTime() ?? 0))[0];
    if (!latest?.LastModified) return 'no backups yet';
    const hours = (Date.now() - latest.LastModified.getTime()) / 3600e3;
    if (hours > 26) throw new Error(`last backup is ${Math.round(hours)} hours old`);
    const test = await this.lastRestoreTest();
    if (test && test.ok === false) throw new Error(`last restore test failed: ${String(test.error ?? 'unknown error').slice(0, 200)}`);
    return `last ${Math.round(hours)}h ago, ${Math.round((latest.Size ?? 0) / 1024)} KB${test?.ok ? ', restore test ok' : ''}`;
  }

  private restoreMemo: { at: number; value: { ok?: boolean; error?: string } | null } | null = null;

  /** Newest monthly restore-test report (re-read at most every 10 minutes). */
  async lastRestoreTest() {
    if (this.restoreMemo && Date.now() - this.restoreMemo.at < 600e3) return this.restoreMemo.value;
    let value: { ok?: boolean; error?: string } | null = null;
    const r = await this.s3.send(new ListObjectsV2Command({ Bucket: this.bucket, Prefix: `${this.backupPrefix}/restore-tests/` }));
    const key = (r.Contents ?? []).map((o) => o.Key!).filter((k) => k?.endsWith('.json')).sort().pop();
    if (key) {
      const o = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
      try {
        value = JSON.parse((await o.Body?.transformToString()) ?? 'null');
      } catch {
        value = { ok: false, error: 'report is not valid JSON' };
      }
    }
    this.restoreMemo = { at: Date.now(), value };
    return value;
  }

  /** The reconciler expires unanswered payments after 2 hours; anything older means it isn't running. */
  async paymentsCheck() {
    const stuck = await this.prisma.payment.count({ where: { status: 'PENDING', createdAt: { lt: new Date(Date.now() - 3 * 3600e3) } } });
    const review = await this.prisma.order.count({ where: { needsReview: true } });
    if (stuck) throw new Error(`${stuck} payment(s) pending for over 3 hours`);
    return review ? `${review} order(s) need review in Admin → Finance` : 'ok';
  }

  /** One round of checks; returns false when another replica is already running them. */
  async runOnce(checks = this.checks()): Promise<boolean> {
    // Transaction-scoped advisory lock: held while the checks run, released automatically on commit.
    return this.prisma.$transaction(
      async (tx) => {
        const [{ locked }] = await tx.$queryRaw<{ locked: boolean }[]>`SELECT pg_try_advisory_xact_lock(360360) AS locked`;
        if (!locked) return false;
        const results = await Promise.all(
          checks.map(async (ch) => {
            try {
              const detail = await Promise.race([ch.run(), new Promise<never>((_, rej) => setTimeout(() => rej(new Error('timed out')), TIMEOUT_MS + 2000))]);
              return { name: ch.name, ok: true, detail: detail ? String(detail).slice(0, 300) : null, error: null as string | null };
            } catch (e) {
              return { name: ch.name, ok: false, detail: null, error: ((e as Error).message || 'failed').slice(0, 500) };
            }
          }),
        );
        for (const r of results) await this.record(r);
        return true;
      },
      { timeout: 55_000, maxWait: 5_000 },
    );
  }

  private async record(r: { name: string; ok: boolean; detail: string | null; error: string | null }) {
    const now = new Date();
    const prev = await this.prisma.monitorCheck.findUnique({ where: { name: r.name } });
    const failures = r.ok ? 0 : (prev?.consecutiveFailures ?? 0) + 1;
    const changed = !prev || prev.ok !== r.ok;
    const startAlert = !r.ok && failures >= FAIL_THRESHOLD && !prev?.alerting;
    const recovered = r.ok && !!prev?.alerting;
    await this.prisma.monitorCheck.upsert({
      where: { name: r.name },
      create: { name: r.name, ok: r.ok, consecutiveFailures: failures, lastError: r.error, detail: r.detail, lastCheckedAt: now, changedAt: now, alerting: startAlert },
      update: {
        ok: r.ok,
        consecutiveFailures: failures,
        lastError: r.ok ? prev?.lastError ?? null : r.error,
        detail: r.detail,
        lastCheckedAt: now,
        ...(changed ? { changedAt: now } : {}),
        ...(startAlert ? { alerting: true } : {}),
        ...(recovered ? { alerting: false } : {}),
      },
    });
    if (startAlert) {
      await this.prisma.monitorIncident.create({ data: { check: r.name, error: r.error ?? 'failed', startedAt: prev?.ok === false ? prev.changedAt : now } });
      await this.notify(`${r.name} is DOWN`, `Check "${r.name}" has failed ${failures} times in a row.\n\nError: ${r.error}\n\nSee Admin → Operations for details.`);
    }
    if (recovered) {
      const open = await this.prisma.monitorIncident.findFirst({ where: { check: r.name, endedAt: null }, orderBy: { startedAt: 'desc' } });
      if (open) await this.prisma.monitorIncident.update({ where: { id: open.id }, data: { endedAt: now } });
      const mins = open ? Math.max(1, Math.round((now.getTime() - open.startedAt.getTime()) / 60e3)) : 0;
      await this.notify(`${r.name} recovered`, `Check "${r.name}" is healthy again${mins ? ` after about ${mins} minute(s)` : ''}.${r.detail ? `\n\n${r.detail}` : ''}`);
    }
  }

  private async notify(subject: string, text: string) {
    const sent = await this.email.sendAlert(subject, text).catch((e) => (this.logger.warn(`alert email failed: ${(e as Error).message}`), false));
    this.logger.warn(`${subject}${sent ? ' (emailed)' : ' (email not set up)'}`);
  }

  // ───────────── for the admin page ─────────────

  async backups() {
    const list = async (kind: string) => {
      const r = await this.s3.send(new ListObjectsV2Command({ Bucket: this.bucket, Prefix: `${this.backupPrefix}/${kind}/` })).catch(() => null);
      return (r?.Contents ?? [])
        .filter((o) => o.Key)
        .sort((a, b) => (b.LastModified?.getTime() ?? 0) - (a.LastModified?.getTime() ?? 0))
        .slice(0, 20)
        .map((o) => ({ key: o.Key!.slice(this.backupPrefix.length + 1), size: o.Size ?? 0, at: o.LastModified }));
    };
    const [daily, weekly, tests] = await Promise.all([list('daily'), list('weekly'), list('restore-tests')]);
    let lastRestoreTest: unknown = null;
    if (tests[0]) {
      const o = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: `${this.backupPrefix}/${tests[0].key}` })).catch(() => null);
      const text = o?.Body ? await o.Body.transformToString().catch(() => null) : null;
      try {
        lastRestoreTest = text ? JSON.parse(text) : null;
      } catch {
        lastRestoreTest = null;
      }
    }
    return { daily, weekly, restoreTests: tests, lastRestoreTest };
  }
}
