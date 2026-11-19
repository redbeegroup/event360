import { createHash, randomBytes, timingSafeEqual } from 'crypto';
import { PaymentSettingsService } from '../../notifications/settings.service';
import { CreateContext, CreateResult, InvalidSignatureError, PaymentProvider, ProviderStatus, VerifiedCallback } from './provider';

/**
 * KBZPay payment gateway (KBZ Bank PGW, API docs at wap.kbzpay.com/pgw/uat/api).
 *  - precreate (kbz.payment.precreate): phones get the PWA checkout URL (trade_type PWAAPP) which opens the KBZPay app;
 *    the web gets an EMV QR (PAY_BY_QRCODE) to scan with KBZPay.
 *  - notify: JSON {Request:{…}} signed like requests; we must answer the literal text "success".
 *  - queryorder (version 3.0) for the reconciler.
 *  - Refunds need a KBZ client certificate (ports 8008/18008), so they are done by hand for now (RefundStatus.MANUAL).
 * KBZ also allow-lists our server IP and (for PWA) a registered referer/return URL; both are set up with KBZ.
 */
const URLS = {
  sandbox: {
    api: 'http://api-uat.kbzpay.com/payment/gateway/uat',
    pwa: 'https://static.kbzpay.com/pgw/uat/pwa/#/',
  },
  production: {
    api: 'https://api.kbzpay.com/payment/gateway',
    pwa: 'https://wap.kbzpay.com/pgw/pwa/#/',
  },
};

type Flat = Record<string, string | number | undefined | null>;

/** SHA256(sorted non-empty k=v joined with & + "&key=<appKey>"), uppercase hex. sign/sign_type and arrays/objects excluded. */
export function kbzSign(fields: Flat, appKey: string): string {
  const a = Object.keys(fields)
    .filter((k) => k !== 'sign' && k !== 'sign_type')
    .filter((k) => {
      const v = fields[k];
      return v !== undefined && v !== null && v !== '' && typeof v !== 'object';
    })
    .sort()
    .map((k) => `${k}=${fields[k]}`)
    .join('&');
  return createHash('sha256').update(`${a}&key=${appKey}`).digest('hex').toUpperCase();
}

/** Our payment UUID ↔ KBZ merch_order_id ([A-Za-z0-9_], ≤ 40). */
export const toMerchOrderId = (paymentId: string) => paymentId.replace(/-/g, '');
export const fromMerchOrderId = (id: string) =>
  /^[0-9a-f]{32}$/i.test(id) ? `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`.toLowerCase() : undefined;

const nonce = () => randomBytes(16).toString('hex');
const ts = () => String(Math.floor(Date.now() / 1000));
const toMmk = (s: unknown) => BigInt(Math.round(Number(String(s).trim())));

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string; signal?: AbortSignal }) => Promise<{ status: number; text(): Promise<string> }>;

export class KbzPayProvider implements PaymentProvider {
  readonly code = 'KBZPAY' as const;
  readonly label = 'KBZPay';

  constructor(
    private readonly settings: PaymentSettingsService,
    private readonly http: FetchLike = (u, i) => fetch(u, i),
  ) {}

  private async cfg() {
    const c = await this.settings.config('kbzpay');
    if (!c) throw new Error('KBZPay is not configured');
    return { ...c, urls: URLS[c.mode], merchCode: c.values.merchantCode, appId: c.values.appId, appKey: c.values.appKey };
  }

  async available() {
    return !!(await this.settings.config('kbzpay'))?.enabled;
  }

