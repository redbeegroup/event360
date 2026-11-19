/** HTML for the dev-only Mock pay checkout (no scripts; plain forms). */
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

const shell = (body: string) => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mock pay · Event 360</title><style>
body{margin:0;font:16px/1.5 system-ui,sans-serif;background:#f4f1fb;color:#1d1b20;display:flex;min-height:100vh;align-items:center;justify-content:center}
.card{background:#fff;border-radius:16px;box-shadow:0 4px 24px rgba(0,0,0,.08);padding:28px;max-width:380px;width:calc(100% - 32px)}
.tag{display:inline-block;background:#fff3cd;color:#7a5b00;border-radius:6px;padding:2px 8px;font-size:12px;font-weight:700}
h1{font-size:20px;margin:12px 0 4px}.amt{font-size:32px;font-weight:800;margin:12px 0 20px}
button{display:block;width:100%;border:0;border-radius:10px;padding:14px;font-size:16px;font-weight:700;margin-top:10px;cursor:pointer}
.pay{background:#5b3fd6;color:#fff}.fail{background:#fde2e2;color:#a01818}.silent{background:#eee;color:#333}
a{color:#5b3fd6;font-weight:700}p.small{font-size:13px;color:#666}</style></head><body><div class="card">${body}</div></body></html>`;

export function mockPage(p: { id: string; t: string; amount: bigint; title: string; status: string }) {
  if (p.status !== 'PENDING' && p.status !== 'INITIATED') {
    return shell(`<span class="tag">TEST WALLET</span><h1>This payment is ${esc(p.status.toLowerCase())}</h1><p>Return to the Event 360 app.</p>`);
  }
  const form = (outcome: string, cls: string, label: string) =>
    `<form method="post" action="/v1/payments/mock/${p.id}/${outcome}"><input type="hidden" name="t" value="${esc(p.t)}"><button class="${cls}">${label}</button></form>`;
  return shell(`<span class="tag">TEST WALLET · NO REAL MONEY</span>
<h1>${esc(p.title)}</h1><div class="amt">${Number(p.amount).toLocaleString('en-US')} MMK</div>
${form('pay', 'pay', 'Pay')}${form('fail', 'fail', 'Decline')}${form('silent', 'silent', 'Pay, but lose the callback')}
<p class="small">"Lose the callback" tests the background status check: tickets appear within about a minute.</p>`);
}

export function mockResultPage(p: { outcome: string; returnUrl?: string }) {
  const msg =
    p.outcome === 'done'
      ? 'Thank you.'
      : p.outcome === 'fail'
        ? 'Payment declined.'
        : p.outcome === 'silent'
          ? 'Paid. The callback was dropped on purpose.'
          : 'Payment successful.';
  const back = p.returnUrl ? `<p><a href="${esc(p.returnUrl)}">Return to Event 360</a></p>` : '<p>You can return to the Event 360 app now.</p>';
  const tag = p.outcome === 'done' ? '' : '<span class="tag">TEST WALLET</span>';
  return shell(`${tag}<h1>${msg}</h1>${back}`);
}
