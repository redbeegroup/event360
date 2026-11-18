import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createPrivateKey, createPublicKey, generateKeyPairSync, KeyObject, sign, verify } from 'crypto';

export interface TicketClaims {
  tid: string; // ticket id
  eid: string; // event id
  tt: string; // ticket type id
  v: number; // QR version (bumped on transfer → old QR invalid)
}

/**
 * Signs ticket QR payloads with Ed25519 (ADR-0001 §6). Format matches mobile/packages/ticketing:
 *   base64url(JSON claims) + "." + base64url(signature)
 * The private key comes from QR_SIGNING_KEY (base64 PKCS#8 DER). Crew apps verify offline with the public key.
 */
@Injectable()
export class TicketTokenService {
  private readonly logger = new Logger(TicketTokenService.name);
  private readonly privateKey: KeyObject;
  private readonly publicKey: KeyObject;

  constructor(config: ConfigService) {
    const b64 = config.get<string>('QR_SIGNING_KEY');
    if (b64) {
      this.privateKey = createPrivateKey({ key: Buffer.from(b64, 'base64'), format: 'der', type: 'pkcs8' });
    } else {
      if (config.get('NODE_ENV') === 'production' && config.get('ALLOW_EPHEMERAL_QR_KEY') !== 'true') {
        throw new Error('QR_SIGNING_KEY is required in production');
      }
      this.logger.warn('QR_SIGNING_KEY not set: using an ephemeral key (QR codes change on restart)');
      this.privateKey = generateKeyPairSync('ed25519').privateKey;
    }
    this.publicKey = createPublicKey(this.privateKey);
  }

  sign(claims: TicketClaims): string {
    const payload = Buffer.from(JSON.stringify(claims));
    const sig = sign(null, payload, this.privateKey);
    return `${payload.toString('base64url')}.${sig.toString('base64url')}`;
  }

  verify(token: string): TicketClaims | null {
    const [p, s] = token.split('.');
    if (!p || !s) return null;
    try {
      const payload = Buffer.from(p, 'base64url');
      if (!verify(null, payload, this.publicKey, Buffer.from(s, 'base64url'))) return null;
      return JSON.parse(payload.toString()) as TicketClaims;
    } catch {
      return null;
    }
  }

  /** Raw 32-byte Ed25519 public key, base64 — what the Flutter verifier expects. */
  publicKeyRaw(): string {
    const jwk = this.publicKey.export({ format: 'jwk' }) as { x: string };
    return Buffer.from(jwk.x, 'base64url').toString('base64');
  }
}
