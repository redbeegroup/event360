import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import nodemailer from 'nodemailer';
import { SecretBox } from '../../common/secret-box';
import { PrismaService } from '../prisma/prisma.service';

interface StoredEmail {
  host?: string;
  port?: number;
  secure?: boolean; // implicit TLS (465); otherwise STARTTLS when offered
  user?: string;
  passSealed?: string;
  from?: string;
  alertTo?: string[];
  enabled?: boolean;
}

export interface EmailSettingsInput {
  host?: string;
  port?: number;
  secure?: boolean;
  user?: string;
  pass?: string; // empty = keep
  from?: string;
  alertTo?: string[];
  enabled?: boolean;
}

/** SMTP settings (password sealed with SETTINGS_KEY) and sending, used for operations alerts. */
@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);
  private box: SecretBox | null = null;
  /** Replaced in tests. */
  transport = (opts: Record<string, unknown>) => nodemailer.createTransport(opts as Parameters<typeof nodemailer.createTransport>[0]);

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

  private async stored(): Promise<StoredEmail> {
    const row = await this.prisma.platformSetting.findUnique({ where: { key: 'email' } });
    return (row?.value as unknown as StoredEmail) ?? {};
  }

  async view() {
    const s = await this.stored();
    return {
      host: s.host ?? '',
      port: s.port ?? 587,
      secure: !!s.secure,
      user: s.user ?? '',
      passSet: !!s.passSealed,
      from: s.from ?? '',
      alertTo: s.alertTo ?? [],
      enabled: !!s.enabled,
      canStoreSecrets: !!this.box,
    };
  }

  async update(input: EmailSettingsInput, actorId: string) {
    if (!this.box) throw new Error('SETTINGS_KEY is not configured on the server');
    const cur = await this.stored();
    const next: StoredEmail = {
      host: input.host !== undefined ? input.host.trim() : cur.host,
      port: input.port ?? cur.port ?? 587,
      secure: input.secure ?? cur.secure ?? false,
      user: input.user !== undefined ? input.user.trim() : cur.user,
      passSealed: input.pass?.trim() ? this.box.seal(input.pass) : cur.passSealed,
      from: input.from !== undefined ? input.from.trim() : cur.from,
      alertTo: input.alertTo ?? cur.alertTo ?? [],
      enabled: input.enabled ?? cur.enabled ?? false,
    };
    if (next.enabled && !(next.host && next.from && next.alertTo?.length)) throw new Error('Fill in the server, sender and at least one alert recipient before enabling');
    await this.prisma.$transaction([
      this.prisma.platformSetting.upsert({
        where: { key: 'email' },
        create: { key: 'email', value: next as object, updatedById: actorId },
        update: { value: next as object, updatedById: actorId },
      }),
      this.prisma.auditLog.create({
        data: { actorId, action: 'settings.email.update', entityType: 'platform_setting', entityId: 'email', data: { host: next.host ?? null, enabled: next.enabled, passChanged: !!input.pass?.trim() } },
      }),
    ]);
    return this.view();
  }

  /** Sends to the alert recipients. Returns false when email isn't set up (callers just log). */
  async sendAlert(subject: string, text: string, opts: { force?: boolean } = {}): Promise<boolean> {
    const s = await this.stored();
    if (!s.host || !s.from || !s.alertTo?.length || (!s.enabled && !opts.force)) return false;
    let pass: string | undefined;
    if (s.passSealed && this.box) {
      try {
        pass = this.box.open(s.passSealed);
      } catch {
        this.logger.error('Stored SMTP password cannot be decrypted (SETTINGS_KEY changed?)');
        return false;
      }
    }
    const t = this.transport({
      host: s.host,
      port: s.port ?? 587,
      secure: !!s.secure,
      auth: s.user ? { user: s.user, pass } : undefined,
      connectionTimeout: 10_000,
      greetingTimeout: 10_000,
      socketTimeout: 15_000,
    });
    await t.sendMail({ from: s.from, to: s.alertTo.join(', '), subject: `[Event 360${process.env.ENV_NAME ? ` ${process.env.ENV_NAME}` : ''}] ${subject}`, text });
    return true;
  }
}
