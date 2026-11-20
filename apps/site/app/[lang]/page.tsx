import Link from 'next/link';
import type { Metadata } from 'next';
import { getCategories, getEvents } from '../lib/api';
import { PORTAL_URL } from '../lib/config';
import { dict, href, isLang, pick, type Lang } from '../lib/i18n';
import { TicketCard, TicketStub } from '../components/Cards';

const CITIES = ['Yangon', 'Mandalay', 'Naypyitaw', 'Bagan', 'Taunggyi'];

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  return { alternates: { canonical: href(lang as Lang, '/'), languages: { en: '/', my: '/my' } } };
}

export default async function Home({ params }: { params: Promise<{ lang: string }> }) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  const t = dict(lang);
  const [page, cats] = await Promise.all([getEvents({ limit: 12 }), getCategories()]);
  const events = page.items;
  const soon = events.slice(0, 3);
  const L = (p: string) => href(lang, p);
  return (
    <>
      <section className="hero">
        <div className="wrap hero-grid">
          <div>
            <h1>{t.heroTitle}</h1>
            <p className="hero-body">{t.heroBody}</p>
            <form className="search" action={L('/events')} role="search">
              <label className="visually-hidden" htmlFor="q">{t.searchPlaceholder}</label>
              <input id="q" name="q" type="search" placeholder={t.searchPlaceholder} />
              <button className="btn btn-gold" type="submit">{t.search}</button>
            </form>
            <nav className="city-row" aria-label={t.city}>
              {CITIES.map((c) => (
                <Link key={c} href={`${L('/events')}?city=${encodeURIComponent(c)}`}>{c}</Link>
              ))}
            </nav>
          </div>
          {soon.length > 0 && (
            <div className="hero-stack">
              <h2>{t.comingUp}</h2>
              {soon.map((e) => <TicketStub key={e.id} e={e} lang={lang} />)}
            </div>
          )}
        </div>
      </section>

      {events.length > 0 && (
        <section className="section wrap" aria-labelledby="upcoming">
          <div className="section-head">
            <h2 id="upcoming">{t.comingUp}</h2>
            <Link href={L('/events')}>{t.seeAll}</Link>
          </div>
          <div className="tickets">
            {events.slice(0, 8).map((e) => <TicketCard key={e.id} e={e} lang={lang} />)}
          </div>
        </section>
      )}

      {cats.length > 0 && (
        <section className="section wrap" aria-labelledby="cats">
          <div className="section-head"><h2 id="cats">{t.browseByCategory}</h2></div>
          <div className="cats">
            {cats.flatMap((c) => c.children).map((c) => (
              <Link key={c.id} href={`${L('/events')}?category=${encodeURIComponent(c.slug)}`}>{pick(lang, c.nameEn, c.nameMy)}</Link>
            ))}
          </div>
        </section>
      )}

      <section className="section wrap" aria-labelledby="how">
        <h2 id="how">{t.howTitle}</h2>
        <ol className="how">
          {t.how.map(([title, body]) => (
            <li key={title}>
              <h3>{title}</h3>
              <p className="muted" style={{ marginTop: 6 }}>{body}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="section wrap" aria-labelledby="org">
        <div className="org-band">
          <div>
            <h2 id="org">{t.orgTitle}</h2>
            <p>{t.orgBody}</p>
            <a className="btn btn-gold" style={{ marginTop: 22 }} href={PORTAL_URL}>{t.orgCta}</a>
          </div>
          <ul>{t.orgPoints.map((x) => <li key={x}>{x}</li>)}</ul>
        </div>
      </section>
    </>
  );
}
