'use client';

import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { expandSeats, type Layout } from '../lib/seat-layout';

export const SEAT_RADIUS = 9;
const MAX_ZOOM = 8;
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
  /** Rubber-band selection result. `add` is true with Shift/Ctrl/Cmd held. Needs `boxSelect` other than 'off'. */
  onSelectMany?: (seatKeys: string[], add: boolean) => void;
  /** Zoom (+ / - / Fit, wheel, pinch) and drag-to-pan. Default true; false draws the plain static map. */
  zoomable?: boolean;
  /** When a drag draws a selection box: 'shift' = with Shift held, 'always' = every drag (touch toggle), 'off' = never (drag pans). */
  boxSelect?: 'shift' | 'always' | 'off';
  /** Viewport height in px (default: follows the map's aspect ratio). */
  height?: number;
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
  zoomable = true,
  boxSelect = 'off',
  height,
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

  // Zoom state: k = scale (1 = Fit), (x, y) = top-left of the visible window in layout coordinates.
  const W = layout.width;
  const H = layout.height;
  const [view, setView] = useState({ k: 1, x: 0, y: 0 });
  const viewRef = useRef(view);
  viewRef.current = view;
  const dimsRef = useRef({ W, H });
  dimsRef.current = { W, H };
  const clampView = (k: number, x: number, y: number) => {
    const { W: w0, H: h0 } = dimsRef.current;
    const kk = Math.min(MAX_ZOOM, Math.max(1, k));
    return { k: kk, x: Math.min(Math.max(0, x), w0 - w0 / kk), y: Math.min(Math.max(0, y), h0 - h0 / kk) };
  };
  const setViewClamped = (k: number, x: number, y: number) => setView(clampView(k, x, y));
  const eff = zoomable ? clampView(view.k, view.x, view.y) : { k: 1, x: 0, y: 0 };
  const vbW = W / eff.k;
  const vbH = H / eff.k;

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
  /** Screen pixels per layout unit under the current viewBox. */
  const pxPerUnit = () => svgRef.current?.getScreenCTM()?.a || 1;

  /** Zoom by `factor`, keeping the layout point under screen (cx, cy) fixed. */
  const zoomAt = (factor: number, cx?: number, cy?: number) => {
    const cur = clampView(viewRef.current.k, viewRef.current.x, viewRef.current.y);
    const nk = Math.min(MAX_ZOOM, Math.max(1, cur.k * factor));
    if (nk === cur.k) return;
    const p = cx == null || cy == null ? { x: cur.x + W / cur.k / 2, y: cur.y + H / cur.k / 2 } : toLocal(cx, cy);
    const fx = (p.x - cur.x) / (W / cur.k);
    const fy = (p.y - cur.y) / (H / cur.k);
    setViewClamped(nk, p.x - fx * (W / nk), p.y - fy * (H / nk));
  };
  const zoomAtRef = useRef(zoomAt);
  zoomAtRef.current = zoomAt;

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg || !zoomable) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      zoomAtRef.current(Math.exp(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.0015)), e.clientX, e.clientY);
    };
    svg.addEventListener('wheel', onWheel, { passive: false });
    return () => svg.removeEventListener('wheel', onWheel);
  }, [zoomable]);

  type Gesture =
    | { kind: 'none' }
    | { kind: 'pan'; cx: number; cy: number; vx: number; vy: number; moved: boolean }
    | { kind: 'box'; cx: number; cy: number; x: number; y: number; add: boolean; moved: boolean }
    | { kind: 'pinch'; dist: number; k: number };
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<Gesture>({ kind: 'none' });

  const pinchDist = () => {
    const [a, b] = [...pointers.current.values()];
    return { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2 };
  };

  const onPointerDown = (e: React.PointerEvent<SVGSVGElement>) => {
    if (e.pointerType !== 'touch' && e.button !== 0) return;
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (zoomable && pointers.current.size === 2) {
      setBand(null);
      gesture.current = { kind: 'pinch', dist: pinchDist().d, k: clampView(viewRef.current.k, 0, 0).k };
      suppressClick.current = true;
      for (const id of pointers.current.keys()) {
        try { e.currentTarget.setPointerCapture(id); } catch { /* ignore */ }
      }
      return;
    }
    if (pointers.current.size > 1) return;
    const boxOk = !!onSelectMany && (boxSelect === 'always' || (boxSelect === 'shift' && e.shiftKey));
    if (boxOk) {
      const p = toLocal(e.clientX, e.clientY);
      gesture.current = { kind: 'box', cx: e.clientX, cy: e.clientY, x: p.x, y: p.y, add: e.shiftKey || e.ctrlKey || e.metaKey, moved: false };
    } else if (zoomable) {
      const cur = clampView(viewRef.current.k, viewRef.current.x, viewRef.current.y);
      gesture.current = { kind: 'pan', cx: e.clientX, cy: e.clientY, vx: cur.x, vy: cur.y, moved: false };
    }
  };

  const onPointerMove = (e: React.PointerEvent<SVGSVGElement>) => {
    // A mouse button released outside the map never reaches us: drop the stuck gesture
    if (e.pointerType === 'mouse' && e.buttons === 0 && gesture.current.kind !== 'none') {
      gesture.current = { kind: 'none' };
      pointers.current.clear();
      setBand(null);
      return;
    }
    if (pointers.current.has(e.pointerId)) pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const g = gesture.current;
    if (g.kind === 'pinch') {
      if (pointers.current.size < 2) return;
      const { d, mx, my } = pinchDist();
      const cur = clampView(viewRef.current.k, viewRef.current.x, viewRef.current.y);
      zoomAtRef.current((g.k * d) / g.dist / cur.k, mx, my);
      return;
    }
    if (g.kind === 'none') return;
    if (!g.moved) {
      if (Math.hypot(e.clientX - g.cx, e.clientY - g.cy) < 6) return;
      g.moved = true;
      try { e.currentTarget.setPointerCapture(e.pointerId); } catch { /* ignore */ }
    }
    if (g.kind === 'pan') {
      const ppu = pxPerUnit();
      setViewClamped(viewRef.current.k, g.vx - (e.clientX - g.cx) / ppu, g.vy - (e.clientY - g.cy) / ppu);
    } else {
      const p = toLocal(e.clientX, e.clientY);
      setBand({ x1: g.x, y1: g.y, x2: p.x, y2: p.y });
    }
  };

  const endPointer = (e: React.PointerEvent<SVGSVGElement>, cancelled: boolean) => {
    if (!pointers.current.has(e.pointerId)) return;
    pointers.current.delete(e.pointerId);
    const g = gesture.current;
    if (g.kind === 'pinch') {
      // Stay in 'pinch' until every finger is up, so the trailing lift cannot start a pan or a click.
      if (pointers.current.size === 0) {
        gesture.current = { kind: 'none' };
        setTimeout(() => (suppressClick.current = false), 60);
      }
      return;
    }
    gesture.current = { kind: 'none' };
    try { e.currentTarget.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    if (g.kind === 'none') return;
    setBand(null);
    if (!g.moved) return;
    suppressClick.current = true;
    setTimeout(() => (suppressClick.current = false), 60);
    if (g.kind === 'box' && !cancelled) {
      const p = toLocal(e.clientX, e.clientY);
      const [xa, xb] = [Math.min(g.x, p.x), Math.max(g.x, p.x)];
      const [ya, yb] = [Math.min(g.y, p.y), Math.max(g.y, p.y)];
      const keys = seatsRef.current.filter((s) => s.x >= xa && s.x <= xb && s.y >= ya && s.y <= yb).map((s) => s.seatKey);
      onSelectManyRef.current?.(keys, g.add);
    }
  };

  const T = lang === 'my'
    ? { in: 'ချဲ့ရန်', out: 'ချုံ့ရန်', fit: 'အားလုံးကြည့်ရန်', fitText: 'အားလုံး' }
    : { in: 'Zoom in', out: 'Zoom out', fit: 'Fit whole map', fitText: 'Fit' };
  const btn: React.CSSProperties = { background: 'var(--surface, #fff)', minWidth: 32, height: 32, padding: '0 8px', lineHeight: 1, fontSize: 16, fontWeight: 600, cursor: 'pointer' };

  const svg = (
    <svg
      ref={svgRef}
      {...(zoomable || (onSelectMany && boxSelect !== 'off')
        ? { onPointerDown, onPointerMove, onPointerUp: (e: React.PointerEvent<SVGSVGElement>) => endPointer(e, false), onPointerCancel: (e: React.PointerEvent<SVGSVGElement>) => endPointer(e, true) }
        : {})}
      onClickCapture={(e) => {
        if (suppressClick.current) e.stopPropagation();
      }}
      viewBox={`${eff.x} ${eff.y} ${vbW} ${vbH}`}
      role="img"
      aria-label={ariaLabel}
      style={{ width: '100%', height: height ?? 'auto', userSelect: 'none', ...(zoomable ? { touchAction: eff.k === 1 && boxSelect !== 'always' ? 'pan-y' : 'none', cursor: eff.k > 1 ? 'grab' : undefined } : {}), background: 'var(--surface, #fff)', border: '1px solid var(--border, #ddd)', borderRadius: 8 }}
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

  if (!zoomable) return svg;
  return (
    <div style={{ position: 'relative' }}>
      {svg}
      <div role="group" style={{ position: 'absolute', top: 8, right: 8, display: 'flex', gap: 4 }}>
        <button type="button" className="secondary" style={btn} aria-label={T.in} title={T.in} disabled={eff.k >= MAX_ZOOM} onClick={() => zoomAt(1.6)}>+</button>
        <button type="button" className="secondary" style={btn} aria-label={T.out} title={T.out} disabled={eff.k <= 1} onClick={() => zoomAt(1 / 1.6)}>−</button>
        <button type="button" className="secondary" style={btn} aria-label={T.fit} title={T.fit} disabled={eff.k === 1} onClick={() => setView({ k: 1, x: 0, y: 0 })}>{T.fitText}</button>
      </div>
    </div>
  );
}
