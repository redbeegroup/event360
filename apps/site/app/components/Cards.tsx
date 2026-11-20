import Link from 'next/link';
import type { EventCard } from '../lib/api';
import { dayParts, dict, fmtDay, fmtMmk, fmtTime, href, pick, type Lang } from '../lib/i18n';

export function priceLabel(e: EventCard, lang: Lang) {
  const t = dict(lang);
  if (e.soldOut) return { text: t.soldOut, cls: 'out' };
  if (e.isFree) return { text: t.free, cls: 'free' };
  return { text: e.minPriceMmk != null ? t.from(fmtMmk(e.minPriceMmk, lang)) : '', cls: '' };
}

export function place(e: EventCard, lang: Lang) {
  const t = dict(lang);
  if (e.format === 'ONLINE') return t.online;
  const v = e.venue ? `${pick(lang, e.venue.name, e.venue.nameMy)}, ${e.venue.city}` : '';
  return e.format === 'HYBRID' ? `${v} · ${t.hybrid}` : v;
}

/** Grid card: cover, date tag, perforated tear, details. */
export function TicketCard({ e, lang }: { e: EventCard; lang: Lang }) {
  const { day, month } = dayParts(e.startsAt);
  const price = priceLabel(e, lang);
  return (
    <Link className="ticket" href={href(lang, `/e/${e.slug}`)}>
      <div className="ticket-cover">
        {e.coverImageUrl && <img src={e.coverImageUrl} alt="" loading="lazy" />}
        <span className="ticket-date" aria-hidden="true">
          <span className="d">{day}</span>
          <span className="m">{month}</span>
        </span>
      </div>
      <div className="ticket-tear" aria-hidden="true" />
      <div className="ticket-body">
        <h3>{pick(lang, e.title, e.titleMy)}</h3>
        <p className="ticket-meta">
          {fmtDay(e.startsAt, lang)}, {fmtTime(e.startsAt, lang)}
          <br />
          {place(e, lang)}
        </p>
        <p className={`ticket-price ${price.cls}`}>{price.text}</p>
      </div>
    </Link>
  );
}

/** Compact horizontal stub (hero list). */
export function TicketStub({ e, lang }: { e: EventCard; lang: Lang }) {
  const { day, month } = dayParts(e.startsAt);
  const price = priceLabel(e, lang);
  return (
    <Link className="stub" href={href(lang, `/e/${e.slug}`)}>
      <span className="stub-date" aria-hidden="true">
        <span className="d">{day}</span>
        <span className="m">{month}</span>
      </span>
      <span className="stub-body">
        <strong>{pick(lang, e.title, e.titleMy)}</strong>
        <span className="meta">{fmtTime(e.startsAt, lang)} · {place(e, lang)}</span>
        <span className="meta" style={{ color: price.cls === 'free' ? 'var(--jade)' : undefined, fontWeight: 600 }}>{price.text}</span>
      </span>
    </Link>
  );
}
