import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { isIP } from 'net';

/** True for loopback, RFC 1918 private and link-local addresses (IPv4, IPv4-mapped and IPv6). */
export function isPrivateIp(ip: string | undefined | null): boolean {
  if (!ip) return false;
  const v = ip.startsWith('::ffff:') ? ip.slice(7) : ip;
  if (isIP(v) === 4) {
    const [a, b] = v.split('.').map(Number);
    return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254);
  }
  if (isIP(v) === 6) {
    const l = v.toLowerCase();
    return l === '::1' || l.startsWith('fc') || l.startsWith('fd') || l.startsWith('fe80:');
  }
  return false;
}

/**
 * Global rate limit (applied to every route; tighter limits via @Throttle).
 *
 * Requests from the internet reach the API through NPMPlus → Traefik, and with TRUST_PROXY=2 `req.ip`
 * is the visitor's address taken from the hop NPMPlus added (it can't be spoofed by the visitor).
 * The portal forwards that chain too. Calls without it come from inside the cluster or the LAN
 * (website server rendering, SRS hooks, probes, the monitor) and are not limited.
 */
@Injectable()
export class AppThrottlerGuard extends ThrottlerGuard {
  protected async shouldSkip(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<{ ip?: string }>();
    if (process.env.THROTTLE_INTERNAL === 'true') return false; // tests: treat local callers like visitors
    return isPrivateIp(req?.ip) || super.shouldSkip(context);
  }
}
