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
import { createHash, randomBytes, randomInt, timingSafeEqual } from 'crypto';
import { PrismaService } from '../prisma/prisma.service';
import { normalizeMyanmarPhone } from './phone';

const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_MS = 60_000;
const REFRESH_TTL_MS = 30 * 24 * 3600 * 1000;

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

    const ttl = Number(this.config.get('OTP_TTL_SECONDS') ?? 300);
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    await this.prisma.otpChallenge.create({
      data: { phone, codeHash: sha256(`${phone}:${code}`), expiresAt: new Date(Date.now() + ttl * 1000) },
    });

    // TODO(Phase 1): dispatch via notifications module → local SMS aggregator.
    const devEcho = this.config.get('OTP_DEV_ECHO') === 'true';
    if (devEcho) this.logger.warn(`DEV OTP for ${phone}: ${code}`);
    return { expiresInSeconds: ttl, ...(devEcho ? { devCode: code } : {}) };
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

    const expected = Buffer.from(challenge.codeHash, 'hex');
    const actual = Buffer.from(sha256(`${phone}:${code}`), 'hex');
    if (!timingSafeEqual(expected, actual)) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException('Invalid code');
    }

    await this.prisma.otpChallenge.update({ where: { id: challenge.id }, data: { consumedAt: new Date() } });

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
