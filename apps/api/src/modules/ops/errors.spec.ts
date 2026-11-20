import { fingerprint, normalizeMessage, topFrame } from './errors.service';

describe('error grouping', () => {
  it('ignores ids, numbers and quoted values', () => {
    expect(normalizeMessage('Order 3339531d-5c29-4452-8096-64e3f4ab0ea1 not found')).toBe('Order <id> not found');
    expect(normalizeMessage('Timeout after 30000 ms')).toBe('Timeout after <n> ms');
    expect(normalizeMessage('Unknown field "abc" in "xyz"')).toBe('Unknown field "…" in "…"');
  });
  it('uses the first frame of our own code', () => {
    const stack = 'Error: boom\n    at Object.<anonymous> (/app/node_modules/x/index.js:1:2)\n    at PaymentsService.settle (/app/dist/modules/payments/payments.service.js:120:11)';
    expect(topFrame(stack)).toBe('at PaymentsService.settle (/app/dist/modules/payments/payments.service.js');
  });
  it('same bug → same fingerprint; different place or source → different', () => {
    const a = { source: 'api', message: 'Order 3339531d-5c29-4452-8096-64e3f4ab0ea1 failed', stack: 'Error\n    at A.b (/app/dist/a.js:1:1)' };
    const b = { ...a, message: 'Order 11111111-2222-3333-4444-555555555555 failed', stack: 'Error\n    at A.b (/app/dist/a.js:9:9)' };
    expect(fingerprint(a)).toBe(fingerprint(b));
    expect(fingerprint({ ...a, source: 'user_app' })).not.toBe(fingerprint(a));
    expect(fingerprint({ ...a, stack: 'Error\n    at C.d (/app/dist/c.js:1:1)' })).not.toBe(fingerprint(a));
  });
});
