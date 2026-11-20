import '@fontsource-variable/bricolage-grotesque';
import '@fontsource-variable/figtree';
import '@fontsource/noto-sans-myanmar/400.css';
import '@fontsource/noto-sans-myanmar/700.css';
import '../globals.css';
import type { Metadata, Viewport } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { ReactNode } from 'react';
import { APP_URL, CONTACT_EMAIL, INDEXABLE, PORTAL_URL, SITE_URL } from '../lib/config';
import { dict, href, isLang, type Lang } from '../lib/i18n';
import { LangSwitch } from '../components/LangSwitch';

export const dynamic = 'force-dynamic';

export const viewport: Viewport = { themeColor: '#1b1e4b', width: 'device-width', initialScale: 1 };

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  const l = isLang(lang) ? lang : 'en';
  return {
    metadataBase: new URL(SITE_URL),
    title: { default: l === 'my' ? 'Event 360 — မြန်မာနိုင်ငံရှိ ပွဲများ' : 'Event 360 — Events in Myanmar', template: '%s · Event 360' },
    description: dict(l).heroBody,
    robots: INDEXABLE ? { index: true, follow: true } : { index: false, follow: false },
    openGraph: { siteName: 'Event 360', locale: l === 'my' ? 'my_MM' : 'en_US', type: 'website' },
    icons: { icon: '/favicon.svg' },
  };
}

export default async function LangLayout({ children, params }: { children: ReactNode; params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLang(lang)) notFound();
  const t = dict(lang);
  const L = (p: string) => href(lang as Lang, p);
  return (
    <html lang={lang}>
      <body>
        <a className="visually-hidden" href="#main">Skip to content</a>
        <header className="site-header">
          <div className="wrap">
            <Link className="brand" href={L('/')}>
              <span className="brand-mark" aria-hidden="true" />
              Event 360
            </Link>
            <nav className="site-nav" aria-label="Main">
              <Link href={L('/events')}>{t.nav.events}</Link>
              <a className="hide-sm" href={PORTAL_URL}>{t.nav.organizers}</a>
              <LangSwitch lang={lang} />
              <a className="btn btn-night hide-sm" style={{ minHeight: 40 }} href={APP_URL}>{t.nav.getApp}</a>
            </nav>
          </div>
        </header>
        <main id="main">{children}</main>
        <footer className="site-footer">
          <div className="wrap">
            <div className="footer-grid">
              <div>
                <div className="brand" style={{ color: '#fff' }}>
                  <span className="brand-mark" aria-hidden="true" style={{ background: '#2a2e6e' }} />
                  Event 360
                </div>
                <p style={{ marginTop: 12, maxWidth: '36ch' }}>{t.footerTag}</p>
              </div>
              <div>
                <h3>Event 360</h3>
                <ul>
                  <li><Link href={L('/events')}>{t.nav.events}</Link></li>
                  <li><a href={APP_URL}>{t.nav.getApp}</a></li>
                  <li><a href={PORTAL_URL}>{t.forOrganizers}</a></li>
                  <li><a href={`mailto:${CONTACT_EMAIL}`}>{t.contact}</a></li>
                </ul>
              </div>
              <div>
                <h3>{t.terms}</h3>
                <ul>
                  <li><Link href={L('/privacy')}>{t.privacy}</Link></li>
                  <li><Link href={L('/terms')}>{t.terms}</Link></li>
                  <li><Link href={L('/refunds')}>{t.refunds}</Link></li>
                  <li><Link href={L('/delete-account')}>{t.deleteAccount}</Link></li>
                </ul>
              </div>
            </div>
            <p className="footer-small">© {new Date().getFullYear()} Event 360</p>
          </div>
        </footer>
      </body>
    </html>
  );
}
