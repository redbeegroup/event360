import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getOrganizer } from '../../../lib/api';
import { dict, href, isLang, pick, type Lang } from '../../../lib/i18n';
import { TicketCard } from '../../../components/Cards';

type P = { params: Promise<{ lang: string; slug: string }> };

export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang, slug } = await params;
  const o = await getOrganizer(slug);
  if (!o) return {};
  const l: Lang = isLang(lang) ? lang : 'en';
  return {
    title: o.name,
    description: pick(l, o.description, o.descriptionMy) || undefined,
    alternates: { canonical: href(l, `/o/${o.slug}`), languages: { en: `/o/${o.slug}`, my: `/my/o/${o.slug}` } },
    openGraph: { title: o.name, images: o.logoUrl ? [{ url: o.logoUrl }] : undefined },
  };
}

export default async function OrganizerPage({ params }: P) {
  const { lang: l, slug } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  const t = dict(lang);
  const o = await getOrganizer(slug);
  if (!o) notFound();
  const upcoming = o.events.filter((e) => new Date(e.endsAt) > new Date());
  return (
    <div className="wrap">
      <div className="org-head">
        {o.logoUrl ? <img src={o.logoUrl} alt="" /> : <span className="ph" aria-hidden="true" />}
        <div>
          <h1 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.6rem)' }}>{o.name}</h1>
          {o.verified && <div className="badge">{t.verified}</div>}
        </div>
      </div>
      {pick(lang, o.description, o.descriptionMy) && <p className="prose" style={{ marginTop: 12 }}>{pick(lang, o.description, o.descriptionMy)}</p>}
      {(o.website || o.facebookUrl) && (
        <p style={{ marginTop: 12, display: 'flex', gap: 16 }}>
          {o.website && <a href={o.website} rel="noopener noreferrer nofollow" target="_blank">{t.website}</a>}
          {o.facebookUrl && <a href={o.facebookUrl} rel="noopener noreferrer nofollow" target="_blank">{t.facebook}</a>}
        </p>
      )}
      <section className="section" aria-labelledby="up">
        <div className="section-head"><h2 id="up">{t.organizerEvents}</h2></div>
        {upcoming.length === 0 ? <p className="empty">{t.noOrgEvents}</p> : <div className="tickets">{upcoming.map((e) => <TicketCard key={e.id} e={e} lang={lang} />)}</div>}
      </section>
    </div>
  );
}
