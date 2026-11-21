import Link from 'next/link';
import { SeatMapView } from './SeatMapView';
import type { Layout } from '../lib/seat-layout';

/** Preview colours by seat status (index order matches STATUS_ORDER). */
const COLORS = ['#3fae6a', '#f2b84b', '#7a6cf0', '#9aa0a6', '#e5e3ee'];
const STATUS_ORDER = ['AVAILABLE', 'CHECKOUT_HOLD', 'GUEST_HOLD', 'SOLD', 'UNSOLD'] as const;

export interface SeatMapPreviewProps {
  layout: Layout;
  seats: { seatKey: string; status: string }[];
  href: string;
  lang: 'en' | 'my';
  title: string;
  labels: { available: string; checkout: string; guest: string; sold: string; unsold: string; open: string };
}

/** Read-only seat map coloured by status, with a legend of counts; the whole card links to the Seats tab. */
export function SeatMapPreview({ layout, seats, href, lang, title, labels }: SeatMapPreviewProps) {
  const seatTypes: Record<string, number> = {};
  const counts = [0, 0, 0, 0, 0];
  for (const s of seats) {
    const i = STATUS_ORDER.indexOf(s.status as (typeof STATUS_ORDER)[number]);
    if (i < 0) continue;
    seatTypes[s.seatKey] = i;
    counts[i]++;
  }
  const names = [labels.available, labels.checkout, labels.guest, labels.sold, labels.unsold];
  const n = new Intl.NumberFormat(lang === 'my' ? 'my-MM' : 'en-US');
  return (
    <Link href={href} className="card seat-preview" aria-label={`${title} — ${labels.open}`} style={{ display: 'flex', flexWrap: 'wrap', gap: 20, alignItems: 'center', color: 'inherit', textDecoration: 'none' }}>
      <div style={{ flex: '1 1 320px', maxWidth: 450, minWidth: 0 }}>
        <SeatMapView layout={layout} seatTypes={seatTypes} colors={COLORS} zoomable={false} showAttrs={false} lang={lang} ariaLabel={title} />
      </div>
      <div style={{ flex: '0 0 auto' }}>
        <h2 style={{ marginTop: 0 }}>{title}</h2>
        <ul style={{ listStyle: 'none', padding: 0, margin: '0 0 12px' }}>
          {names.map((nm, i) => (
            <li key={nm} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '3px 0' }}>
              <span aria-hidden style={{ width: 12, height: 12, borderRadius: '50%', background: COLORS[i], border: i === 4 ? '1px solid #b9b5c9' : 'none' }} />
              <span>{nm}</span>
              <strong style={{ marginLeft: 'auto', paddingLeft: 16 }}>{n.format(counts[i])}</strong>
            </li>
          ))}
        </ul>
        <span className="muted">{labels.open} →</span>
      </div>
    </Link>
  );
}
