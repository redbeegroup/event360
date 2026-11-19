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
}

export interface SmsSettingsInput {
  apiKey?: string;
  apiSecret?: string; // empty/undefined = keep the current one
  senderId?: string;
  enabled?: boolean;
  testMode?: boolean;
  otpTemplate?: string;
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
    };
  }
}
