import Link from 'next/link';
import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getEvent, getOrganizer, getSeats } from '../../../lib/api';
import { SITE_URL, ticketsUrl } from '../../../lib/config';
import { dict, fmtDayLong, fmtMmk, fmtPct, fmtTime, fmtDay, href, isLang, pick, type Lang } from '../../../lib/i18n';
import { TicketCard, place } from '../../../components/Cards';
import { SeatMapStatic } from '../../../components/SeatMapStatic';

type P = { params: Promise<{ lang: string; slug: string }> };

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

  const tiers = e.ticketTypes.some((tt) => tt.priceMmk > 0) ? (e.groupDiscounts ?? []) : [];
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

  const mixedFree = !e.isFree && e.minPriceMmk === 0;
  const minPrice = e.isFree || mixedFree ? t.free : e.minPriceMmk != null ? fmtMmk(e.minPriceMmk, lang) : null;
  const lowestPaid = mixedFree ? Math.min(...e.ticketTypes.filter((tt) => tt.priceMmk > 0).map((tt) => tt.priceMmk)) : null;
  // Seated events: dot colours match the seat-map legend (the API's resolved colour, else the type's own, else the same palette by price order).
  const PALETTE = ['#f2b632', '#1f8a70', '#3b6fd8', '#c2410c', '#7c3aed', '#0891b2', '#be185d', '#4d7c0f'];
  const hex = (c: string | null | undefined) => (c && /^#[0-9a-fA-F]{3,8}$/.test(c) ? c : null);
  const byPrice = [...e.ticketTypes].sort((a, b) => a.priceMmk - b.priceMmk || a.id.localeCompare(b.id));
  const dot = (id: string) => {
    if (!seatMap) return null;
    const own = seatMap.types.find((x) => x.id === id)?.color;
    return hex(own) ?? hex(e.ticketTypes.find((x) => x.id === id)?.color) ?? PALETTE[Math.max(0, byPrice.findIndex((x) => x.id === id)) % PALETTE.length];
  };
  const venueLine = e.venue ? e.venue.city : null;

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c') }} />
      <div className="wrap event-page">
        <p className="crumbs">
          <Link href={href(lang, '/events')}>{t.eventsTitle}</Link> / {pick(lang, e.category.nameEn, e.category.nameMy)}
        </p>
        {e.coverImageUrl && <img className="event-cover" src={e.coverImageUrl} alt="" />}

        <div className="event-layout">
          <header className="event-head">
            <div className="badges">
              {seatMap && <span className="badge badge-gold">{t.reservedSeating}</span>}
              <span className="badge">{pick(lang, e.category.nameEn, e.category.nameMy)}</span>
            </div>
            <h1 className="event-h1">{title}</h1>
            <p className="event-by">
              {t.by} <Link href={href(lang, `/o/${e.organization.slug}`)}>{e.organization.name}</Link>
              {e.organization.kycStatus === 'APPROVED' && <span className="badge badge-ok">{t.verified}</span>}
            </p>
            {pick(lang, e.summary, e.summaryMy) && <p className="event-summary">{pick(lang, e.summary, e.summaryMy)}</p>}
          </header>

          <div className="event-aside-cell">
            <aside className="ticket-box" aria-label={t.tickets}>
              <h2 className="visually-hidden">{t.tickets}</h2>
              {minPrice && (
                <div className="from">
                  <span>{t.ticketsFrom}</span>
                  <span className={`price-big${e.isFree || mixedFree ? ' free' : ''}`}>{minPrice}</span>
                  {lowestPaid != null && Number.isFinite(lowestPaid) && <span className="paid-from">{t.paidFrom(fmtMmk(lowestPaid, lang))}</span>}
                </div>
              )}
              <div className="tt-list">
                {e.ticketTypes.map((tt) => (
                  <div className="tt" key={tt.id}>
                    {dot(tt.id) && <span className="tt-dot" style={{ background: dot(tt.id)! }} aria-hidden="true" />}
                    <div className="tt-main">
                      <div className="name">{pick(lang, tt.name, tt.nameMy)}</div>
                      <div className="left">{tt.remaining > 0 ? t.left(tt.remaining) : t.soldOut}</div>
                      {tt.nextPrice && tt.priceMmk > 0 && (
                        <div className="left">{t.priceRises(fmtMmk(tt.nextPrice.priceMmk, lang), `${fmtDay(tt.nextPrice.startsAt, lang)}, ${fmtTime(tt.nextPrice.startsAt, lang)}`)}</div>
                      )}
                    </div>
                    <span className={`price${tt.priceMmk === 0 ? ' free' : ''}`}>{tt.priceMmk === 0 ? t.free : fmtMmk(tt.priceMmk, lang)}</span>
                  </div>
                ))}
              </div>
              {tiers.length > 0 && (
                <div className="group-tiers">
                  <div className="label">{t.groupTitle}</div>
                  {tiers.map((g) => <div className="left" key={g.minQuantity}>{t.groupTier(g.minQuantity, fmtPct(g.percentBp))}</div>)}
                </div>
              )}
              {canBuy && (
                <a className="btn btn-gold" href={ticketsUrl(e.slug)}>{e.isFree ? t.registerFree : t.getTickets}</a>
              )}
              <p className="note">{t.ticketsInApp}</p>
            </aside>
          </div>

          <div className="event-body">
            <div className="info-cards">
              <div className="info-card">
                <span className="label">{t.when}</span>
                <span className="strong">{fmtDayLong(e.startsAt, lang)}</span>
                <span className="sub">{fmtTime(e.startsAt, lang)} – {fmtTime(e.endsAt, lang)}</span>
              </div>
              <div className="info-card">
                <span className="label">{t.where}</span>
                <span className="strong">{e.format === 'ONLINE' ? t.online : venueName ?? place(e, lang)}</span>
                {e.format !== 'ONLINE' && venueLine && <span className="sub">{venueLine}{e.format === 'HYBRID' ? ` · ${t.hybrid}` : ''}</span>}
              </div>
            </div>
        {(cancelled || ended) && <p className="notice">{cancelled ? t.cancelled : t.ended}</p>}

        {pick(lang, e.description, e.descriptionMy) && (
          <section aria-labelledby="about">
            <h2 id="about">{t.overview}</h2>
            <p className="prose">{pick(lang, e.description, e.descriptionMy)}</p>
          </section>
        )}

        {seatMap && (
          <section aria-labelledby="seating">
            <h2 id="seating">{t.seatMapTitle}</h2>
            <p><span className="badge badge-gold">{t.reservedSeating}</span></p>
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
            <h2 id="good">{t.practicalInfo}</h2>
            <dl className="facts">
              {shownFacts.map(([k, v]) => (
                <div className="fact" key={k + v}>
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
            {mapUrl && <a className="btn btn-ghost" style={{ marginTop: 14, minHeight: 44 }} href={mapUrl} target="_blank" rel="noopener noreferrer">{t.openMap}</a>}
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
        </div>
      </div>
    </>
  );
}
