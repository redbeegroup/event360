import { UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthService } from './auth.service';

/** Minimal in-memory Prisma double covering the calls AuthService makes. */
function makePrisma() {
  const otps: any[] = [];
  const users: any[] = [];
  const refresh: any[] = [];
  let seq = 0;
  const id = () => `id-${++seq}`;
  const latest = (rows: any[]) => [...rows].sort((a, b) => b.createdAt - a.createdAt)[0] ?? null;
  return {
    otps,
    refresh,
    otpChallenge: {
      findFirst: async ({ where }: any) =>
        latest(
          otps.filter(
            (o) =>
              o.phone === where.phone &&
              (where.consumedAt === undefined || o.consumedAt === null) &&
              (!where.expiresAt || o.expiresAt > where.expiresAt.gt),
          ),
        ),
      count: async ({ where }: any) => otps.filter((o) => o.phone === where.phone && o.createdAt > where.createdAt.gt).length,
      create: async ({ data }: any) => {
        const row = { id: id(), attempts: 0, consumedAt: null, createdAt: new Date(), ...data };
        otps.push(row);
        return row;
      },
      delete: async ({ where }: any) => {
        const i = otps.findIndex((o) => o.id === where.id);
        return otps.splice(i, 1)[0];
      },
      updateMany: async ({ where, data }: any) => {
        const row = otps.find(
          (o) =>
            o.id === where.id &&
            (where.consumedAt === undefined || o.consumedAt === null) &&
            (where.attempts?.lt === undefined || o.attempts < where.attempts.lt),
        );
        if (!row) return { count: 0 };
        if (data.attempts?.increment) row.attempts += data.attempts.increment;
        if (data.consumedAt) row.consumedAt = data.consumedAt;
        return { count: 1 };
      },
      update: async ({ where, data }: any) => {
        const row = otps.find((o) => o.id === where.id);
        if (data.attempts?.increment) row.attempts += data.attempts.increment;
        if (data.consumedAt) row.consumedAt = data.consumedAt;
        return row;
      },
    },
    user: {
      upsert: async ({ where, create }: any) => {
        let u = users.find((x) => x.phone === where.phone);
        if (!u) {
          u = { id: id(), phone: create.phone, platformRoles: ['CONSUMER'], isActive: true };
          users.push(u);
        }
        return u;
      },
    },
    refreshToken: {
      create: async ({ data }: any) => {
        const row = { id: id(), revokedAt: null, ...data };
        refresh.push(row);
        return row;
      },
      findUnique: async ({ where }: any) => {
        const r = refresh.find((x) => x.tokenHash === where.tokenHash);
        return r ? { ...r, user: users.find((u) => u.id === r.userId) } : null;
      },
      update: async ({ where, data }: any) => Object.assign(refresh.find((x) => x.id === where.id), data),
      updateMany: async ({ where, data }: any) => {
        refresh.filter((r) => r.userId === where.userId && r.revokedAt === null).forEach((r) => Object.assign(r, data));
        return {};
      },
    },
  };
}

describe('AuthService (phone OTP)', () => {
  const config = new ConfigService({ OTP_DEV_ECHO: 'true', OTP_TTL_SECONDS: '300' });
  const jwt = new JwtService({ secret: 'test' });
  let prisma: ReturnType<typeof makePrisma>;
  let svc: AuthService;

  beforeEach(() => {
    prisma = makePrisma();
    svc = new AuthService(prisma as any, jwt, config, { sendOtp: jest.fn() } as any);
  });

  it('issues tokens for a correct code and consumes it', async () => {
    const { devCode } = await svc.requestOtp('09123456789');
    const res = await svc.verifyOtp('+959123456789', devCode!);
    expect(res.user.phone).toBe('+959123456789');
    expect(await jwt.verifyAsync(res.accessToken)).toMatchObject({ sub: res.user.id });
    await expect(svc.verifyOtp('09123456789', devCode!)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('locks the challenge after too many wrong attempts', async () => {
    const { devCode } = await svc.requestOtp('09123456789');
    const wrong = devCode === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) {
      await expect(svc.verifyOtp('09123456789', wrong)).rejects.toThrow('Invalid code');
    }
    await expect(svc.verifyOtp('09123456789', devCode!)).rejects.toThrow('too many attempts');
  });

  it('rate-limits resend within the cooldown', async () => {
    await svc.requestOtp('09123456789');
    await expect(svc.requestOtp('09123456789')).rejects.toThrow('Please wait');
  });

  it('rotates refresh tokens and revokes the family on reuse', async () => {
    const { devCode } = await svc.requestOtp('09123456789');
    const first = await svc.verifyOtp('09123456789', devCode!);
    const second = await svc.refresh(first.refreshToken);
    expect(second.refreshToken).not.toBe(first.refreshToken);
    await expect(svc.refresh(first.refreshToken)).rejects.toThrow('reused');
    await expect(svc.refresh(second.refreshToken)).rejects.toThrow('reused');
  });
});

describe('AuthService (production: code sent by SMS)', () => {
  const config = new ConfigService({ OTP_DEV_ECHO: 'false', OTP_TTL_SECONDS: '300' });
  const jwt = new JwtService({ secret: 'test' });

  it('sends the code by SMS and never returns it', async () => {
    const prisma = makePrisma();
    const sms = { sendOtp: jest.fn().mockResolvedValue({ messageId: 'm1' }) };
    const svc = new AuthService(prisma as any, jwt, config, sms as any);
    const r = await svc.requestOtp('09123456789');
    expect(r).toEqual({ expiresInSeconds: 300 });
    expect(sms.sendOtp).toHaveBeenCalledWith('+959123456789', expect.stringMatching(/^\d{6}$/), 5);
    const code = sms.sendOtp.mock.calls[0][1];
    await expect(svc.verifyOtp('09123456789', code)).resolves.toMatchObject({ user: { phone: '+959123456789' } });
  });

  it('a failed send returns 503 and does not use up the cooldown/limit', async () => {
    const prisma = makePrisma();
    const sms = { sendOtp: jest.fn().mockRejectedValueOnce(new Error('timeout')).mockResolvedValue({}) };
    const svc = new AuthService(prisma as any, jwt, config, sms as any);
    await expect(svc.requestOtp('09123456789')).rejects.toMatchObject({ status: 503 });
    expect(prisma.otps).toHaveLength(0);
    await expect(svc.requestOtp('09123456789')).resolves.toEqual({ expiresInSeconds: 300 }); // no "please wait"
  });
});
