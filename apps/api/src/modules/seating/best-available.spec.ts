import { aisleKeys, bestAvailable, SeatState, stageCentre } from './best-available';
import { expandSeats, Layout } from './layout';

const T = 't1';
function build(layout: Layout, taken: string[] = [], type: (k: string) => string | null = () => T) {
  const seats: SeatState[] = expandSeats(layout).map((s) => ({ ...s, status: taken.includes(s.seatKey) ? 'SOLD' : 'AVAILABLE', ticketTypeId: type(s.seatKey) }));
  return { seats, aisles: aisleKeys(layout), stage: stageCentre(layout) };
}
const row = (n: number, gaps: Record<number, number> = {}) => Array.from({ length: n }, (_, i) => ({ n: i + 1, ...(gaps[i + 1] ? { gapBefore: gaps[i + 1] } : {}) }));
const sec = (key: string, y: number, rows: Layout['sections'][number]['rows'], x = 100) => ({ key, name: key, kind: 'SEATED' as const, x, y, rows });
const base = (sections: Layout['sections']): Layout => ({ width: 400, height: 300, stage: { x: 100, y: 0, w: 200, h: 20 }, sections });

describe('bestAvailable', () => {
  it('picks centre block of adjacent seats in front row', () => {
    const l = base([sec('A', 40, [{ label: '1', seats: row(7) }, { label: '2', seats: row(7) }], 128)]);
    const { seats, stage } = build(l);
    // row spans x=128..272, centred on the stage (200): seats 3-5 are the centre block
    expect(bestAvailable(seats, stage, T, 3)).toEqual(['A:1:3', 'A:1:4', 'A:1:5']);
  });

  it('skips blocks split by an aisle gap', () => {
    const l = base([sec('A', 40, [{ label: '1', seats: row(6, { 4: 2 }) }, { label: '2', seats: row(6) }])]);
    const { seats, stage, aisles } = build(l);
    expect(aisles.has('A:1:4')).toBe(true);
    const got = bestAvailable(seats, stage, T, 4, aisles)!;
    expect(got.every((k) => k.startsWith('A:2:'))).toBe(true); // 3+3 split by the aisle in row 1
    expect(bestAvailable(seats, stage, T, 3, aisles)!.every((k) => k.startsWith('A:1:'))).toBe(true);
  });

  it('falls back to closest scattered seats', () => {
    const l = base([sec('A', 40, [{ label: '1', seats: row(5) }]), sec('B', 200, [{ label: '1', seats: row(5) }])]);
    const { seats, stage } = build(l, ['A:1:2', 'A:1:4', 'B:1:2', 'B:1:4']);
    const got = bestAvailable(seats, stage, T, 3)!;
    expect(got.sort()).toEqual(['A:1:1', 'A:1:3', 'A:1:5']);
  });

  it('returns null when not enough', () => {
    const l = base([sec('A', 40, [{ label: '1', seats: row(3) }]), sec('B', 200, [{ label: '1', seats: row(3) }])]);
    const { seats, stage } = build(l, ['A:1:2']);
    expect(bestAvailable(seats, stage, T, 4)).toBeNull(); // 5 free overall, but never spread across sections
    expect(bestAvailable(seats, stage, T, 0)).toBeNull();
  });

  it('ignores other ticket types and taken seats', () => {
    const l = base([sec('A', 40, [{ label: '1', seats: row(4) }])]);
    const { seats, stage } = build(l, ['A:1:1'], (k) => (k === 'A:1:2' ? 'other' : T));
    expect(bestAvailable(seats, stage, T, 2)).toEqual(['A:1:3', 'A:1:4']);
    expect(bestAvailable(seats, stage, T, 3)).toBeNull();
  });

  it('uses the layout top centre without a stage', () => {
    const l: Layout = { width: 400, height: 300, sections: [sec('A', 40, [{ label: '1', seats: row(5) }])] };
    expect(stageCentre(l)).toEqual({ x: 200, y: 0 });
  });
});
