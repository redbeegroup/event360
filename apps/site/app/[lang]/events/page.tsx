import Link from 'next/link';
import type { Metadata } from 'next';
import { getCategories, getEvents } from '../../lib/api';
import { dict, href, isLang, pick, type Lang } from '../../lib/i18n';
import { TicketCard } from '../../components/Cards';

const CITIES = ['Yangon', 'Mandalay', 'Naypyitaw', 'Bagan', 'Taunggyi', 'Mawlamyine'];
const PER_PAGE = 24;

type SP = { q?: string; category?: string; city?: string; free?: string; page?: string };

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  const t = dict(isLang(lang) ? lang : 'en');
  return { title: t.eventsTitle, description: t.eventsIntro, alternates: { canonical: href(lang as Lang, '/events'), languages: { en: '/events', my: '/my/events' } } };
}

export default async function Events({ params, searchParams }: { params: Promise<{ lang: string }>; searchParams: Promise<SP> }) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  const sp = await searchParams;
  const t = dict(lang);
  const page = Math.max(1, Number(sp.page) || 1);
  const [res, cats] = await Promise.all([
    getEvents({ q: sp.q?.slice(0, 100), category: sp.category, city: sp.city, free: sp.free === '1', page, limit: PER_PAGE }),
    getCategories(),
  ]);
  const pages = Math.max(1, Math.ceil(res.total / PER_PAGE));
  const base = href(lang, '/events');
  const qs = (over: Partial<SP>) => {
    const p = new URLSearchParams();
    const m = { ...sp, ...over };
    for (const [k, v] of Object.entries(m)) if (v) p.set(k, String(v));
    const s = p.toString();
    return s ? `${base}?${s}` : base;
  };
  const filtered = !!(sp.q || sp.category || sp.city || sp.free);
  return (
    <div className="wrap">
      <div className="page-head">
        <h1 style={{ fontSize: 'clamp(2rem, 4vw, 3rem)' }}>{t.eventsTitle}</h1>
        <p className="muted">{t.eventsIntro}</p>
      </div>
      <form className="filters" action={base} role="search" aria-label={t.filters}>
        <label className="grow">
          {t.search}
          <input type="search" name="q" defaultValue={sp.q ?? ''} placeholder={t.searchPlaceholder} />
        </label>
        <label>
          {t.category}
          <select name="category" defaultValue={sp.category ?? ''}>
            <option value="">{t.anyCategory}</option>
            {cats.map((c) => (
              <optgroup key={c.id} label={pick(lang, c.nameEn, c.nameMy)}>
                {c.children.map((s) => <option key={s.id} value={s.slug}>{pick(lang, s.nameEn, s.nameMy)}</option>)}
              </optgroup>
            ))}
          </select>
        </label>
        <label>
          {t.city}
          <select name="city" defaultValue={sp.city ?? ''}>
            <option value="">{t.allCities}</option>
            {CITIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </label>
        <label className="check"><input type="checkbox" name="free" value="1" defaultChecked={sp.free === '1'} /> {t.freeOnly}</label>
        <button className="btn btn-night" type="submit">{t.apply}</button>
        {filtered && <Link className="btn btn-ghost" href={base}>{t.clear}</Link>}
      </form>
      <p className="muted" aria-live="polite" style={{ marginBottom: 14 }}>{t.results(res.total)}</p>
      {res.items.length === 0 ? (
        <p className="empty">{t.noResults}</p>
      ) : (
        <div className="tickets">{res.items.map((e) => <TicketCard key={e.id} e={e} lang={lang} />)}</div>
      )}
      {pages > 1 && (
        <nav className="pager" aria-label="Pages">
          {page > 1 && <Link className="btn btn-ghost" href={qs({ page: String(page - 1) })} rel="prev">{t.prev}</Link>}
          <span className="muted">{t.pageOf(page, pages)}</span>
          {page < pages && <Link className="btn btn-ghost" href={qs({ page: String(page + 1) })} rel="next">{t.next}</Link>}
        </nav>
      )}
    </div>
  );
}
