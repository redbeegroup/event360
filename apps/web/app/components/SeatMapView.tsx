'use client';

import { useId, useMemo } from 'react';
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
  /** Draw row labels next to the first seat of each row. Default: when onRowClick is given. */
  showRowLabels?: boolean;
  /** Outline restricted-view / wheelchair seats. Default true. */
  showAttrs?: boolean;
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
  showRowLabels,
  showAttrs = true,
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
  const withRows = showRowLabels ?? !!onRowClick;
  const hatch = `hatch-${pid}`;

  return (
    <svg
      viewBox={`0 0 ${layout.width} ${layout.height}`}
      role="img"
      aria-label="Seat map"
      style={{ width: '100%', height: 'auto', background: 'var(--surface, #fff)', border: '1px solid var(--border, #ddd)', borderRadius: 8 }}
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
            {layout.stage.label ?? 'Stage'}
          </text>
        </g>
      )}
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
        const attr = showAttrs ? (s.attrs[0] as keyof typeof ATTR_STROKE | undefined) : undefined;
        const isSel = selected?.has(s.seatKey);
        return (
          <g key={s.seatKey} onClick={onToggle ? () => onToggle(s.seatKey) : undefined} style={onToggle ? { cursor: 'pointer' } : undefined}>
            <title>{s.label}</title>
            {isSel && <circle cx={s.x} cy={s.y} r={SEAT_RADIUS + 4} fill="none" stroke="#111" strokeWidth={2} />}
            <circle cx={s.x} cy={s.y} r={SEAT_RADIUS} fill={fill} stroke={attr ? ATTR_STROKE[attr] : 'none'} strokeWidth={attr ? 3 : 0} />
            {held?.has(s.seatKey) && <circle cx={s.x} cy={s.y} r={SEAT_RADIUS} fill={`url(#${hatch})`} stroke="#444" strokeWidth={1} />}
          </g>
        );
      })}
    </svg>
  );
}
