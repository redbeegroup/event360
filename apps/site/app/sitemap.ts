import type { MetadataRoute } from 'next';
import { getEvents } from './lib/api';
import { SITE_URL } from './lib/config';

export const dynamic = 'force-dynamic';

/** Static pages + upcoming events, each in English (root) and Myanmar (/my). */
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const both = (path: string, extra: Partial<MetadataRoute.Sitemap[number]> = {}): MetadataRoute.Sitemap[number] => ({
    url: `${SITE_URL}${path}`,
    alternates: { languages: { en: `${SITE_URL}${path}`, my: `${SITE_URL}/my${path === '/' ? '' : path}` } },
    ...extra,
  });
  const pages = ['/', '/events', '/privacy', '/terms', '/refunds', '/delete-account'].map((p) => both(p, { changeFrequency: p === '/' || p === '/events' ? 'daily' : 'yearly' }));
  const events: MetadataRoute.Sitemap = [];
  const orgs = new Set<string>();
  for (let page = 1; page <= 20; page++) {
    const r = await getEvents({ page, limit: 50 }).catch(() => null); // API maximum per page
    if (!r) break;
    for (const e of r.items) {
      events.push(both(`/e/${e.slug}`, { changeFrequency: 'daily' }));
      orgs.add(e.organization.slug);
    }
    if (page * 50 >= r.total) break;
  }
  return [...pages, ...events, ...[...orgs].map((s) => both(`/o/${s}`, { changeFrequency: 'weekly' }))];
}
