import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SecretBox } from '../../common/secret-box';
import { PrismaService } from '../prisma/prisma.service';

export const DEFAULT_OTP_TEMPLATE = 'Your Event 360 code is {code}. Valid {minutes} minutes. Do not share it.';

/** Stored form of the "sms" setting (apiSecret sealed with SETTINGS_KEY). */
interface StoredSms {
  provider: 'smspoh';
  apiKey?: string;
  apiSecretSealed?: string;
  senderId?: string;
  enabled?: boolean;
  testMode?: boolean;
  otpTemplate?: string;
  /** Waitlist offers by SMS (one per offer) while SMS is enabled; unset = on. */
  waitlistSms?: boolean;
}

/** Decrypted settings, for sending only — never returned by the API. */
export interface SmsConfig {
  provider: 'smspoh';
  apiKey: string;
  apiSecret: string;
  senderId: string;
  enabled: boolean;
  testMode: boolean;
  otpTemplate: string;
  waitlistSms: boolean;
}

export interface SmsSettingsInput {
  apiKey?: string;
  apiSecret?: string; // empty/undefined = keep the current one
  senderId?: string;
  enabled?: boolean;
  testMode?: boolean;
  otpTemplate?: string;
  waitlistSms?: boolean;
}

const last4 = (s?: string) => (s ? `••••${s.slice(-4)}` : null);

@Injectable()
export class SettingsService {
  private readonly logger = new Logger(SettingsService.name);
  private box: SecretBox | null = null;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    try {
      this.box = new SecretBox(config.get<string>('SETTINGS_KEY'));
    } catch {
      this.logger.warn('SETTINGS_KEY is not set: secrets cannot be saved or read (SMS disabled)');
    }
  }

  private async stored(): Promise<StoredSms> {
    const row = await this.prisma.platformSetting.findUnique({ where: { key: 'sms' } });
    return (row?.value as unknown as StoredSms) ?? { provider: 'smspoh' };
  }

  /** What admins see: no secret, only whether it is set (and its last 4 characters). */
  async smsView() {
    const s = await this.stored();
    let secretHint: string | null = null;
    if (s.apiSecretSealed && this.box) {
      try {
        secretHint = last4(this.box.open(s.apiSecretSealed));
      } catch {
        secretHint = '(cannot decrypt — re-enter)';
      }
    }
    return {
      provider: s.provider ?? 'smspoh',
      apiKey: s.apiKey ? `${s.apiKey.slice(0, 4)}••••${s.apiKey.slice(-4)}` : null,
      apiSecretSet: !!s.apiSecretSealed,
      apiSecretHint: secretHint,
      senderId: s.senderId ?? '',
      enabled: !!s.enabled,
      testMode: !!s.testMode,
      otpTemplate: s.otpTemplate || DEFAULT_OTP_TEMPLATE,
      waitlistSms: s.waitlistSms ?? true,
      canStoreSecrets: !!this.box,
    };
  }

  async updateSms(input: SmsSettingsInput, actorId: string) {
    if (!this.box) throw new Error('SETTINGS_KEY is not configured on the server');
    const cur = await this.stored();
    const next: StoredSms = {
      provider: 'smspoh',
      apiKey: input.apiKey?.trim() ? input.apiKey.trim() : cur.apiKey,
      apiSecretSealed: input.apiSecret?.trim() ? this.box.seal(input.apiSecret.trim()) : cur.apiSecretSealed,
      senderId: input.senderId !== undefined ? input.senderId.trim() : cur.senderId,
      enabled: input.enabled ?? cur.enabled ?? false,
      testMode: input.testMode ?? cur.testMode ?? false,
      otpTemplate: input.otpTemplate?.trim() || cur.otpTemplate || DEFAULT_OTP_TEMPLATE,
      waitlistSms: input.waitlistSms ?? cur.waitlistSms ?? true,
    };
    await this.prisma.$transaction([
      this.prisma.platformSetting.upsert({
        where: { key: 'sms' },
        create: { key: 'sms', value: next as object, updatedById: actorId },
        update: { value: next as object, updatedById: actorId },
      }),
      this.prisma.auditLog.create({
        data: {
          actorId,
          action: 'settings.sms.update',
          entityType: 'platform_setting',
          entityId: 'sms',
          data: {
            changed: Object.keys(input).filter((k) => (input as Record<string, unknown>)[k] !== undefined && (input as Record<string, unknown>)[k] !== ''),
            enabled: next.enabled,
            testMode: next.testMode,
            waitlistSms: next.waitlistSms,
          },
        },
      }),
    ]);
    return this.smsView();
  }

  /** Decrypted config, or null when SMS isn't fully configured. */
  async smsConfig(): Promise<SmsConfig | null> {
    const s = await this.stored();
    if (!this.box || !s.apiKey || !s.apiSecretSealed || !s.senderId) return null;
    let apiSecret: string;
    try {
      apiSecret = this.box.open(s.apiSecretSealed);
    } catch {
      this.logger.error('Stored SMS secret cannot be decrypted (SETTINGS_KEY changed?)');
      return null;
    }
    return {
      provider: 'smspoh',
      apiKey: s.apiKey,
      apiSecret,
      senderId: s.senderId,
      enabled: !!s.enabled,
      testMode: !!s.testMode,
      otpTemplate: s.otpTemplate || DEFAULT_OTP_TEMPLATE,
      waitlistSms: s.waitlistSms ?? true,
    };
  }
}

