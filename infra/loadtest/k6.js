// Event 360 load test (dev, in-cluster against http://api:3000).
// Scenarios: public browsing, a sold-out rush (sign in + claim 1 of 300 seats), door scanning.
// SCENARIOS (comma list) picks which run; default "browse,rush,scan". SCENARIOS=seated,seats_read runs the reserved-seating
// test instead: BUYERS (1,000) buyers on a 500-seat map plus SEATS_RATE (50) req/s on GET /seats.
// LT is then the LOADTEST_SEATED JSON from data.js. The free-ticket scenarios need the LOADTEST JSON.
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const API = __ENV.API || 'http://api:3000';
const LT = JSON.parse(__ENV.LT);
const json = { headers: { 'content-type': 'application/json' } };
const claimed = new Counter('rush_claimed');
const soldOut = new Counter('rush_sold_out');
const scanAccepted = new Counter('scan_accepted');
const scanDuplicate = new Counter('scan_duplicate');
const seatedClaimed = new Counter('seated_claimed'); // seats successfully ordered
const seatedConflict = new Counter('seated_conflict'); // orders refused with 409 (a seat was just taken)
const seatedBestNone = new Counter('seated_best_none'); // /seats/best found no seats together (409)
const http5xx = new Rate('http_5xx'); // seated scenarios only
const BUYERS = Number(__ENV.BUYERS || 1000);
const SEATS_RATE = Number(__ENV.SEATS_RATE || 50);
const SEATS_NAME = 'GET /seats (load)';

const ALL = {
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
    seated: {
      executor: 'shared-iterations', exec: 'seated', vus: Math.min(200, BUYERS), iterations: BUYERS, maxDuration: '300s',
    },
    seats_read: {
      executor: 'constant-arrival-rate', exec: 'seatsRead', rate: SEATS_RATE, timeUnit: '1s', duration: __ENV.SEATS_DURATION || '60s',
      preAllocatedVUs: 50, maxVUs: 300,
    },
};
const picked = (__ENV.SCENARIOS || 'browse,rush,scan').split(',').map((x) => x.trim());
const THRESHOLDS = {
  browse: { 'http_req_duration{scenario:browse}': ['p(95)<800'], 'http_req_failed{scenario:browse}': ['rate<0.01'] },
  scan: { 'http_req_duration{scenario:scan}': ['p(95)<500'] },
  seated: { http_5xx: ['rate==0'] },
  seats_read: { [`http_req_duration{name:${SEATS_NAME}}`]: ['p(95)<300'] },
};

export const options = {
  setupTimeout: '300s',
  scenarios: Object.fromEntries(Object.entries(ALL).filter(([k]) => picked.includes(k))),
  thresholds: Object.assign({}, ...picked.map((k) => THRESHOLDS[k] || {})),
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
  if (!LT.door) return {}; // the seated run has no door ticket type or crew code
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

// ---- Seated: 500 assigned seats on a 600-seat map; the other 100 are unassigned and must never sell ----
const TYPE_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

// Seat keys in the order the API's expandSeats returns them (seated sections, rows, seats); `status` and `seatTypes` follow it.
function expandKeys(layout) {
  const out = [];
  for (const sec of layout.sections) {
    if (sec.kind !== 'SEATED' || !sec.rows) continue;
    for (const row of sec.rows) for (const s of row.seats) out.push(`${sec.key}:${row.label}:${s.label !== undefined && s.label !== null ? s.label : s.n}`);
  }
  return out;
}

let keyCache = { versionId: null, keys: null };

function seatsGet(tag, headers) {
  const r = http.get(`${API}/v1/events/${LT.eventId}/seats`, { headers, tags: { name: tag } });
  http5xx.add(r.status >= 500);
  return r;
}

export function seatsRead() {
  const r = seatsGet(SEATS_NAME);
  check(r, { 'seats 200': (x) => x.status === 200 });
}

function pickAvailable(body, n) {
  if (keyCache.versionId !== body.versionId) keyCache = { versionId: body.versionId, keys: expandKeys(body.layout) };
  const ti = body.types.findIndex((t) => t.id === LT.ticketTypeId);
  const ch = TYPE_CHARS[ti];
  const free = [];
  for (let i = 0; i < body.status.length; i++) if (body.status[i] === 'A' && body.seatTypes[i] === ch) free.push(keyCache.keys[i]);
  const out = [];
  while (out.length < n && free.length) out.push(free.splice(Math.floor(Math.random() * free.length), 1)[0]);
  return out;
}

export function seated() {
  const t = signIn(phone());
  if (!t) return;
  const auth = { authorization: `Bearer ${t}` };
  const want = 1 + Math.floor(Math.random() * 2); // 1 or 2 seats
  let seats;
  if (exec.scenario.iterationInTest % 2 === 0) {
    // Half pick random available seats themselves from the (up to 2 s old) availability
    const r = seatsGet('GET /seats (buyer)', auth);
    if (r.status !== 200) return;
    seats = pickAvailable(r.json(), want);
  } else {
    // The other half ask for the best seats together
    const r = http.post(`${API}/v1/events/${LT.eventId}/seats/best`, JSON.stringify({ ticketTypeId: LT.ticketTypeId, quantity: want }), { headers: { 'content-type': 'application/json', ...auth }, tags: { name: 'POST /seats/best' } });
    http5xx.add(r.status >= 500);
    if (r.status === 409) { seatedBestNone.add(1); return; }
    if (r.status !== 200) return;
    seats = r.json('seats');
  }
  if (!seats || !seats.length) return; // sold out as far as this buyer can see
  const o = http.post(`${API}/v1/events/${LT.eventId}/orders`, JSON.stringify({ seats, idempotencyKey: `lt-${exec.vu.idInTest}-${exec.scenario.iterationInTest}-${Date.now()}` }), {
    headers: { 'content-type': 'application/json', ...auth },
    tags: { name: 'POST /orders (seated)' },
  });
  http5xx.add(o.status >= 500);
  if (o.status < 300) seatedClaimed.add(seats.length);
  else if (o.status === 409) seatedConflict.add(1);
  check(o, { 'seated handled': (x) => x.status < 300 || x.status === 409 });
}
