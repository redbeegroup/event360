import { readFileSync } from 'fs';
import { join } from 'path';
import { expandSeats, validateLayout, SEAT_SPACING, Layout } from './layout';

const seats = (n: number) => Array.from({ length: n }, (_, i) => ({ n: i + 1 }));
const base = (over: Partial<Layout['sections'][0]> = {}): Layout => ({
  width: 1000,
  height: 800,
  sections: [
    {
      key: 'A',
      name: 'Stalls',
      kind: 'SEATED',
      x: 100,
      y: 100,
      rows: [
        { label: '1', seats: seats(3) },
        { label: '2', seats: seats(3) },
      ],
      ...over,
    },
  ],
});

describe('expandSeats', () => {
  it('expands 1 section x 2 rows x 3 seats', () => {
    const out = expandSeats(base());
    expect(out).toHaveLength(6);
    expect(out[0].seatKey).toBe('A:1:1');
    expect(out[5].seatKey).toBe('A:2:3');
    expect(out[0].label).toBe('Stalls · Row 1 · Seat 1');
    expect(out[0].labelMy).toBe('Stalls · အတန်း 1 · ခုံ 1');
    expect(out[0].seatLabel).toBe('1');
  });

  it('uses nameMy and explicit seat label when given', () => {
    const l = base({ nameMy: 'ရှေ့ခန်း', rows: [{ label: 'B', seats: [{ n: 1, label: '12' }] }] });
    const [s] = expandSeats(l);
    expect(s.seatKey).toBe('A:B:12');
    expect(s.labelMy).toBe('ရှေ့ခန်း · အတန်း B · ခုံ 12');
  });

  it('an empty nameMy falls back to the English name', () => {
    expect(expandSeats(base({ nameMy: '' }))[0].labelMy).toBe('Stalls · အတန်း 1 · ခုံ 1');
  });

  it('gapBefore shifts x by gap * SEAT_SPACING', () => {
    const l = base({ rows: [{ label: '1', seats: [{ n: 1 }, { n: 2, gapBefore: 2 }, { n: 3 }] }] });
    const out = expandSeats(l);
    expect(out[1].x - out[0].x).toBe(3 * SEAT_SPACING);
    expect(out[2].x - out[1].x).toBe(SEAT_SPACING);
  });

  it('curve moves end seats down relative to the centre', () => {
    const l = base({ curve: 0.5, rows: [{ label: '1', seats: seats(9) }] });
    const out = expandSeats(l);
    expect(out[0].y).toBeGreaterThan(out[4].y);
    expect(out[8].y).toBeGreaterThan(out[4].y);
  });

  it('curve sag is curve * halfWidth at the row ends', () => {
    const l = base({ curve: 0.5, rows: [{ label: '1', seats: seats(10) }] });
    const out = expandSeats(l);
    const halfWidth = (9 * SEAT_SPACING) / 2;
    const sag = out[0].y - out[4].y;
    expect(Math.abs(sag - 0.5 * halfWidth)).toBeLessThan(1);
    expect(out[9].y).toBeCloseTo(out[0].y, 5);
  });

  it('row y advances by SEAT_SPACING', () => {
    const out = expandSeats(base());
    expect(out[3].y - out[0].y).toBe(SEAT_SPACING);
    expect(out[0].x).toBe(100);
  });

  it('applies dx/dy overrides and rotation about the section origin', () => {
    const l = base({ rotation: 90, rows: [{ label: '1', seats: [{ n: 1 }, { n: 2 }] }] });
    const out = expandSeats(l);
    expect(out[1].x).toBeCloseTo(100, 5);
    expect(out[1].y).toBeCloseTo(100 + SEAT_SPACING, 5);
    const d = expandSeats(base({ rows: [{ label: '1', seats: [{ n: 1, dx: 5, dy: 7 }] }] }))[0];
    expect(d.x).toBe(105);
    expect(d.y).toBe(107);
  });

  it('carries attrs', () => {
    const l = base({ rows: [{ label: '1', seats: [{ n: 1, attrs: ['WHEELCHAIR'] }, { n: 2 }] }] });
    const out = expandSeats(l);
    expect(out[0].attrs).toEqual(['WHEELCHAIR']);
    expect(out[1].attrs).toEqual([]);
  });

  it('STANDING sections add no seats', () => {
    const l = base();
    l.sections.push({ key: 'P', name: 'Pit', kind: 'STANDING', x: 0, y: 0, capacity: 300 });
    expect(expandSeats(l)).toHaveLength(6);
  });
});

