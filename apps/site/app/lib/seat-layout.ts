import 'server-only';
// COPY of the layout types and expandSeats() in apps/api/src/modules/seating/layout.ts (same copy as apps/web/app/lib/seat-layout.ts).
// It MUST stay in sync with the API's layout.ts: the seat order here is the index into the endpoint's `seatTypes` string.
// Do not change logic here without changing the API file. Validation is left out: layouts arrive already validated.

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

const seatLabelOf = (s: LayoutSeat) => s.label ?? String(s.n);

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
