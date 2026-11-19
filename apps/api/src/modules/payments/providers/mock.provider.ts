import { createHmac, timingSafeEqual } from 'crypto';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateContext, CreateResult, InvalidSignatureError, PaymentProvider, ProviderStatus, VerifiedCallback } from './provider';

/**
 * Dev-only test wallet (PAYMENTS_MOCK=true). Its checkout page is served by the API (/v1/payments/mock/:id) with
 * Pay / Fail / "Pay but don't call back" buttons; the outcome is sent to our own webhook as an HMAC-signed callback,
 * so the real webhook → settle path runs. "Provider-side" state lives in payment_events (kind: mock-state) so the
 * reconciler's query() can find payments whose callback was "lost".
 */
export class MockProvider implements PaymentProvider {
  readonly code = 'MOCK' as const;
  readonly label = 'Mock pay (test)';

  constructor(
    private readonly prisma: PrismaService,
    private readonly enabled: boolean,
    private readonly secret: string,
    private readonly apiBase: string,
  ) {}

  async available() {
    return this.enabled;
  }

  sign(payload: string) {
    return createHmac('sha256', this.secret).update(payload).digest('hex');
  }

  pageToken(paymentId: string) {
    return this.sign(`page:${paymentId}`).slice(0, 32);
  }

  async create(ctx: CreateContext): Promise<CreateResult> {
    const url = `${this.apiBase}/v1/payments/mock/${ctx.paymentId}?t=${this.pageToken(ctx.paymentId)}`;
    return { providerRef: `mock_${ctx.paymentId}`, action: { type: 'REDIRECT', url, qr: url, returnUrl: ctx.returnUrl } };
  }

  /** Callback body the mock page posts to our webhook. */
  callbackFor(paymentId: string, status: 'SUCCEEDED' | 'FAILED', amountMmk: bigint) {
    const body = { paymentId, providerRef: `mock_${paymentId}`, status, amount: amountMmk.toString(), ts: Date.now() };
    return { body, signature: this.sign(JSON.stringify(body)) };
  }

  async verifyCallback(headers: Record<string, string | string[] | undefined>, body: unknown): Promise<VerifiedCallback> {
    const sig = String(headers['x-mock-signature'] ?? '');
    const expected = this.sign(JSON.stringify(body));
    if (sig.length !== expected.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) throw new InvalidSignatureError('bad mock signature');
    const b = body as { paymentId: string; providerRef: string; status: 'SUCCEEDED' | 'FAILED'; amount: string };
    return { paymentId: b.paymentId, providerRef: b.providerRef, status: b.status, amountMmk: BigInt(b.amount) };
  }

  callbackAck() {
    return { contentType: 'application/json', body: '{"ok":true}' };
  }

  /** Records what the "wallet" did, for query(). */
  async recordState(paymentId: string, status: ProviderStatus) {
    await this.prisma.paymentEvent.create({ data: { paymentId, provider: 'MOCK', verified: true, rawPayload: { kind: 'mock-state', status } } });
  }

  async query(p: { paymentId: string }): Promise<ProviderStatus> {
    const ev = await this.prisma.paymentEvent.findMany({ where: { paymentId: p.paymentId, provider: 'MOCK' }, orderBy: { receivedAt: 'desc' }, take: 20 });
    const st = ev.map((e) => e.rawPayload as { kind?: string; status?: ProviderStatus }).find((x) => x.kind === 'mock-state');
    return st?.status ?? 'PENDING';
  }

  async refund(p: { paymentId: string; refundId: string }) {
    return { providerRef: `mockrefund_${p.refundId}` };
  }
}
