// Event 360 load test (dev, in-cluster against http://api:3000).
// Scenarios: public browsing, a sold-out rush (sign in + claim 1 of 300 seats), door scanning.
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const API = __ENV.API || 'http://api:3000';
const LT = JSON.parse(__ENV.LT);
const json = { headers: { 'content-type': 'application/json' } };
const claimed = new Counter('rush_claimed');
const soldOut = new Counter('rush_sold_out');
const scanAccepted = new Counter('scan_accepted');
const scanDuplicate = new Counter('scan_duplicate');

export const options = {
  setupTimeout: '300s',
  scenarios: {
    browse: {
      executor: 'ramping-arrival-rate', exec: 'browse', startRate: 20, timeUnit: '1s',
      preAllocatedVUs: 100, maxVUs: 400,
      stages: [{ target: 100, duration: '30s' }, { target: 300, duration: '60s' }, { target: 300, duration: '30s' }, { target: 0, duration: '10s' }],
    },
    rush: {
      executor: 'shared-iterations', exec: 'rush', vus: 200, iterations: 1000, startTime: '40s', maxDuration: '120s',
    },
    scan: {
      executor: 'constant-arrival-rate', exec: 'scan', rate: 25, timeUnit: '1s', duration: '30s',
      preAllocatedVUs: 40, maxVUs: 200, startTime: '60s',
    },
  },
  thresholds: {
    'http_req_duration{scenario:browse}': ['p(95)<800'],
    'http_req_duration{scenario:scan}': ['p(95)<500'],
    'http_req_failed{scenario:browse}': ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

let seq = 0;
function phone() {
  // 0969000 + 5 digits, unique per VU/iteration (below 90000; setup uses 9xxxx); cleanup removes +95969000… users
  return `0969000${String(__VU * 50 + seq++).padStart(5, '0')}`;
}

function signIn(p) {
  const r1 = http.post(`${API}/v1/auth/otp/request`, JSON.stringify({ phone: p }), { ...json, tags: { name: 'otp/request' } });
  if (r1.status !== 200) return null;
  const r2 = http.post(`${API}/v1/auth/otp/verify`, JSON.stringify({ phone: p, code: r1.json('devCode') }), { ...json, tags: { name: 'otp/verify' } });
  return r2.status === 200 ? r2.json('accessToken') : null;
}

function order(token, ticketTypeId, tagName) {
  return http.post(`${API}/v1/events/${LT.eventId}/orders`, JSON.stringify({ items: [{ ticketTypeId, quantity: 1 }] }), {
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    tags: { name: tagName },
  });
}

// Door tickets for the scan scenario: 400 attendees with a Door ticket each, created up front.
export function setup() {
  const qrs = [];
  for (let i = 0; i < 400; i++) {
    const p = `09690009${String(i).padStart(4, '0')}`; // 0969000 9xxxx
    const t = signIn(p);
    if (!t) continue;
    if (order(t, LT.door, 'setup order').status >= 300) continue;
    const mine = http.get(`${API}/v1/me/tickets`, { headers: { authorization: `Bearer ${t}` }, tags: { name: 'setup tickets' } });
    for (const tk of mine.json() || []) if (tk.qr) qrs.push(tk.qr);
  }
  const r = http.post(`${API}/v1/crew/redeem`, JSON.stringify({ code: LT.code, deviceName: 'k6' }), json);
  return { qrs, crew: r.json('accessToken') };
}

export function browse() {
  const pick = Math.random();
  let r;
  if (pick < 0.45) r = http.get(`${API}/v1/events?limit=20`, { tags: { name: 'GET /events' } });
  else if (pick < 0.8) r = http.get(`${API}/v1/events/${LT.sample}`, { tags: { name: 'GET /events/:slug' } });
  else if (pick < 0.9) r = http.get(`${API}/v1/categories`, { tags: { name: 'GET /categories' } });
  else r = http.get(`${API}/v1/events?limit=20&q=music`, { tags: { name: 'GET /events?q' } });
  check(r, { 'browse 200': (x) => x.status === 200 });
}

export function rush() {
  const t = signIn(phone());
  if (!t) return;
  const r = order(t, LT.rush, 'POST /orders (rush)');
  if (r.status < 300) claimed.add(1);
  else if (r.status === 409 || r.status === 400) soldOut.add(1);
  check(r, { 'rush handled': (x) => x.status < 300 || x.status === 409 || x.status === 400 });
}

export function scan(data) {
  const qr = data.qrs[Math.floor(Math.random() * data.qrs.length)];
  const r = http.post(`${API}/v1/crew/events/${LT.eventId}/scan`, JSON.stringify({ qr, gate: 'LT', deviceId: `k6-${__VU}` }), {
    headers: { 'content-type': 'application/json', authorization: `Bearer ${data.crew}` },
    tags: { name: 'POST /scan' },
  });
  const res = r.status === 200 ? r.json('result') : null;
  if (res === 'ACCEPTED') scanAccepted.add(1);
  else if (res === 'ALREADY_CHECKED_IN') scanDuplicate.add(1);
  check(r, { 'scan 200': (x) => x.status === 200 });
}
