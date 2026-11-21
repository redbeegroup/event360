'use client';

import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { expandSeats, type Layout } from '../lib/seat-layout';

export const SEAT_RADIUS = 9;
export const DEFAULT_SEAT_COLORS = ['#6c2bd9', '#0e8a6a', '#c2410c', '#1d6fd8', '#b4236b', '#8a6d00'];
const UNAVAILABLE = new Set(['TAKEN', 'SOLD', 'UNSOLD', 'BLOCKED', 'UNAVAILABLE']);
const ATTR_STROKE = { RESTRICTED_VIEW: '#d97706', WHEELCHAIR: '#1d6fd8' } as const;

export interface SeatMapViewProps {
  layout: Layout;
  /** seatKey -> index into `colors` (e.g. the price tier / seat type of that seat). */
  seatTypes?: Record<string, number>;
  /** seatKey -> status. TAKEN / SOLD / UNSOLD / BLOCKED / UNAVAILABLE render grey. */
  status?: Record<string, string>;
  colors?: string[];
  /** Ring around these seats. */
  selected?: Set<string>;
  /** Hatched (striped) seats, e.g. held in a cart. */
  held?: Set<string>;
  onToggle?: (seatKey: string) => void;
  onSectionClick?: (sectionKey: string) => void;
  onRowClick?: (sectionKey: string, rowLabel: string) => void;
  /** Rubber-band selection (mouse / pen drag across empty space or seats). `add` is true with Shift/Ctrl/Cmd held. */
  onSelectMany?: (seatKeys: string[], add: boolean) => void;
  /** Draw row labels next to the first seat of each row. Default: when onRowClick is given. */
  showRowLabels?: boolean;
  /** Outline restricted-view / wheelchair seats. Default true. */
  showAttrs?: boolean;
  /** Seat tooltips use labelMy when 'my'. */
  lang?: 'en' | 'my';
  ariaLabel?: string;
  /** Stage text when the layout's stage has no label. */
  stageLabel?: string;
}

