// Pure layout maths for reserved seating. No I/O.

export type SeatAttr = 'RESTRICTED_VIEW' | 'WHEELCHAIR';
export interface LayoutSeat {
  n: number;
  label?: string;
  gapBefore?: number;
  attrs?: SeatAttr[];
  dx?: number;
  dy?: number;
}
export interface LayoutRow {
  label: string;
  seats: LayoutSeat[];
}
export interface LayoutSection {
  key: string;
  name: string;
  nameMy?: string;
  kind: 'SEATED' | 'STANDING';
  x: number;
  y: number;
  rotation?: number;
  curve?: number;
  rows?: LayoutRow[];
  capacity?: number;
  w?: number;
  h?: number;
}
export interface Layout {
  width: number;
  height: number;
  stage?: { x: number; y: number; w: number; h: number; label?: string };
  sections: LayoutSection[];
}
export interface ExpandedSeat {
  seatKey: string;
  sectionKey: string;
  rowLabel: string;
  seatLabel: string;
  label: string;
  labelMy: string;
  x: number;
  y: number;
  attrs: SeatAttr[];
}

/** Layout units between seats and rows. */
export const SEAT_SPACING = 24;

const ATTRS: SeatAttr[] = ['RESTRICTED_VIEW', 'WHEELCHAIR'];
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isStr = (v: unknown): v is string => typeof v === 'string' && v.length > 0;
const seatLabelOf = (s: LayoutSeat) => s.label ?? String(s.n);

export function validateLayout(l: unknown): { ok: true; layout: Layout } | { ok: false; problems: string[] } {
  const problems: string[] = [];
  if (!l || typeof l !== 'object' || Array.isArray(l)) {
    return { ok: false, problems: ['Layout must be an object'] };
  }
  const o = l as Record<string, unknown>;
  if (!isNum(o.width) || !isNum(o.height)) problems.push('Layout width and height must be numbers');
  if (o.stage !== undefined) {
    const st = o.stage as Record<string, unknown> | null;
    if (!st || typeof st !== 'object' || !isNum(st.x) || !isNum(st.y) || !isNum(st.w) || !isNum(st.h)) {
      problems.push('Stage must have numeric x, y, w, h');
    }
  }
  if (!Array.isArray(o.sections)) {
    problems.push('Layout sections must be an array');
    return { ok: false, problems };
  }
  const keys = new Set<string>();
  const seatKeys = new Set<string>();
  for (const [si, raw] of (o.sections as unknown[]).entries()) {
    const s = raw as Record<string, unknown> | null;
    if (!s || typeof s !== 'object') {
      problems.push(`Section #${si + 1} must be an object`);
      continue;
    }
    const k = isStr(s.key) ? s.key : '';
    const where = k ? `Section "${k}"` : `Section #${si + 1}`;
    if (!k) problems.push(`${where} needs a key`);
    else if (k.includes(':')) problems.push(`${where}: key must not contain ":"`);
    else if (keys.has(k)) problems.push(`Duplicate section key "${k}"`);
    else keys.add(k);
    if (!isStr(s.name)) problems.push(`${where} needs a name`);
    if (!isNum(s.x) || !isNum(s.y)) problems.push(`${where} needs numeric x and y`);
    if (s.kind === 'STANDING') {
      if (!isNum(s.capacity) || !Number.isInteger(s.capacity) || s.capacity <= 0) {
        problems.push(`${where}: STANDING section needs a positive integer capacity`);
      }
    } else if (s.kind === 'SEATED') {
      if (!Array.isArray(s.rows) || s.rows.length === 0) {
        problems.push(`${where}: SEATED section needs rows`);
        continue;
      }
      const rowLabels = new Set<string>();
      for (const [ri, rr] of (s.rows as unknown[]).entries()) {
        const r = rr as Record<string, unknown> | null;
        if (!r || typeof r !== 'object' || !isStr(r.label)) {
          problems.push(`${where}: row #${ri + 1} needs a label`);
          continue;
        }
        const rl = r.label;
        if (rl.includes(':')) problems.push(`${where}, row "${rl}": label must not contain ":"`);
        if (rowLabels.has(rl)) problems.push(`${where}: duplicate row label "${rl}"`);
        rowLabels.add(rl);
        if (!Array.isArray(r.seats) || r.seats.length === 0) {
          problems.push(`${where}, row "${rl}": empty row`);
          continue;
        }
        const labels = new Set<string>();
        for (const ss of r.seats as unknown[]) {
          const seat = ss as Record<string, unknown> | null;
          if (!seat || typeof seat !== 'object' || !isNum(seat.n)) {
            problems.push(`${where}, row "${rl}": seat needs a numeric n`);
            continue;
          }
          if (seat.label !== undefined && !isStr(seat.label)) {
            problems.push(`${where}, row "${rl}": seat label must be a non-empty string`);
            continue;
          }
          const lab = seatLabelOf(seat as unknown as LayoutSeat);
          if (lab.includes(':')) problems.push(`${where}, row "${rl}": seat label "${lab}" must not contain ":"`);
          if (labels.has(lab)) problems.push(`${where}, row "${rl}": duplicate seat label "${lab}"`);
          labels.add(lab);
          seatKeys.add(`${k}:${rl}:${lab}`);
          if (seat.gapBefore !== undefined && (!isNum(seat.gapBefore) || seat.gapBefore < 0)) {
            problems.push(`${where}, row "${rl}", seat "${lab}": gapBefore must be >= 0`);
          }
          if (seat.attrs !== undefined) {
            if (!Array.isArray(seat.attrs) || seat.attrs.some((a) => !ATTRS.includes(a as SeatAttr))) {
              problems.push(`${where}, row "${rl}", seat "${lab}": invalid attrs`);
            }
          }
        }
      }
    } else {
      problems.push(`${where}: kind must be SEATED or STANDING`);
    }
  }
  if (problems.length) return { ok: false, problems };
  return { ok: true, layout: l as Layout };
}

