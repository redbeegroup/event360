import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SettingsService, SmsConfig } from './settings.service';

export const SMSPOH_BASE = 'https://v3.smspoh.com/api/rest';

export class SmsError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
  ) {
    super(message);
  }
}

/** 09xxxxxxxxx / +959… / 959… → 959… (what SMSPoh v3 accepts). */
export function toSmsPohNumber(phone: string): string {
  const d = phone.replace(/\D/g, '');
  if (d.startsWith('959')) return d;
  if (d.startsWith('09')) return `95${d.slice(1)}`;
  return d;
}

const mask = (n: string) => (n.length > 7 ? `${n.slice(0, 3)}•••••${n.slice(-4)}` : '•••');

/** Sends SMS through the provider configured in the admin portal (SMSPoh v3 REST). */
@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
  ) {}

  private auth(c: SmsConfig) {
    return `Bearer ${Buffer.from(`${c.apiKey}:${c.apiSecret}`).toString('base64')}`;
  }

  private async call(c: SmsConfig, path: string, init: RequestInit) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 10_000);
    try {
      const res = await fetch(`${SMSPOH_BASE}${path}`, {
        ...init,
        signal: ctl.signal,
        headers: { authorization: this.auth(c), 'content-type': 'application/json', accept: 'application/json', ...(init.headers ?? {}) },
      });
      const text = await res.text();
      let body: any = null;
      try {
        body = text ? JSON.parse(text) : null;
      } catch {
        body = { message: text.slice(0, 200) };
      }
      if (!res.ok) throw new SmsError(body?.message ?? `SMS provider error (HTTP ${res.status})`, res.status);
      return body;
    } catch (e) {
      if (e instanceof SmsError) throw e;
      throw new SmsError((e as Error).name === 'AbortError' ? 'SMS provider timed out' : `SMS provider unreachable: ${(e as Error).message}`);
    } finally {
      clearTimeout(timer);
    }
  }

  /** Sends one SMS; logs the result (without the text). Throws SmsError on failure. */
  async send(phone: string, message: string, purpose: 'otp' | 'test' | 'notify', c?: SmsConfig) {
    const cfg = c ?? (await this.settings.smsConfig());
    if (!cfg) throw new SmsError('SMS is not configured');
    const to = toSmsPohNumber(phone);
    const ref = `${purpose}-${Date.now().toString(36)}`;
    try {
      const body = await this.call(cfg, '/send', {
        method: 'POST',
        body: JSON.stringify({ to, message, from: cfg.senderId, clientReference: ref, ...(cfg.testMode ? { test: true } : {}) }),
      });
      const m = body?.messages?.[0];
      await this.prisma.smsLog.create({
        data: { provider: cfg.provider, to: mask(to), purpose, status: 'accepted', providerMessageId: m?.messageId ?? null, testMode: cfg.testMode },
      });
      return { messageId: m?.messageId as string | undefined, status: m?.status as string | undefined, network: m?.network as string | undefined };
    } catch (e) {
      const err = e as SmsError;
      this.logger.warn(`SMS to ${mask(to)} failed: ${err.message}`);
      await this.prisma.smsLog.create({
        data: { provider: cfg.provider, to: mask(to), purpose, status: 'failed', error: err.message.slice(0, 300), testMode: cfg.testMode },
      });
      throw err;
    }
  }

  async balance(): Promise<{ balance: number; currency: string } | null> {
    const cfg = await this.settings.smsConfig();
    if (!cfg) return null;
    const b = await this.call(cfg, '/account/get-balance', { method: 'GET' });
    return { balance: Number(b?.balance ?? 0), currency: String(b?.currency ?? 'MMK') };
  }

  /** Decrypted SMS settings (null when not configured). */
  settingsConfig() {
    return this.settings.smsConfig();
  }

  /** Sends a login code using the admin-defined template. */
  async sendOtp(phone: string, code: string, minutes: number) {
    const cfg = await this.settings.smsConfig();
    if (!cfg || !cfg.enabled) throw new ServiceUnavailableException('SMS login is not available yet');
    const text = cfg.otpTemplate.replaceAll('{code}', code).replaceAll('{minutes}', String(minutes));
    return this.send(phone, text, 'otp', cfg);
  }

  recentLog(limit = 50) {
    return this.prisma.smsLog.findMany({ orderBy: { createdAt: 'desc' }, take: Math.min(Math.max(limit, 1), 200) });
  }
}
