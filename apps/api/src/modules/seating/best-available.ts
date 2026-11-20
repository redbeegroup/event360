// Pure "best available seats" maths for reserved seating. No I/O.
import type { ExpandedSeat, Layout } from './layout';

export type SeatState = ExpandedSeat & { status: string; ticketTypeId: string | null };
type Point = { x: number; y: number };

/** Centre of the stage; without one, the middle of the layout's top edge. */
export function stageCentre(layout: Layout): Point {
  const s = layout.stage;
  return s ? { x: s.x + s.w / 2, y: s.y + s.h / 2 } : { x: layout.width / 2, y: 0 };
}

/**
 * seatKeys that start a new block: seats with `gapBefore > 0` that follow another seat in their row (an aisle).
 * Walks the layout rows directly, so ExpandedSeat keeps its public shape.
 */
export function aisleKeys(layout: Layout): Set<string> {
  const out = new Set<string>();
  for (const sec of layout.sections) {
    if (sec.kind !== 'SEATED' || !sec.rows) continue;
    for (const row of sec.rows) {
      row.seats.forEach((s, i) => {
        if (i > 0 && (s.gapBefore ?? 0) > 0) out.add(`${sec.key}:${row.label}:${s.label ?? String(s.n)}`);
      });
    }
  }
  return out;
}

const dist = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y);

/**
 * Picks `quantity` seats of `ticketTypeId`, or null. `seats` are in layout order. `aisles` (from aisleKeys)
 * marks seats that are not adjacent to the previous one; omitted, every consecutive seat of a row is adjacent.
 * Without a stage, "front" is the topmost seat row and the middle of the seats.
 * 1. The block of `quantity` adjacent AVAILABLE seats in one row whose centre is nearest the stage centre.
 * 2. Else the `quantity` nearest AVAILABLE seats in the section holding the AVAILABLE seat nearest the stage
 *    (never spread across sections).
 * Ties: lower row index, then lower seat index.
 */
export function bestAvailable(seats: SeatState[], stage: Point | undefined, ticketTypeId: string, quantity: number, aisles: Set<string> = new Set()): string[] | null {
  if (!Number.isInteger(quantity) || quantity < 1) return null;
  const centre: Point =
    stage ??
    (seats.length
      ? { x: seats.reduce((a, s) => a + s.x, 0) / seats.length, y: Math.min(...seats.map((s) => s.y)) }
      : { x: 0, y: 0 });
  const ok = (s: SeatState) => s.status === 'AVAILABLE' && s.ticketTypeId === ticketTypeId;

  // Row index per seat: rows are runs of the same section + row label in layout order.
  const rowIdx: number[] = [];
  let r = -1;
  seats.forEach((s, i) => {
    const p = seats[i - 1];
    if (!p || p.sectionKey !== s.sectionKey || p.rowLabel !== s.rowLabel) r++;
    rowIdx.push(r);
  });

  // 1. Adjacent blocks.
  let best: { d: number; row: number; start: number; at: number } | null = null;
  let runStart = 0; // start of the current run of available adjacent seats
  for (let i = 0; i <= seats.length; i++) {
    const s = seats[i];
    const continues = s && i > 0 && ok(s) && ok(seats[i - 1]) && rowIdx[i] === rowIdx[i - 1] && !aisles.has(s.seatKey);
    if (continues) continue;
    // run [runStart, i) just ended
    for (let a = runStart; a + quantity <= i; a++) {
      const block = seats.slice(a, a + quantity);
      const d = dist({ x: block.reduce((t, b) => t + b.x, 0) / quantity, y: block.reduce((t, b) => t + b.y, 0) / quantity }, centre);
      if (!best || d < best.d - 1e-9 || (Math.abs(d - best.d) <= 1e-9 && (rowIdx[a] < best.row || (rowIdx[a] === best.row && a < best.start)))) {
        best = { d, row: rowIdx[a], start: a, at: a };
      }
    }
    runStart = i;
    if (s && !ok(s)) runStart = i + 1;
  }
  if (best) return seats.slice(best.start, best.start + quantity).map((s) => s.seatKey);

  // 2. Nearest seats within the best section.
  const free = seats.map((s, i) => ({ s, i, d: dist(s, centre) })).filter((c) => ok(c.s));
  const cmp = (a: (typeof free)[number], b: (typeof free)[number]) => a.d - b.d || rowIdx[a.i] - rowIdx[b.i] || a.i - b.i;
  free.sort((a, b) => (Math.abs(a.d - b.d) > 1e-9 ? a.d - b.d : cmp(a, b)));
  if (!free.length) return null;
  const sec = free[0].s.sectionKey;
  const inSec = free.filter((c) => c.s.sectionKey === sec);
  if (inSec.length < quantity) return null;
  return inSec.slice(0, quantity).map((c) => c.s.seatKey);
}
