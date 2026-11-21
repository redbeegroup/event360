import Link from 'next/link';
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getEvent, getOrganizer, getSeats } from '../../../lib/api';
import { SITE_URL, ticketsUrl } from '../../../lib/config';
import { dict, fmtDayLong, fmtMmk, fmtTime, href, isLang, pick, type Lang } from '../../../lib/i18n';
import { TicketCard, place } from '../../../components/Cards';
import { SeatMapStatic } from '../../../components/SeatMapStatic';

type P = { params: Promise<{ lang: string; slug: string }> };

const Icon = ({ d }: { d: string }) => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d={d} />
  </svg>
);
const ICON = {
  cal: 'M7 3v3M17 3v3M4 9h16M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z',
  pin: 'M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11zM12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
  org: 'M4 20V9l8-5 8 5v11M9 20v-6h6v6',
};

export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang, slug } = await params;
  const e = await getEvent(slug);
  if (!e) return {};
  const l: Lang = isLang(lang) ? lang : 'en';
  const title = pick(l, e.title, e.titleMy);
  const description = pick(l, e.summary, e.summaryMy) || `${fmtDayLong(e.startsAt, l)} · ${place(e, l)}`;
  return {
    title,
    description,
    alternates: { canonical: href(l, `/e/${e.slug}`), languages: { en: `/e/${e.slug}`, my: `/my/e/${e.slug}` } },
    openGraph: { title, description, type: 'website', url: href(l, `/e/${e.slug}`), images: e.coverImageUrl ? [{ url: e.coverImageUrl, width: 1200, height: 675 }] : undefined },
    twitter: { card: e.coverImageUrl ? 'summary_large_image' : 'summary', title, description },
  };
}

