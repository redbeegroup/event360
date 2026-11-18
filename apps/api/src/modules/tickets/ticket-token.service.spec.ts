import { ConfigService } from '@nestjs/config';
import { generateKeyPairSync } from 'crypto';
import { TicketTokenService } from './ticket-token.service';

describe('TicketTokenService', () => {
  const der = generateKeyPairSync('ed25519').privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64');
  const svc = new TicketTokenService(new ConfigService({ QR_SIGNING_KEY: der }));
  const claims = { tid: 't1', eid: 'e1', tt: 'tt1', v: 1 };

  it('round-trips signed claims', () => {
    const token = svc.sign(claims);
    expect(token).toMatch(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
    expect(svc.verify(token)).toEqual(claims);
  });

  it('rejects a tampered payload or signature', () => {
    const [p, s] = svc.sign(claims).split('.');
    const forged = Buffer.from(JSON.stringify({ ...claims, tid: 't2' })).toString('base64url');
    expect(svc.verify(`${forged}.${s}`)).toBeNull();
    expect(svc.verify(`${p}.${s.slice(0, -2)}AA`)).toBeNull();
    expect(svc.verify('garbage')).toBeNull();
  });

  it('rejects tokens from another key', () => {
    const other = new TicketTokenService(new ConfigService({ NODE_ENV: 'test' }));
    expect(svc.verify(other.sign(claims))).toBeNull();
  });

  it('exposes a raw 32-byte Ed25519 public key (what the Flutter verifier expects)', () => {
    expect(Buffer.from(svc.publicKeyRaw(), 'base64')).toHaveLength(32);
  });

  it('refuses to start in production without a key', () => {
    // ConfigService reads process.env before its own values, and Jest sets NODE_ENV=test.
    const prev = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    try {
      expect(() => new TicketTokenService(new ConfigService({}))).toThrow(/QR_SIGNING_KEY/);
    } finally {
      process.env.NODE_ENV = prev;
    }
  });
});