/** SVG renderer for a seat-map layout. Shared by the admin editor and the organizer seats tab. */
export function SeatMapView({
  layout,
  seatTypes,
  status,
  colors = DEFAULT_SEAT_COLORS,
  selected,
  held,
  onToggle,
  onSectionClick,
  onRowClick,
  onSelectMany,
  showRowLabels,
  showAttrs = true,
  lang = 'en',
  ariaLabel,
  stageLabel,
}: SeatMapViewProps) {
  const pid = useId().replace(/:/g, '');
  const seats = useMemo(() => expandSeats(layout), [layout]);
  const rowLabels = useMemo(() => {
    const seen = new Map<string, { sectionKey: string; rowLabel: string; x: number; y: number }>();
    for (const s of seats) {
      const k = `${s.sectionKey}:${s.rowLabel}`;
      if (!seen.has(k)) seen.set(k, { sectionKey: s.sectionKey, rowLabel: s.rowLabel, x: s.x, y: s.y });
    }
    return [...seen.values()];
  }, [seats]);
  const rowSpans = useMemo(() => {
    const m = new Map<string, { sectionKey: string; rowLabel: string; x1: number; x2: number; y1: number; y2: number }>();
    for (const s of seats) {
      const k = `${s.sectionKey}:${s.rowLabel}`;
      const r = m.get(k);
      if (!r) m.set(k, { sectionKey: s.sectionKey, rowLabel: s.rowLabel, x1: s.x, x2: s.x, y1: s.y, y2: s.y });
      else {
        r.x1 = Math.min(r.x1, s.x); r.x2 = Math.max(r.x2, s.x); r.y1 = Math.min(r.y1, s.y); r.y2 = Math.max(r.y2, s.y);
      }
    }
    return [...m.values()];
  }, [seats]);
  const withRows = showRowLabels ?? !!onRowClick;
  const hatch = `hatch-${pid}`;

  const svgRef = useRef<SVGSVGElement>(null);
  const [band, setBand] = useState<{ x1: number; y1: number; x2: number; y2: number } | null>(null);
  const suppressClick = useRef(false);
  const onSelectManyRef = useRef(onSelectMany);
  onSelectManyRef.current = onSelectMany;
  const seatsRef = useRef(seats);
  seatsRef.current = seats;
  const dragCleanup = useRef<(() => void) | null>(null);
  useEffect(() => () => dragCleanup.current?.(), []);

  const toLocal = (cx: number, cy: number) => {
    const svg = svgRef.current;
    const m = svg?.getScreenCTM();
    if (!svg || !m) return { x: 0, y: 0 };
    const pt = svg.createSVGPoint();
    pt.x = cx;
    pt.y = cy;
    const r = pt.matrixTransform(m.inverse());
    return { x: r.x, y: r.y };
  };

  const startDrag = (e: React.PointerEvent<SVGSVGElement>) => {
    if (!onSelectMany || e.button !== 0 || e.pointerType === 'touch') return;
    const start = { cx: e.clientX, cy: e.clientY, ...toLocal(e.clientX, e.clientY), add: e.shiftKey || e.ctrlKey || e.metaKey };
    let moved = false;
    const move = (ev: PointerEvent) => {
      if (!moved && Math.hypot(ev.clientX - start.cx, ev.clientY - start.cy) < 6) return;
      moved = true;
      const p = toLocal(ev.clientX, ev.clientY);
      setBand({ x1: start.x, y1: start.y, x2: p.x, y2: p.y });
    };
    const up = (ev: PointerEvent) => {
      cleanup();
      setBand(null);
      if (!moved) return;
      const p = toLocal(ev.clientX, ev.clientY);
      const [xa, xb] = [Math.min(start.x, p.x), Math.max(start.x, p.x)];
      const [ya, yb] = [Math.min(start.y, p.y), Math.max(start.y, p.y)];
      const keys = seatsRef.current.filter((s) => s.x >= xa && s.x <= xb && s.y >= ya && s.y <= yb).map((s) => s.seatKey);
      suppressClick.current = true;
      setTimeout(() => (suppressClick.current = false), 60);
      onSelectManyRef.current?.(keys, start.add);
    };
    const cleanup = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      dragCleanup.current = null;
    };
    const cancel = () => {
      cleanup();
      setBand(null);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    dragCleanup.current = cleanup;
  };

  return (
    <svg
      ref={svgRef}
      onPointerDown={startDrag}
      onClickCapture={(e) => {
        if (suppressClick.current) e.stopPropagation();
      }}
      viewBox={`0 0 ${layout.width} ${layout.height}`}
      role="img"
      aria-label={ariaLabel}
      style={{ width: '100%', height: 'auto', userSelect: 'none', background: 'var(--surface, #fff)', border: '1px solid var(--border, #ddd)', borderRadius: 8 }}
    >
      <defs>
        <pattern id={hatch} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <rect width="6" height="6" fill="#fff" />
          <rect width="3" height="6" fill="#444" />
        </pattern>
      </defs>
      {layout.stage && (
        <g>
          <rect x={layout.stage.x} y={layout.stage.y} width={layout.stage.w} height={layout.stage.h} rx={6} fill="#cfcbe0" stroke="#8b86a3" />
          <text x={layout.stage.x + layout.stage.w / 2} y={layout.stage.y + layout.stage.h / 2} textAnchor="middle" dominantBaseline="middle" fontSize={16} fill="#3a3550">
            {layout.stage.label ?? stageLabel ?? ''}
          </text>
        </g>
      )}
      {/* Under the section titles and row labels, so those stay clickable where they overlap a row */}
      {onRowClick &&
        rowSpans.map((r) => (
          <rect
            key={`hit-${r.sectionKey}:${r.rowLabel}`}
            x={r.x1 - 28}
            y={r.y1 - SEAT_RADIUS - 2}
            width={r.x2 - r.x1 + 28 + SEAT_RADIUS + 2}
            height={r.y2 - r.y1 + 2 * SEAT_RADIUS + 4}
            fill="transparent"
            style={{ cursor: 'pointer' }}
            onClick={() => onRowClick(r.sectionKey, r.rowLabel)}
          />
        ))}
      {layout.sections.map((sec) => (
        <g key={sec.key}>
          {sec.kind === 'STANDING' && (
            <rect
              x={sec.x}
              y={sec.y}
              width={sec.w ?? 200}
              height={sec.h ?? 100}
              transform={sec.rotation ? `rotate(${sec.rotation} ${sec.x} ${sec.y})` : undefined}
              fill="#e8e4f5"
              stroke="#8b86a3"
              strokeDasharray="6 4"
              style={onSectionClick ? { cursor: 'pointer' } : undefined}
              onClick={onSectionClick ? () => onSectionClick(sec.key) : undefined}
            />
          )}
          <text
            x={sec.x}
            y={sec.kind === 'STANDING' ? sec.y + (sec.h ?? 100) / 2 : sec.y - 14}
            dx={sec.kind === 'STANDING' ? (sec.w ?? 200) / 2 : 0}
            textAnchor={sec.kind === 'STANDING' ? 'middle' : 'start'}
            fontSize={14}
            fontWeight={600}
            fill="#3a3550"
            style={onSectionClick ? { cursor: 'pointer' } : undefined}
            onClick={onSectionClick ? () => onSectionClick(sec.key) : undefined}
          >
            {sec.name}
            {sec.kind === 'STANDING' && sec.capacity ? ` (${sec.capacity})` : ''}
          </text>
        </g>
      ))}
      {withRows &&
        rowLabels.map((r) => (
          <text
            key={`${r.sectionKey}:${r.rowLabel}`}
            x={r.x - 16}
            y={r.y}
            textAnchor="end"
            dominantBaseline="middle"
            fontSize={10}
            fill="#6b6780"
            style={onRowClick ? { cursor: 'pointer' } : undefined}
            onClick={onRowClick ? () => onRowClick(r.sectionKey, r.rowLabel) : undefined}
          >
            {r.rowLabel}
          </text>
        ))}
      {seats.map((s) => {
        const st = status?.[s.seatKey];
        const unavailable = st != null && UNAVAILABLE.has(st.toUpperCase());
        const typeIdx = seatTypes?.[s.seatKey];
        const fill = unavailable ? '#c9c7d1' : typeIdx != null ? colors[typeIdx % colors.length] : seatTypes ? '#e5e3ee' : colors[0];
        const restricted = showAttrs && s.attrs.includes('RESTRICTED_VIEW');
        const wheel = showAttrs && s.attrs.includes('WHEELCHAIR');
        const attr = restricted ? 'RESTRICTED_VIEW' : wheel ? 'WHEELCHAIR' : undefined;
        const isSel = selected?.has(s.seatKey);
        return (
          <g key={s.seatKey} onClick={onToggle ? () => onToggle(s.seatKey) : undefined} style={onToggle ? { cursor: 'pointer' } : undefined}>
            <title>{lang === 'my' && s.labelMy ? s.labelMy : s.label}</title>
            {isSel && <circle cx={s.x} cy={s.y} r={SEAT_RADIUS + 4} fill="none" stroke="#111" strokeWidth={2} />}
            {restricted && wheel && <circle cx={s.x} cy={s.y} r={SEAT_RADIUS + 2} fill="none" stroke={ATTR_STROKE.WHEELCHAIR} strokeWidth={2} />}
            <circle cx={s.x} cy={s.y} r={SEAT_RADIUS} fill={fill} stroke={attr ? ATTR_STROKE[attr] : 'none'} strokeWidth={attr ? 3 : 0} />
            {held?.has(s.seatKey) && <circle cx={s.x} cy={s.y} r={SEAT_RADIUS} fill={`url(#${hatch})`} stroke="#444" strokeWidth={1} />}
          </g>
        );
      })}
      {band && (
        <rect
          x={Math.min(band.x1, band.x2)}
          y={Math.min(band.y1, band.y2)}
          width={Math.abs(band.x2 - band.x1)}
          height={Math.abs(band.y2 - band.y1)}
          fill="rgba(108,43,217,0.12)"
          stroke="#6c2bd9"
          strokeDasharray="5 3"
          pointerEvents="none"
        />
      )}
    </svg>
  );
}