export default async function EventPage({ params }: P) {
  const { lang: l, slug } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  const t = dict(lang);
  const e = await getEvent(slug);
  if (!e) notFound();
  const more = (await getOrganizer(e.organization.slug).catch(() => null))?.events.filter((x) => x.id !== e.id).slice(0, 3) ?? [];

  const seatMap = e.seating ? await getSeats(e.slug) : null;

  const ended = new Date(e.endsAt) < new Date();
  const cancelled = e.status === 'CANCELLED';
  const canBuy = !ended && !cancelled && !e.soldOut;
  const title = pick(lang, e.title, e.titleMy);
  const venueName = e.venue ? pick(lang, e.venue.name, e.venue.nameMy) : null;
  const facts: [string, string | null | undefined][] = [
    ['', e.ageMin ? t.ageMin(e.ageMin) : null],
    [t.dressCode, pick(lang, e.dressCode, e.dressCodeMy)],
    [t.languages, pick(lang, e.languages, e.languagesMy)],
    [t.parking, pick(lang, e.parking, e.parkingMy)],
    [t.accessibility, pick(lang, e.accessibility, e.accessibilityMy)],
    [t.whatToBring, pick(lang, e.whatToBring, e.whatToBringMy)],
  ];
  const shownFacts = facts.filter(([, v]) => v);
  const mapUrl = e.venue?.mapUrl || (e.venue?.latitude != null && e.venue?.longitude != null ? `https://www.google.com/maps/search/?api=1&query=${e.venue.latitude},${e.venue.longitude}` : e.venue ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${e.venue.name}, ${e.venue.city}`)}` : null);

  // schema.org Event for search engines
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Event',
    name: e.title,
    description: e.summary ?? undefined,
    startDate: e.startsAt,
    endDate: e.endsAt,
    eventStatus: cancelled ? 'https://schema.org/EventCancelled' : 'https://schema.org/EventScheduled',
    eventAttendanceMode:
      e.format === 'ONLINE' ? 'https://schema.org/OnlineEventAttendanceMode' : e.format === 'HYBRID' ? 'https://schema.org/MixedEventAttendanceMode' : 'https://schema.org/OfflineEventAttendanceMode',
    image: e.coverImageUrl ? [e.coverImageUrl] : undefined,
    location: e.venue
      ? { '@type': 'Place', name: e.venue.name, address: { '@type': 'PostalAddress', streetAddress: e.venue.address ?? undefined, addressLocality: e.venue.city, addressCountry: 'MM' } }
      : { '@type': 'VirtualLocation', url: `${SITE_URL}/e/${e.slug}` },
    organizer: { '@type': 'Organization', name: e.organization.name, url: `${SITE_URL}/o/${e.organization.slug}` },
    offers: e.ticketTypes.map((tt) => ({
      '@type': 'Offer',
      name: tt.name,
      price: tt.priceMmk,
      priceCurrency: 'MMK',
      availability: tt.remaining > 0 ? 'https://schema.org/InStock' : 'https://schema.org/SoldOut',
      url: `${SITE_URL}/e/${e.slug}`,
    })),
  };

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c') }} />
      <section className="event-hero">
        {e.coverImageUrl && <img className="event-cover" src={e.coverImageUrl} alt="" />}
        <div className="wrap event-title">
          <p className="crumbs">
            <Link href={href(lang, '/events')}>{t.eventsTitle}</Link> / {pick(lang, e.category.nameEn, e.category.nameMy)}
          </p>
          <h1 style={{ fontSize: 'clamp(2rem, 5vw, 3.4rem)', maxWidth: '22ch' }}>{title}</h1>
          {pick(lang, e.summary, e.summaryMy) && <p>{pick(lang, e.summary, e.summaryMy)}</p>}
        </div>
      </section>

      <div className="wrap event-layout">
        <div className="event-main">
          {(cancelled || ended) && <p className="notice">{cancelled ? t.cancelled : t.ended}</p>}

          {pick(lang, e.description, e.descriptionMy) && (
            <section aria-labelledby="about">
              <h2 id="about">{t.about}</h2>
              <p className="prose">{pick(lang, e.description, e.descriptionMy)}</p>
            </section>
          )}

          {seatMap && (
            <section aria-labelledby="seating">
              <h2 id="seating">{t.seatMapTitle}</h2>
              <p><span className="badge">{t.reservedSeating}</span></p>
              <SeatMapStatic seats={seatMap} lang={lang} t={t} />
            </section>
          )}

          {e.sessions.length > 0 && (
            <section aria-labelledby="schedule">
              <h2 id="schedule">{t.schedule}</h2>
              <ol className="timeline">
                {e.sessions.map((s) => (
                  <li key={s.id}>
                    <time dateTime={s.startsAt}>{fmtTime(s.startsAt, lang)}</time>
                    <div>
                      <strong>{pick(lang, s.title, s.titleMy)}</strong>
                      {s.location && <div className="muted small">{s.location}</div>}
                    </div>
                  </li>
                ))}
              </ol>
            </section>
          )}

          {e.performers.length > 0 && (
            <section aria-labelledby="lineup">
              <h2 id="lineup">{t.lineup}</h2>
              <div className="lineup">
                {e.performers.map((p) => (
                  <div className="person" key={p.id}>
                    {p.photoUrl ? <img src={p.photoUrl} alt="" loading="lazy" /> : <span className="ph" aria-hidden="true" />}
                    <div>
                      <strong>{pick(lang, p.name, p.nameMy)}</strong>
                      {p.role && <div className="muted small">{pick(lang, p.role, p.roleMy)}</div>}
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {e.media.length > 0 && (
            <section aria-labelledby="photos">
              <h2 id="photos">{t.photos}</h2>
              <div className="gallery">
                {e.media.map((m) => (
                  <figure key={m.id}>
                    <img src={m.url} alt={pick(lang, m.caption, m.captionMy)} loading="lazy" />
                    {m.caption && <figcaption>{pick(lang, m.caption, m.captionMy)}</figcaption>}
                  </figure>
                ))}
              </div>
            </section>
          )}

          {shownFacts.length > 0 && (
            <section aria-labelledby="good">
              <h2 id="good">{t.goodToKnow}</h2>
              <dl className="facts">
                {shownFacts.map(([k, v]) => (
                  <div key={k + v}>
                    {k && <dt>{k}</dt>}
                    <dd>{v}</dd>
                  </div>
                ))}
              </dl>
            </section>
          )}

          {e.venue && (
            <section aria-labelledby="directions">
              <h2 id="directions">{t.directions}</h2>
              <p>
                <strong>{venueName}</strong>
                {e.venue.address && <><br />{e.venue.address}</>}
                <br />
                {e.venue.city}
              </p>
              {pick(lang, e.venue.directions, e.venue.directionsMy) && <p className="prose muted" style={{ marginTop: 8 }}>{pick(lang, e.venue.directions, e.venue.directionsMy)}</p>}
              {mapUrl && <a className="btn btn-ghost" style={{ marginTop: 14 }} href={mapUrl} target="_blank" rel="noopener noreferrer">{t.openMap}</a>}
            </section>
          )}

          {e.faqs.length > 0 && (
            <section aria-labelledby="faq">
              <h2 id="faq">{t.faq}</h2>
              {e.faqs.map((f) => (
                <details className="faq" key={f.id}>
                  <summary>{pick(lang, f.question, f.questionMy)}</summary>
                  <p>{pick(lang, f.answer, f.answerMy)}</p>
                </details>
              ))}
            </section>
          )}

          {pick(lang, e.refundPolicy, e.refundPolicyMy) && (
            <section aria-labelledby="refund">
              <h2 id="refund">{t.refundPolicy}</h2>
              <p className="prose">{pick(lang, e.refundPolicy, e.refundPolicyMy)}</p>
            </section>
          )}

          {more.length > 0 && (
            <section aria-labelledby="more">
              <h2 id="more">{t.moreFrom}</h2>
              <div className="tickets">{more.map((x) => <TicketCard key={x.id} e={x} lang={lang} />)}</div>
            </section>
          )}
        </div>

        <aside className="aside" aria-label={t.tickets}>
          <div className="pass">
            <div className="pass-top">
              <div className="pass-row">
                <Icon d={ICON.cal} />
                <div>
                  <div className="label">{t.when}</div>
                  <div>{fmtDayLong(e.startsAt, lang)}</div>
                  <div className="muted">{fmtTime(e.startsAt, lang)} – {fmtTime(e.endsAt, lang)}</div>
                </div>
              </div>
              <div className="pass-row">
                <Icon d={ICON.pin} />
                <div>
                  <div className="label">{t.where}</div>
                  <div>{place(e, lang)}</div>
                </div>
              </div>
              <div className="pass-row">
                <Icon d={ICON.org} />
                <div>
                  <div className="label">{t.organizer}</div>
                  <Link href={href(lang, `/o/${e.organization.slug}`)}>{e.organization.name}</Link>
                  {e.organization.kycStatus === 'APPROVED' && <div className="badge">{t.verified}</div>}
                </div>
              </div>
            </div>
            <div className="ticket-tear" aria-hidden="true" />
            <div className="pass-bottom">
              <h2 style={{ fontSize: '1.1rem' }}>{t.tickets}</h2>
              {seatMap && <div className="badge">{t.reservedSeating}</div>}
              {e.ticketTypes.map((tt) => (
                <div className="tt" key={tt.id}>
                  <div>
                    <div>{pick(lang, tt.name, tt.nameMy)}</div>
                    <div className="left">{tt.remaining > 0 ? t.left(tt.remaining) : t.soldOut}</div>
                  </div>
                  <strong style={{ color: tt.priceMmk === 0 ? 'var(--jade)' : undefined }}>{tt.priceMmk === 0 ? t.free : fmtMmk(tt.priceMmk, lang)}</strong>
                </div>
              ))}
              {canBuy && (
                <a className="btn btn-gold" href={ticketsUrl(e.slug)}>{e.isFree ? t.registerFree : t.getTickets}</a>
              )}
              <p className="muted small">{t.ticketsInApp}</p>
            </div>
          </div>
        </aside>
      </div>
    </>
  );
}
