// Server-only static seat map: a plain SVG, no client JS. Server-side copy of the drawing in
// apps/web/app/components/SeatMapView.tsx (seat circles, stage, section titles), reduced to what a read-only overview needs.
// The layout maths it relies on (lib/seat-layout.ts) is a copy of the API's layout.ts and must stay in sync with it.
import { expandSeats } from '../lib/seat-layout';
import type { PublicSeats } from '../lib/api';
import { fmtMmk, pick, type Dict, type Lang } from '../lib/i18n';

const SEAT_RADIUS = 9;
const TYPE_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
/** Seats without a ticket type. */
const NO_TYPE = '#e5e3ee';
/** Taken (T), held for guests (G) or not for sale (U). */
const UNAVAILABLE = '#c9c7d1';
const isUnavailable = (c: string | undefined) => c === 'T' || c === 'G' || c === 'U';
/** Colours reach the page as inline SVG/CSS, so only accept plain hex values. */
const safeColor = (c: string) => (/^#[0-9a-fA-F]{3,8}$/.test(c) ? c : '#6c2bd9');

export function SeatMapStatic({ seats, lang, t }: { seats: PublicSeats; lang: Lang; t: Dict }) {
  const { layout, types } = seats;
  const list = expandSeats(layout);
  return (
    <div className="seatmap">
      <svg viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-label={t.seatMapAlt} style={{ width: '100%', height: 'auto' }}>
        {layout.stage && (
          <g>
            <rect x={layout.stage.x} y={layout.stage.y} width={layout.stage.w} height={layout.stage.h} rx={6} fill="#cfcbe0" stroke="#8b86a3" />
            <text x={layout.stage.x + layout.stage.w / 2} y={layout.stage.y + layout.stage.h / 2} textAnchor="middle" dominantBaseline="middle" fontSize={16} fill="#3a3550">
              {layout.stage.label ?? ''}
            </text>
          </g>
        )}
        {layout.sections.map((sec) => (
          <g key={sec.key}>
            {sec.kind === 'STANDING' && (
              <rect x={sec.x} y={sec.y} width={sec.w ?? 200} height={sec.h ?? 100} transform={sec.rotation ? `rotate(${sec.rotation} ${sec.x} ${sec.y})` : undefined} fill="#e8e4f5" stroke="#8b86a3" strokeDasharray="6 4" />
            )}
            <text
              x={sec.x + (sec.kind === 'STANDING' ? (sec.w ?? 200) / 2 : 0)}
              y={sec.kind === 'STANDING' ? sec.y + (sec.h ?? 100) / 2 : sec.y - 14}
              textAnchor={sec.kind === 'STANDING' ? 'middle' : 'start'}
              fontSize={14}
              fontWeight={600}
              fill="#3a3550"
            >
              {pick(lang, sec.name, sec.nameMy)}
              {sec.kind === 'STANDING' && sec.capacity ? ` (${sec.capacity})` : ''}
            </text>
          </g>
        ))}
        {list.map((s, i) => {
          const ti = TYPE_CHARS.indexOf(seats.seatTypes[i] ?? '-');
          const fill = isUnavailable(seats.status[i]) ? UNAVAILABLE : ti >= 0 && types[ti] ? safeColor(types[ti].color) : NO_TYPE;
          return <circle key={s.seatKey} cx={s.x} cy={s.y} r={SEAT_RADIUS} fill={fill} />;
        })}
      </svg>
      <ul className="seatmap-legend">
        {types.map((ty) => (
          <li key={ty.id}>
            <span className="swatch" style={{ background: safeColor(ty.color) }} aria-hidden="true" />
            <span>{pick(lang, ty.name, ty.nameMy)}</span>
            <strong>{ty.priceMmk === 0 ? t.free : fmtMmk(ty.priceMmk, lang)}</strong>
          </li>
        ))}
        <li>
          <span className="swatch" style={{ background: UNAVAILABLE }} aria-hidden="true" />
          <span>{t.seatUnavailable}</span>
        </li>
      </ul>
      <p className="muted small">{t.seatMapNote}</p>
    </div>
  );
}
