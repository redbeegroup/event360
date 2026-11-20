import type { MetadataRoute } from 'next';
import { INDEXABLE, SITE_URL } from './lib/config';

export const dynamic = 'force-dynamic';

export default function robots(): MetadataRoute.Robots {
  return INDEXABLE ? { rules: { userAgent: '*', allow: '/' }, sitemap: `${SITE_URL}/sitemap.xml` } : { rules: { userAgent: '*', disallow: '/' } };
}