// ───────────── payment providers ─────────────

export type PaymentProviderKey = 'kbzpay' | 'wavepay';

/** Plain and secret (sealed) fields per payment provider. */
export const PAYMENT_PROVIDER_FIELDS: Record<PaymentProviderKey, { plain: string[]; secret: string[] }> = {
  kbzpay: { plain: ['merchantCode', 'appId'], secret: ['appKey'] },
  wavepay: { plain: ['merchantId'], secret: ['secretKey'] },
};

interface StoredPayment {
  plain?: Record<string, string>;
  sealed?: Record<string, string>;
  mode?: 'sandbox' | 'production';
  enabled?: boolean;
}

export interface PaymentProviderConfig {
  key: PaymentProviderKey;
  mode: 'sandbox' | 'production';
  enabled: boolean;
  values: Record<string, string>; // plain + decrypted secrets
}

export interface PaymentSettingsInput {
  values?: Record<string, string | undefined>; // empty secret = keep the current one
  mode?: 'sandbox' | 'production';
  enabled?: boolean;
}

@Injectable()
export class PaymentSettingsService {
  private readonly logger = new Logger(PaymentSettingsService.name);
  private box: SecretBox | null = null;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    try {
      this.box = new SecretBox(config.get<string>('SETTINGS_KEY'));
    } catch {
      this.box = null;
    }
  }

  private async stored(key: PaymentProviderKey): Promise<StoredPayment> {
    const row = await this.prisma.platformSetting.findUnique({ where: { key: `payment.${key}` } });
    return (row?.value as unknown as StoredPayment) ?? {};
  }

  private open(sealed: string): string | null {
    if (!this.box) return null;
    try {
      return this.box.open(sealed);
    } catch {
      return null;
    }
  }

  /** Admin view: plain values, secrets only as "set" + last 4 characters. */
  async view(key: PaymentProviderKey) {
    const s = await this.stored(key);
    const f = PAYMENT_PROVIDER_FIELDS[key];
    const secrets: Record<string, { set: boolean; hint: string | null }> = {};
    for (const k of f.secret) {
      const sealed = s.sealed?.[k];
      const v = sealed ? this.open(sealed) : null;
      secrets[k] = { set: !!sealed, hint: sealed ? (v ? last4(v) : '(cannot decrypt — re-enter)') : null };
    }
    return {
      provider: key,
      plain: Object.fromEntries(f.plain.map((k) => [k, s.plain?.[k] ?? ''])),
      secrets,
      mode: s.mode ?? 'sandbox',
      enabled: !!s.enabled,
      canStoreSecrets: !!this.box,
    };
  }

  async update(key: PaymentProviderKey, input: PaymentSettingsInput, actorId: string) {
    if (!this.box) throw new Error('SETTINGS_KEY is not configured on the server');
    const cur = await this.stored(key);
    const f = PAYMENT_PROVIDER_FIELDS[key];
    const plain = { ...(cur.plain ?? {}) };
    const sealed = { ...(cur.sealed ?? {}) };
    for (const k of f.plain) if (input.values?.[k] !== undefined) plain[k] = String(input.values[k]).trim();
    for (const k of f.secret) {
      const v = input.values?.[k]?.trim();
      if (v) sealed[k] = this.box.seal(v);
    }
    const next: StoredPayment = { plain, sealed, mode: input.mode ?? cur.mode ?? 'sandbox', enabled: input.enabled ?? cur.enabled ?? false };
    if (next.enabled && [...f.plain.filter((k) => !plain[k]), ...f.secret.filter((k) => !sealed[k])].length) {
      throw new Error('Fill in every field before enabling this provider');
    }
    await this.prisma.$transaction([
      this.prisma.platformSetting.upsert({
        where: { key: `payment.${key}` },
        create: { key: `payment.${key}`, value: next as object, updatedById: actorId },
        update: { value: next as object, updatedById: actorId },
      }),
      this.prisma.auditLog.create({
        data: {
          actorId,
          action: `settings.payment.${key}.update`,
          entityType: 'platform_setting',
          entityId: `payment.${key}`,
          data: { changed: Object.keys(input.values ?? {}).filter((k) => input.values?.[k]), mode: next.mode, enabled: next.enabled },
        },
      }),
    ]);
    return this.view(key);
  }

  /** Decrypted config, or null when not fully configured. */
  async config(key: PaymentProviderKey): Promise<PaymentProviderConfig | null> {
    const s = await this.stored(key);
    const f = PAYMENT_PROVIDER_FIELDS[key];
    const values: Record<string, string> = {};
    for (const k of f.plain) {
      if (!s.plain?.[k]) return null;
      values[k] = s.plain[k];
    }
    for (const k of f.secret) {
      const v = s.sealed?.[k] ? this.open(s.sealed[k]) : null;
      if (!v) return null;
      values[k] = v;
    }
    return { key, mode: s.mode ?? 'sandbox', enabled: !!s.enabled, values };
  }
}