/** Seated sections only, in layout order. */
export function expandSeats(l: Layout): ExpandedSeat[] {
  const out: ExpandedSeat[] = [];
  for (const sec of l.sections) {
    if (sec.kind !== 'SEATED' || !sec.rows) continue;
    const rad = ((sec.rotation ?? 0) * Math.PI) / 180;
    const cos = Math.cos(rad);
    const sin = Math.sin(rad);
    const curve = sec.curve ?? 0;
    sec.rows.forEach((row, ri) => {
      // Local (unrotated) x offsets from the section origin, before overrides.
      let col = 0;
      const xs = row.seats.map((s, i) => {
        col += i === 0 ? (s.gapBefore ?? 0) : 1 + (s.gapBefore ?? 0);
        return col * SEAT_SPACING;
      });
      const min = Math.min(...xs);
      const max = Math.max(...xs);
      const centre = (min + max) / 2;
      const half = (max - min) / 2 || 1; // row half width in layout units
      row.seats.forEach((s, i) => {
        const lx = xs[i] + (s.dx ?? 0);
        const t = (xs[i] - centre) / half;
        const ly = ri * SEAT_SPACING + curve * half * t * t + (s.dy ?? 0);
        const seatLabel = seatLabelOf(s);
        const name = sec.name;
        out.push({
          seatKey: `${sec.key}:${row.label}:${seatLabel}`,
          sectionKey: sec.key,
          rowLabel: row.label,
          seatLabel,
          label: `${name} · Row ${row.label} · Seat ${seatLabel}`,
          labelMy: `${sec.nameMy ?? name} · အတန်း ${row.label} · ခုံ ${seatLabel}`,
          x: sec.x + lx * cos - ly * sin,
          y: sec.y + lx * sin + ly * cos,
          attrs: s.attrs ? [...s.attrs] : [],
        });
      });
    });
  }
  return out;
}
