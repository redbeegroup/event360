import { createHmac, timingSafeEqual } from 'crypto';
import { PaymentSettingsService } from '../../notifications/settings.service';
import type { FetchLike } from './kbzpay.provider';
import { CreateContext, CreateResult, InvalidSignatureError, PaymentProvider, ProviderStatus, VerifiedCallback } from './provider';

/**
 * WavePay Payment Gateway (Wave Money "WPPG" merchant document).
 *  - POST /payment (form fields + HMAC-SHA256 hash) → transaction_id → buyer is sent to /authenticate?transaction_id=…
 *    where they enter their WavePay number and approve in the app.
 *  - Callback: JSON to backend_result_url with hashValue; PAYMENT_CONFIRMED is the only success status.
 *  - No status-query or refund API is documented: the reconciler can't poll (callbacks only) and refunds are manual.
 */
const URLS = {
  sandbox: 'https://testpayments.wavemoney.io:8107',
  production: 'https://payments.wavemoney.io',
};

/** HMAC-SHA256 over the values concatenated with no separator (null → "null"), lowercase hex. */
export function waveHash(values: unknown[], secret: string): string {
  return createHmac('sha256', secret)
    .update(values.map((v) => (v === null || v === undefined ? 'null' : String(v))).join(''))
    .digest('hex');
}

const FAILED = new Set(['TRANSACTION_TIMED_OUT', 'ACCOUNT_LOCKED', 'BILL_COLLECTION_FAILED', 'PAYMENT_REQUEST_CANCELLED', 'SCHEDULER_TRANSACTION_TIMED_OUT']);

export class WavePayProvider implements PaymentProvider {
  readonly code = 'WAVEPAY' as const;
  readonly label = 'WavePay';

  constructor(
    private readonly settings: PaymentSettingsService,
    private readonly fallbackReturnUrl: string,
    private readonly http: FetchLike = (u, i) => fetch(u, i),
  ) {}

  private async cfg() {
    const c = await this.settings.config('wavepay');
    if (!c) throw new Error('WavePay is not configured');
    return { base: URLS[c.mode], merchantId: c.values.merchantId, secret: c.values.secretKey };
  }

  async available() {
    return !!(await this.settings.config('wavepay'))?.enabled;
  }

  async create(ctx: CreateContext): Promise<CreateResult> {
    const c = await this.cfg();
    const ttl = String(Math.max(60, Math.min(600, Math.floor((ctx.expiresAt.getTime() - Date.now()) / 1000))));
    const amount = ctx.amountMmk.toString();
    const f: Record<string, string> = {
      time_to_live_in_seconds: ttl,
      merchant_id: c.merchantId,
      order_id: ctx.orderId,
      merchant_reference_id: ctx.paymentId,
      frontend_result_url: ctx.returnUrl ?? this.fallbackReturnUrl,
      backend_result_url: ctx.notifyUrl,
      amount,
      payment_description: ctx.title.slice(0, 100),
      merchant_name: 'Event 360',
      items: JSON.stringify([{ name: ctx.title.slice(0, 100), amount: Number(amount) }]),
    };
    f.hash = waveHash([f.time_to_live_in_seconds, f.merchant_id, f.order_id, f.amount, f.backend_result_url, f.merchant_reference_id], c.secret);
    const res = await this.http(`${c.base}/payment`, {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(f).toString(),
      signal: AbortSignal.timeout(15_000),
    });
    const text = await res.text();
    let j: { message?: string; transaction_id?: string; errors?: unknown } = {};
    try {
      j = JSON.parse(text);
    } catch {
      /* fall through */
    }
    if (res.status !== 200 || !j.transaction_id) throw new Error(`WavePay HTTP ${res.status}: ${j.message ?? (j.errors ? JSON.stringify(j.errors) : text.slice(0, 200))}`);
    const url = `${c.base}/authenticate?transaction_id=${encodeURIComponent(j.transaction_id)}`;
    return { providerRef: j.transaction_id, action: { type: 'REDIRECT', url } };
  }

  async verifyCallback(_h: Record<string, string | string[] | undefined>, body: unknown): Promise<VerifiedCallback> {
    const c = await this.cfg();
    const b = (body ?? {}) as Record<string, unknown>;
    const expected = waveHash(
      [b.status, b.timeToLiveSeconds, b.merchantId, b.orderId, b.amount, b.backendResultUrl, b.merchantReferenceId, b.initiatorMsisdn, b.transactionId, b.paymentRequestId, b.requestTime],
      c.secret,
    );
    const got = String(b.hashValue ?? '').toLowerCase();
    if (got.length !== expected.length || !timingSafeEqual(Buffer.from(got), Buffer.from(expected))) throw new InvalidSignatureError('bad WavePay hash');
    if (String(b.merchantId) !== c.merchantId) throw new InvalidSignatureError('WavePay callback for another merchant');
    const s = String(b.status ?? '');
    return {
      paymentId: typeof b.merchantReferenceId === 'string' ? b.merchantReferenceId : undefined,
      status: s === 'PAYMENT_CONFIRMED' ? 'SUCCEEDED' : FAILED.has(s) ? 'FAILED' : 'PENDING',
      amountMmk: b.amount != null ? BigInt(Math.round(Number(b.amount))) : undefined,
    };
  }

  callbackAck() {
    return { contentType: 'application/json', body: '{"message":"success"}' };
  }

  /** No documented status API: rely on callbacks (the reconciler expires unanswered payments after 2 h). */
  async query(): Promise<ProviderStatus> {
    return 'PENDING';
  }
}