// ───────────── push (Firebase Cloud Messaging) ─────────────

interface StoredPush {
  projectId?: string;
  clientEmail?: string;
  privateKeySealed?: string;
  enabled?: boolean;
}

export interface PushConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
  enabled: boolean;
}

@Injectable()
export class PushSettingsService {
  private box: SecretBox | null = null;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    try {
      this.box = new SecretBox(config.get<string>('SETTINGS_KEY'));
    } catch {
      this.box = null;
    }
  }

  private async stored(): Promise<StoredPush> {
    const row = await this.prisma.platformSetting.findUnique({ where: { key: 'push' } });
    return (row?.value as unknown as StoredPush) ?? {};
  }

  async view() {
    const s = await this.stored();
    return {
      projectId: s.projectId ?? '',
      clientEmail: s.clientEmail ?? '',
      privateKeySet: !!s.privateKeySealed,
      enabled: !!s.enabled,
      canStoreSecrets: !!this.box,
    };
  }

  /** serviceAccountJson: the key file downloaded from Firebase (only project_id, client_email, private_key are kept). */
  async update(input: { serviceAccountJson?: string; enabled?: boolean }, actorId: string) {
    if (!this.box) throw new Error('SETTINGS_KEY is not configured on the server');
    const cur = await this.stored();
    const next: StoredPush = { ...cur, enabled: input.enabled ?? cur.enabled ?? false };
    if (input.serviceAccountJson?.trim()) {
      let j: { type?: string; project_id?: string; client_email?: string; private_key?: string };
      try {
        j = JSON.parse(input.serviceAccountJson);
      } catch {
        throw new Error('The service account key must be the JSON file downloaded from Firebase');
      }
      if (j.type !== 'service_account' || !j.project_id || !j.client_email || !j.private_key?.includes('PRIVATE KEY')) {
        throw new Error('This is not a Firebase service account key (needs type, project_id, client_email, private_key)');
      }
      next.projectId = j.project_id;
      next.clientEmail = j.client_email;
      next.privateKeySealed = this.box.seal(j.private_key);
    }
    if (next.enabled && !(next.projectId && next.clientEmail && next.privateKeySealed)) throw new Error('Upload the service account key before enabling push');
    await this.prisma.$transaction([
      this.prisma.platformSetting.upsert({
        where: { key: 'push' },
        create: { key: 'push', value: next as object, updatedById: actorId },
        update: { value: next as object, updatedById: actorId },
      }),
      this.prisma.auditLog.create({
        data: { actorId, action: 'settings.push.update', entityType: 'platform_setting', entityId: 'push', data: { keyReplaced: !!input.serviceAccountJson?.trim(), enabled: next.enabled } },
      }),
    ]);
    return this.view();
  }

  async config(): Promise<PushConfig | null> {
    const s = await this.stored();
    if (!this.box || !s.projectId || !s.clientEmail || !s.privateKeySealed) return null;
    try {
      return { projectId: s.projectId, clientEmail: s.clientEmail, privateKey: this.box.open(s.privateKeySealed), enabled: !!s.enabled };
    } catch {
      return null;
    }
  }
}
