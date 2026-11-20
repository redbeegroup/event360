import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { EmailService } from './email.service';

export interface ErrorReport {
  source: string;
  message: string;
  stack?: string | null;
  path?: string | null;
  release?: string | null;
  context?: Record<string, unknown>;
}

/** Strip volatile parts (ids, numbers, quoted values) so the same bug groups together. */
export function normalizeMessage(m: string) {
  return m
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '<id>')
    .replace(/\b\d{3,}\b/g, '<n>')
    .replace(/(["'`]).{0,80}?\1/g, '$1…$1')
    .slice(0, 300);
}

/** First stack frame that points at our code (not node_modules / node internals). */
export function topFrame(stack?: string | null) {
  if (!stack) return '';
  const lines = stack.split('\n').map((l) => l.trim());
  const own = lines.find((l) => /^at /.test(l) && !/node_modules|node:internal|\(internal\//.test(l));
  return (own ?? lines.find((l) => /^at /.test(l)) ?? lines[1] ?? '').replace(/:\d+:\d+\)?$/, '').slice(0, 200);
}

/** New error groups the apps/websites may create per hour (the endpoint needs no sign-in). */
export const MAX_NEW_CLIENT_GROUPS_PER_HOUR = 100;

export const fingerprint = (r: Pick<ErrorReport, 'source' | 'message' | 'stack'>) =>
  createHash('sha1').update(`${r.source}|${normalizeMessage(r.message)}|${topFrame(r.stack)}`).digest('hex');

/** Groups errors by fingerprint; emails the first occurrence of a new (or reopened) error, at most every 10 minutes. */
@Injectable()
export class ErrorsService {
  private readonly logger = new Logger(ErrorsService.name);
  private lastAlert = 0;
  private pendingNew: string[] = [];

  constructor(
    private readonly prisma: PrismaService,
    private readonly email: EmailService,
  ) {}

  async capture(r: ErrorReport) {
    const fp = fingerprint(r);
    const now = new Date();
    try {
      const existing = await this.prisma.errorGroup.findUnique({ where: { fingerprint: fp } });
      const data = {
        lastSeen: now,
        lastRelease: r.release?.slice(0, 64) ?? null,
        lastContext: (r.context ?? {}) as object,
        path: r.path?.slice(0, 300) ?? null,
        stack: r.stack?.slice(0, 8000) ?? null,
      };
      if (existing) {
        const reopened = !!existing.resolvedAt;
        await this.prisma.errorGroup.update({ where: { id: existing.id }, data: { ...data, count: { increment: 1 }, resolvedAt: null } });
        if (reopened) this.queueAlert(`${r.source}: ${r.message} (came back after being marked fixed)`);
      } else {
        // Client reports come from an open endpoint: cap how many new groups they can create
        if (r.source !== 'api') {
          const recent = await this.prisma.errorGroup.count({ where: { source: { not: 'api' }, firstSeen: { gt: new Date(now.getTime() - 3600e3) } } });
          if (recent >= MAX_NEW_CLIENT_GROUPS_PER_HOUR) return;
        }
        await this.prisma.errorGroup.create({ data: { ...data, fingerprint: fp, source: r.source.slice(0, 40), message: r.message.slice(0, 1000), firstSeen: now } });
        this.queueAlert(`${r.source}: ${r.message}`);
      }
    } catch (e) {
      this.logger.warn(`could not record error: ${(e as Error).message}`);
    }
  }

  private queueAlert(line: string) {
    this.pendingNew.push(line.slice(0, 300));
    const wait = this.lastAlert + 10 * 60_000 - Date.now();
    if (wait > 0) {
      if (this.pendingNew.length === 1) setTimeout(() => void this.flush(), wait).unref();
      return;
    }
    void this.flush();
  }

  async flush() {
    if (!this.pendingNew.length) return;
    const lines = this.pendingNew.splice(0);
    this.lastAlert = Date.now();
    const sent = await this.email
      .sendAlert(`${lines.length} new error${lines.length > 1 ? 's' : ''}`, `New errors (details in Admin → Operations):\n\n${lines.map((l) => `• ${l}`).join('\n')}`)
      .catch((e) => (this.logger.warn(`alert email failed: ${(e as Error).message}`), false));
    if (!sent) this.logger.warn(`new errors (email not set up): ${lines.join(' | ')}`);
  }
}