  private async call(method: string, version: string, path: string, biz: Flat, extra: Flat = {}) {
    const c = await this.cfg();
    const common: Flat = { timestamp: ts(), method, nonce_str: nonce(), version, ...extra };
    const sign = kbzSign({ ...common, ...biz }, c.appKey);
    const body = JSON.stringify({ Request: { ...common, sign_type: 'SHA256', sign, biz_content: biz } });
    const res = await this.http(`${c.urls.api}/${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
      signal: AbortSignal.timeout(15_000),
    });
    const text = await res.text();
    let json: { Response?: Record<string, unknown> };
    try {
      json = JSON.parse(text);
    } catch {
      throw new Error(`KBZPay HTTP ${res.status}: ${text.slice(0, 200)}`);
    }
    const r = json.Response ?? {};
    if (r.result !== 'SUCCESS' || String(r.code) !== '0') throw new Error(`KBZPay ${method}: ${r.code ?? res.status} ${r.msg ?? ''}`.trim());
    if (r.sign && kbzSign(r as Flat, c.appKey) !== String(r.sign).toUpperCase()) throw new Error('KBZPay response signature mismatch');
    return { r, c };
  }

  async create(ctx: CreateContext): Promise<CreateResult> {
    const minutes = Math.max(1, Math.min(120, Math.floor((ctx.expiresAt.getTime() - Date.now()) / 60e3)));
    const web = ctx.channel === 'WEB';
    const c0 = await this.cfg();
    const biz: Flat = {
      appid: c0.appId,
      merch_code: c0.merchCode,
      merch_order_id: toMerchOrderId(ctx.paymentId),
      trade_type: web ? 'PAY_BY_QRCODE' : 'PWAAPP',
      title: ctx.title.replace(/[^\p{L}\p{N} .,:·-]/gu, '').slice(0, 100),
      total_amount: ctx.amountMmk.toString(),
      trans_currency: 'MMK',
      timeout_express: `${minutes}m`,
    };
    const { r, c } = await this.call('kbz.payment.precreate', '1.0', 'precreate', biz, { notify_url: ctx.notifyUrl });
    const prepayId = String(r.prepay_id ?? '');
    if (!prepayId) throw new Error('KBZPay precreate returned no prepay_id');
    if (web) {
      const qr = String(r.qrCode ?? '');
      if (!qr) throw new Error('KBZPay precreate returned no QR code');
      return { providerRef: prepayId, action: { type: 'QR', qr } };
    }
    const p: Flat = { appid: c.appId, merch_code: c.merchCode, nonce_str: nonce(), prepay_id: prepayId, timestamp: ts() };
    const q = new URLSearchParams({ ...(p as Record<string, string>), sign: kbzSign(p, c.appKey) });
    return { providerRef: prepayId, action: { type: 'REDIRECT', url: `${c.urls.pwa}?${q}` } };
  }

  async verifyCallback(_h: Record<string, string | string[] | undefined>, body: unknown): Promise<VerifiedCallback> {
    const c = await this.cfg();
    const req = ((body as { Request?: Flat })?.Request ?? body) as Flat;
    const sign = String(req?.sign ?? '').toUpperCase();
    const expected = kbzSign(req, c.appKey);
    if (!sign || sign.length !== expected.length || !timingSafeEqual(Buffer.from(sign), Buffer.from(expected))) {
      throw new InvalidSignatureError('bad KBZPay signature');
    }
    if (String(req.merch_code) !== c.merchCode || String(req.appid) !== c.appId) throw new InvalidSignatureError('KBZPay callback for another merchant');
    const status = String(req.trade_status ?? '').trim();
    return {
      paymentId: fromMerchOrderId(String(req.merch_order_id ?? '')),
      status: status === 'PAY_SUCCESS' ? 'SUCCEEDED' : status === 'PAY_FAILED' ? 'FAILED' : status === 'ORDER_EXPIRED' || status === 'ORDER_CLOSED' ? 'EXPIRED' : 'PENDING',
      amountMmk: req.total_amount != null ? toMmk(req.total_amount) : undefined,
    };
  }

  callbackAck() {
    return { contentType: 'text/plain', body: 'success' };
  }

  async query(p: { paymentId: string }): Promise<ProviderStatus> {
    const c = await this.cfg();
    const { r } = await this.call('kbz.payment.queryorder', '3.0', 'queryorder', { appid: c.appId, merch_code: c.merchCode, merch_order_id: toMerchOrderId(p.paymentId) });
    const s = String(r.trade_status ?? '').trim();
    if (s === 'PAY_SUCCESS') return 'SUCCEEDED';
    if (s === 'PAY_FAILED') return 'FAILED';
    if (s === 'ORDER_EXPIRED' || s === 'ORDER_CLOSED') return 'EXPIRED';
    return 'PENDING';
  }
}
