import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { OrgRole, PlatformRole } from '@prisma/client';
import { createHash, randomBytes, randomInt, timingSafeEqual } from 'crypto';
import { hashPassword, verifyPassword } from '../../common/util';
import { SmsService } from '../notifications/sms.service';
import { PrismaService } from '../prisma/prisma.service';
import { normalizeMyanmarPhone } from './phone';

const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_MS = 60_000;
/** Per phone number, independent of IP (mobile carriers often share one IP across many users). */
export const OTP_PER_PHONE_WINDOW_MS = 10 * 60_000;
export const OTP_PER_PHONE_MAX = 5;
const REFRESH_TTL_MS = 30 * 24 * 3600 * 1000;
const INVITE_TTL_MS = 7 * 24 * 3600 * 1000;

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  user: { id: string; phone: string | null; platformRoles: string[] };
}

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly sms: SmsService,
  ) {}

  private phoneOrThrow(raw: string): string {
    const phone = normalizeMyanmarPhone(raw);
    if (!phone) throw new BadRequestException('Invalid Myanmar mobile number');
    return phone;
  }

  async requestOtp(rawPhone: string): Promise<{ expiresInSeconds: number; devCode?: string }> {
    const phone = this.phoneOrThrow(rawPhone);
    const last = await this.prisma.otpChallenge.findFirst({
      where: { phone },
      orderBy: { createdAt: 'desc' },
    });
    if (last && Date.now() - last.createdAt.getTime() < RESEND_COOLDOWN_MS) {
      throw new HttpException('Please wait before requesting another code', HttpStatus.TOO_MANY_REQUESTS);
    }
    const recent = await this.prisma.otpChallenge.count({
      where: { phone, createdAt: { gt: new Date(Date.now() - OTP_PER_PHONE_WINDOW_MS) } },
    });
    if (recent >= OTP_PER_PHONE_MAX) {
      throw new HttpException('Too many codes requested for this number; try again later', HttpStatus.TOO_MANY_REQUESTS);
    }

    const ttl = Number(this.config.get('OTP_TTL_SECONDS') ?? 300);
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const challenge = await this.prisma.otpChallenge.create({
      data: { phone, codeHash: sha256(`${phone}:${code}`), expiresAt: new Date(Date.now() + ttl * 1000) },
    });

    // Dev shows the code on screen and never sends SMS (saves credit).
    if (this.config.get('OTP_DEV_ECHO') === 'true') {
      this.logger.warn(`DEV OTP for ${phone}: ${code}`);
      return { expiresInSeconds: ttl, devCode: code };
    }
    try {
      await this.sms.sendOtp(phone, code, Math.round(ttl / 60));
    } catch (e) {
      // Don't count a code the user never received against their per-number limit.
      await this.prisma.otpChallenge.delete({ where: { id: challenge.id } }).catch(() => undefined);
      if (e instanceof HttpException) throw e;
      throw new HttpException('Could not send the code. Please try again.', HttpStatus.SERVICE_UNAVAILABLE);
    }
    return { expiresInSeconds: ttl };
  }

  async verifyOtp(rawPhone: string, code: string): Promise<TokenPair> {
    const phone = this.phoneOrThrow(rawPhone);
    const challenge = await this.prisma.otpChallenge.findFirst({
      where: { phone, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    if (!challenge || challenge.attempts >= MAX_ATTEMPTS) {
      throw new UnauthorizedException('Code expired or too many attempts');
    }
    // Count the attempt atomically before comparing, so parallel guesses can't exceed MAX_ATTEMPTS
    const counted = await this.prisma.otpChallenge.updateMany({
      where: { id: challenge.id, consumedAt: null, attempts: { lt: MAX_ATTEMPTS } },
      data: { attempts: { increment: 1 } },
    });
    if (counted.count === 0) throw new UnauthorizedException('Code expired or too many attempts');

    const expected = Buffer.from(challenge.codeHash, 'hex');
    const actual = Buffer.from(sha256(`${phone}:${code}`), 'hex');
    if (!timingSafeEqual(expected, actual)) throw new UnauthorizedException('Invalid code');

    // Single use: only one request can consume the code
    const consumed = await this.prisma.otpChallenge.updateMany({
      where: { id: challenge.id, consumedAt: null },
      data: { consumedAt: new Date() },
    });
    if (consumed.count === 0) throw new UnauthorizedException('Code expired or too many attempts');

    const user = await this.prisma.user.upsert({
      where: { phone },
      update: {},
      create: { phone, identities: { create: { provider: 'PHONE', subject: phone } } },
    });
    return this.issueTokens(user);
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    const stored = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: sha256(refreshToken) },
      include: { user: true },
    });
    if (!stored || stored.expiresAt < new Date() || !stored.user.isActive) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (stored.revokedAt) {
      // Reuse of a rotated token → likely theft: revoke the whole family for this user.
      await this.prisma.refreshToken.updateMany({
        where: { userId: stored.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      throw new UnauthorizedException('Refresh token reused');
    }
    await this.prisma.refreshToken.update({ where: { id: stored.id }, data: { revokedAt: new Date() } });
    return this.issueTokens(stored.user);
  }

  /** Ends a session: revokes the given refresh token (unknown tokens are ignored). */
  async logout(refreshToken: string) {
    await this.prisma.refreshToken.updateMany({ where: { tokenHash: sha256(refreshToken), revokedAt: null }, data: { revokedAt: new Date() } });
  }

  /** Portal staff (admins, organizer members) sign in with email + password. */
  async passwordLogin(email: string, password: string): Promise<TokenPair> {
    const user = await this.prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } });
    const ok = await verifyPassword(password, user?.passwordHash);
    if (!user || !ok || !user.isActive) throw new UnauthorizedException('Invalid email or password');
    return this.issueTokens(user);
  }

  /**
   * Creates a one-time invite link (no SMTP yet: the admin copies the link to the invitee).
   * Joining either an organization (orgRole) or the platform staff (platformRole).
   */
  async createInvitation(input: {
    email: string;
    organizationId?: string;
    orgRole?: OrgRole;
    platformRole?: PlatformRole;
    invitedById?: string;
  }): Promise<{ token: string; url: string; expiresAt: Date }> {
    if (!input.orgRole && !input.platformRole) throw new BadRequestException('orgRole or platformRole required');
    if (input.orgRole && !input.organizationId) throw new BadRequestException('organizationId required for orgRole');
    const token = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + INVITE_TTL_MS);
    await this.prisma.invitation.create({
      data: {
        email: input.email.trim().toLowerCase(),
        tokenHash: sha256(token),
        organizationId: input.organizationId,
        orgRole: input.orgRole,
        platformRole: input.platformRole,
        invitedById: input.invitedById,
        expiresAt,
      },
    });
    const portal = (this.config.get<string>('PORTAL_URL') ?? 'http://localhost:3001').replace(/\/$/, '');
    return { token, url: `${portal}/invite/${token}`, expiresAt };
  }

  /** Looks up an invite for the accept page (no secrets returned). */
  async getInvitation(token: string) {
    const inv = await this.prisma.invitation.findUnique({
      where: { tokenHash: sha256(token) },
      include: { organization: { select: { name: true } } },
    });
    if (!inv || inv.acceptedAt || inv.expiresAt < new Date()) throw new BadRequestException('Invite is invalid or expired');
    const existing = await this.prisma.user.findUnique({ where: { email: inv.email }, select: { passwordHash: true } });
    return {
      email: inv.email,
      organization: inv.organization?.name ?? null,
      orgRole: inv.orgRole,
      platformRole: inv.platformRole,
      // The invitee already has a password: they confirm it instead of choosing a new one
      existingAccount: !!existing?.passwordHash,
    };
  }

  async acceptInvitation(token: string, password: string, displayName?: string): Promise<TokenPair> {
    const inv = await this.prisma.invitation.findUnique({ where: { tokenHash: sha256(token) } });
    if (!inv || inv.acceptedAt || inv.expiresAt < new Date()) throw new BadRequestException('Invite is invalid or expired');
    // An invite link only proves someone received it, not that they own the email. If the email already
    // has an account, joining requires that account's current password, and the password is never replaced.
    const current = await this.prisma.user.findUnique({ where: { email: inv.email } });
    if (current?.passwordHash) {
      if (!(await verifyPassword(password, current.passwordHash)) || !current.isActive) {
        throw new BadRequestException('This email already has an Event 360 account. Enter its current password to accept the invite.');
      }
    }
    const passwordHash = current?.passwordHash ? null : await hashPassword(password);

    const user = await this.prisma.$transaction(async (tx) => {
      const existing = await tx.user.findUnique({ where: { email: inv.email } });
      const roles = new Set<PlatformRole>(existing?.platformRoles ?? ['CONSUMER']);
      if (inv.platformRole) roles.add(inv.platformRole);
      const u = existing
        ? await tx.user.update({
            where: { id: existing.id },
            data: {
              platformRoles: [...roles],
              ...(passwordHash && !existing.passwordHash ? { passwordHash } : {}),
              ...(existing.displayName ? {} : { displayName }),
            },
          })
        : await tx.user.create({
            data: {
              email: inv.email,
              passwordHash,
              displayName,
              platformRoles: [...roles],
              identities: { create: { provider: 'EMAIL', subject: inv.email } },
            },
          });
      if (inv.organizationId && inv.orgRole) {
        await tx.organizationMember.upsert({
          where: { organizationId_userId: { organizationId: inv.organizationId, userId: u.id } },
          update: { role: inv.orgRole },
          create: { organizationId: inv.organizationId, userId: u.id, role: inv.orgRole },
        });
      }
      await tx.invitation.update({ where: { id: inv.id }, data: { acceptedAt: new Date() } });
      return u;
    });
    return this.issueTokens(user);
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      include: { memberships: { include: { organization: { select: { id: true, name: true, slug: true, kycStatus: true } } } } },
    });
    if (!user) throw new UnauthorizedException();
    return {
      id: user.id,
      displayName: user.displayName,
      phone: user.phone,
      email: user.email,
      locale: user.locale,
      platformRoles: user.platformRoles,
      organizations: user.memberships.map((m) => ({ ...m.organization, role: m.role })),
    };
  }

  private async issueTokens(user: { id: string; phone: string | null; platformRoles: string[] }): Promise<TokenPair> {
    const accessToken = await this.jwt.signAsync({ sub: user.id, roles: user.platformRoles });
    const refreshToken = randomBytes(48).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: sha256(refreshToken),
        expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
      },
    });
    return {
      accessToken,
      refreshToken,
      user: { id: user.id, phone: user.phone, platformRoles: user.platformRoles },
    };
  }
}