describe('theatre fixture', () => {
  const raw = JSON.parse(readFileSync(join(__dirname, '__fixtures__', 'theatre.json'), 'utf8'));
  it('validates and expands to 1,200 unique seats', () => {
    const v = validateLayout(raw);
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    const out = expandSeats(v.layout);
    expect(out).toHaveLength(1200);
    expect(new Set(out.map((s) => s.seatKey)).size).toBe(1200);
  });
});

describe('validateLayout', () => {
  const problems = (l: unknown) => {
    const v = validateLayout(l);
    return v.ok ? [] : v.problems;
  };

  it('accepts a valid layout', () => {
    expect(validateLayout(base()).ok).toBe(true);
  });

  it('reports duplicate section keys', () => {
    const l = base();
    l.sections.push({ ...l.sections[0] });
    expect(problems(l).join('\n')).toMatch(/duplicate section key/i);
  });

  it('reports duplicate seat labels in a row', () => {
    const l = base({ rows: [{ label: '1', seats: [{ n: 1 }, { n: 1 }] }] });
    expect(problems(l).join('\n')).toMatch(/duplicate seat label/i);
  });

  it('reports an empty row', () => {
    const l = base({ rows: [{ label: '1', seats: [] }] });
    expect(problems(l).join('\n')).toMatch(/empty row/i);
  });

  it('reports a STANDING section without capacity', () => {
    const l = base();
    l.sections.push({ key: 'P', name: 'Pit', kind: 'STANDING', x: 0, y: 0 });
    expect(problems(l).join('\n')).toMatch(/capacity/i);
  });

  it('reports non-object input and a seated section without rows', () => {
    expect(problems(null).length).toBeGreaterThan(0);
    expect(problems(base({ rows: undefined })).join('\n')).toMatch(/rows/i);
  });

  it('rejects wrongly typed optional fields, one problem per field', () => {
    const bad = (v: unknown) => v as never;
    const seatRow = (seat: object) => [{ label: '1', seats: [{ n: 1, ...seat }] }];
    const cases: [unknown, RegExp][] = [
      [base({ curve: bad('0.5') }), /curve must be a number/],
      [base({ rotation: bad('90') }), /rotation must be a number/],
      [base({ w: bad('1') }), /w must be a number/],
      [base({ h: bad('1') }), /h must be a number/],
      [base({ nameMy: bad(5) }), /nameMy must be a string/],
      [base({ rows: seatRow({ dx: 'a' }) }), /dx and dy must be numbers/],
      [base({ rows: seatRow({ dy: 'a' }) }), /dx and dy must be numbers/],
      [{ ...base(), stage: { x: 0, y: 0, w: 1, h: 1, label: 3 } }, /Stage label must be a string/],
    ];
    for (const [c, re] of cases) {
      const p = problems(c);
      expect(p).toHaveLength(1);
      expect(p[0]).toMatch(re);
    }
  });

  it('accepts null-valued optional fields and treats them as absent', () => {
    const nul = null as never;
    const l = {
      ...base({
        nameMy: nul,
        rotation: nul,
        curve: nul,
        w: nul,
        h: nul,
        rows: [{ label: '1', seats: [{ n: 1, label: nul, gapBefore: nul, attrs: nul, dx: nul, dy: nul }, { n: 2 }] }],
      }),
      stage: { x: 0, y: 0, w: 1, h: 1, label: nul },
    };
    const v = validateLayout(l);
    expect(v.ok).toBe(true);
    if (!v.ok) return;
    const out = expandSeats(v.layout);
    expect(out[0].seatKey).toBe('A:1:1');
    expect(out[0].labelMy).toBe('Stalls · အတန်း 1 · ခုံ 1');
    expect(out[0].x).toBe(100);
    expect(out[1].x - out[0].x).toBe(SEAT_SPACING);
    expect(out[0].attrs).toEqual([]);
    expect(JSON.stringify(v.layout)).not.toContain('null');
  });
});
