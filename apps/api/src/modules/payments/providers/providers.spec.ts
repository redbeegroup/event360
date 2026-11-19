import { createHash } from 'crypto';
import { fromMerchOrderId, kbzSign, KbzPayProvider, toMerchOrderId } from './kbzpay.provider';
import { waveHash, WavePayProvider } from './wavepay.provider';

const settings = (key: 'kbzpay' | 'wavepay', values: Record<string, string>) =>
  ({ config: async (k: string) => (k === key ? { key, mode: 'sandbox', enabled: true, values } : null) }) as any;

describe('KBZPay', () => {
  const doc =
    'appid=kp123456789987654321abcdefghijkl&merch_code=100001&merch_order_id=201811212009001&method=kbz.payment.precreate&nonce_str=845255910308564481&notify_url=http://test.com/payment/notify&timestamp=1536637503&total_amount=1000&trade_type=APPH5&trans_currency=MMK&version=1.0';
  const fields = Object.fromEntries(doc.split('&').map((kv) => [kv.slice(0, kv.indexOf('=')), kv.slice(kv.indexOf('=') + 1)]));

  it('signs like the doc: sorted, non-empty, &key=, SHA256 uppercase; sign/sign_type/empty/objects excluded', () => {
    const expected = createHash('sha256').update(`${doc}&key=testkey`).digest('hex').toUpperCase();
    expect(expected).toBe('3654FE8324DBC4E24FF949CA53061E2895A13343F7746E60F8CB719CE7126AAF');
    const shuffled = { ...Object.fromEntries(Object.entries(fields).reverse()), sign: 'X', sign_type: 'SHA256', title: '', refund_info: [] as any };
    expect(kbzSign(shuffled, 'testkey')).toBe(expected);
  });

  it('merch_order_id round-trips our payment id', () => {
    const id = '3339531d-5c29-4452-8096-64e3f4ab0ea1';
    expect(toMerchOrderId(id)).toMatch(/^[0-9a-f]{32}$/);
    expect(fromMerchOrderId(toMerchOrderId(id))).toBe(id);
    expect(fromMerchOrderId('other_order')).toBeUndefined();
  });

  const cfg = { merchantCode: '200001', appId: 'kp419a753459284f72aa76d2ae9d6057', appKey: 'k-secret' };

  it('precreate → PWA URL for the app, QR for the web; signed request', async () => {
    const calls: any[] = [];
    const http = async (url: string, init: any) => {
      const req = JSON.parse(init.body).Request;
      calls.push({ url, req });
      const { biz_content, sign, sign_type, ...common } = req;
      expect(sign).toBe(kbzSign({ ...common, ...biz_content }, cfg.appKey));
      return { status: 200, text: async () => JSON.stringify({ Response: { result: 'SUCCESS', code: '0', msg: 'ok', prepay_id: 'KBZ00abc', qrCode: '000201EMV' } }) };
    };
    const p = new KbzPayProvider(settings('kbzpay', cfg), http);
    const base = { paymentId: '3339531d-5c29-4452-8096-64e3f4ab0ea1', orderId: 'o', amountMmk: 25_000n, title: 'Event 360 · Gala', expiresAt: new Date(Date.now() + 600e3), notifyUrl: 'https://api.x/v1/payments/webhook/kbzpay' };
    const app = await p.create({ ...base, channel: 'APP' });
    expect(app.providerRef).toBe('KBZ00abc');
    expect(app.action.url).toMatch(/^https:\/\/static\.kbzpay\.com\/pgw\/uat\/pwa\/#\/\?appid=kp419/);
    const q = new URLSearchParams(app.action.url!.split('?')[1]);
    expect(q.get('sign')).toBe(kbzSign({ appid: q.get('appid'), merch_code: q.get('merch_code'), nonce_str: q.get('nonce_str'), prepay_id: 'KBZ00abc', timestamp: q.get('timestamp') }, cfg.appKey));
    expect(calls[0].req.biz_content).toMatchObject({ trade_type: 'PWAAPP', total_amount: '25000', trans_currency: 'MMK', merch_order_id: '3339531d5c294452809664e3f4ab0ea1' });
    expect(calls[0].req.biz_content.timeout_express).toMatch(/^(9|10)m$/);
    expect(calls[0].url).toBe('http://api-uat.kbzpay.com/payment/gateway/uat/precreate');
    const web = await p.create({ ...base, channel: 'WEB' });
    expect(web.action).toEqual({ type: 'QR', qr: '000201EMV' });
  });

  it('verifies callbacks and maps statuses; rejects tampering', async () => {
    const p = new KbzPayProvider(settings('kbzpay', cfg));
    const req: Record<string, any> = {
      appid: cfg.appId, merch_code: cfg.merchantCode, merch_order_id: '3339531d5c294452809664e3f4ab0ea1', mm_order_id: '0123', total_amount: '25000',
      trans_currency: 'MMK', trade_status: 'PAY_SUCCESS', trans_end_time: 1535166225, notify_time: 1535166225, nonce_str: 'abc', sign_type: 'SHA256',
    };
    req.sign = kbzSign(req, cfg.appKey);
    expect(await p.verifyCallback({}, { Request: req })).toEqual({ paymentId: '3339531d-5c29-4452-8096-64e3f4ab0ea1', status: 'SUCCEEDED', amountMmk: 25_000n });
    await expect(p.verifyCallback({}, { Request: { ...req, total_amount: '1' } })).rejects.toThrow('signature');
    expect(p.callbackAck().body).toBe('success');
  });

  it('queryorder maps trade_status', async () => {
    for (const [st, want] of [['PAY_SUCCESS', 'SUCCEEDED'], [' WAIT_PAY', 'PENDING'], ['ORDER_EXPIRED', 'EXPIRED'], ['PAY_FAILED', 'FAILED']]) {
      const p = new KbzPayProvider(settings('kbzpay', cfg), async () => ({ status: 200, text: async () => JSON.stringify({ Response: { result: 'SUCCESS', code: '0', trade_status: st } }) }));
      expect(await p.query({ paymentId: '3339531d-5c29-4452-8096-64e3f4ab0ea1' })).toBe(want);
    }
    const bad = new KbzPayProvider(settings('kbzpay', cfg), async () => ({ status: 200, text: async () => JSON.stringify({ Response: { result: 'FAIL', code: 'AOP08518', msg: 'IP trustlist' } }) }));
    await expect(bad.query({ paymentId: 'x' })).rejects.toThrow('AOP08518');
  });
});

describe('WavePay', () => {
  it('HMAC-SHA256 of the concatenated values, lowercase; null → "null"', () => {
    expect(waveHash(['Hello', 'Message'], 'secret-key-1234')).toBe('d857c841f6cfe2021999a2c929ac85b6fd299b15192415c26e56fdd500869025');
    expect(waveHash(['300', 'test_merchant', 'ORD1001', '1000', 'https://example.com/cb', 'REF-1001'], 'secret-123')).toBe('f586b791401a3b667e23b70bdfb311f017a883ebc73460a959dda42893cc5c58');
    expect(waveHash([null, 'a'], 'k')).toBe(waveHash(['null', 'a'], 'k'));
  });

  const cfg = { merchantId: 'm-1', secretKey: 'wave-secret' };

  it('create posts the signed form and returns the authenticate URL', async () => {
    let sent: URLSearchParams | undefined;
    const http = async (_u: string, init: any) => {
      sent = new URLSearchParams(init.body);
      return { status: 200, text: async () => JSON.stringify({ message: 'success', transaction_id: 'enc/abc+1' }) };
    };
    const p = new WavePayProvider(settings('wavepay', cfg), 'https://api.x/v1/payments/done', http);
    const r = await p.create({ paymentId: 'pay-1', orderId: 'ord-1', amountMmk: 15_000n, title: 'Gala', expiresAt: new Date(Date.now() + 300e3), notifyUrl: 'https://api.x/cb', channel: 'APP' });
    expect(r.action.url).toBe('https://testpayments.wavemoney.io:8107/authenticate?transaction_id=enc%2Fabc%2B1');
    expect(sent!.get('frontend_result_url')).toBe('https://api.x/v1/payments/done');
    expect(sent!.get('hash')).toBe(waveHash([sent!.get('time_to_live_in_seconds'), 'm-1', 'ord-1', '15000', 'https://api.x/cb', 'pay-1'], cfg.secretKey));
    expect(Number(sent!.get('time_to_live_in_seconds'))).toBeLessThanOrEqual(300);
    const fail = new WavePayProvider(settings('wavepay', cfg), '', async () => ({ status: 400, text: async () => '{"message":"INVALID_HASH"}' }));
    await expect(fail.create({ paymentId: 'p', orderId: 'o', amountMmk: 1n, title: 't', expiresAt: new Date(Date.now() + 300e3), notifyUrl: 'u', channel: 'APP' })).rejects.toThrow('INVALID_HASH');
  });

  it('verifies callbacks; only PAYMENT_CONFIRMED is success', async () => {
    const p = new WavePayProvider(settings('wavepay', cfg), '');
    const b: Record<string, any> = {
      status: 'PAYMENT_CONFIRMED', merchantId: 'm-1', orderId: 'ord-1', merchantReferenceId: 'pay-1', backendResultUrl: 'https://api.x/cb', initiatorMsisdn: '9791234567',
      amount: '15000', timeToLiveSeconds: 300, currency: 'MMK', transactionId: 't1', paymentRequestId: 'r1', requestTime: '2026-11-21T10:00:00', additionalField1: null,
    };
    const sign = (x: any) => waveHash([x.status, x.timeToLiveSeconds, x.merchantId, x.orderId, x.amount, x.backendResultUrl, x.merchantReferenceId, x.initiatorMsisdn, x.transactionId, x.paymentRequestId, x.requestTime], cfg.secretKey);
    expect(await p.verifyCallback({}, { ...b, hashValue: sign(b) })).toEqual({ paymentId: 'pay-1', status: 'SUCCEEDED', amountMmk: 15_000n });
    const t = { ...b, status: 'TRANSACTION_TIMED_OUT' };
    expect((await p.verifyCallback({}, { ...t, hashValue: sign(t) })).status).toBe('FAILED');
    await expect(p.verifyCallback({}, { ...b, amount: '1', hashValue: sign(b) })).rejects.toThrow('hash');
  });
});
