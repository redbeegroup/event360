import type { Metadata } from 'next';
import '@fontsource-variable/bricolage-grotesque';
import '@fontsource-variable/figtree';
import '@fontsource/noto-sans-myanmar/400.css';
import '@fontsource/noto-sans-myanmar/700.css';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { setLangAction, logoutAction } from './actions';
import { ACCESS_COOKIE } from './lib/api';
import { t } from './lib/i18n';
import { cookies } from 'next/headers';
import './globals.css';

export const metadata: Metadata = { title: 'Event 360 Portal', description: 'Admin & organizer portal' };

export default async function RootLayout({ children }: { children: ReactNode }) {
  const tr = await t();
  const signedIn = Boolean((await cookies()).get(ACCESS_COOKIE)?.value);
  return (
    <html lang={tr.lang === 'my' ? 'my' : 'en'}>
      <body>
        <header className="top">
          <Link href="/" className="brand"><span className="brand-mark" aria-hidden="true" />Event 360</Link>
          {signedIn && (
            <nav>
              <Link href="/organizer">{tr.organizer}</Link>
              <Link href="/admin">{tr.admin}</Link>
            </nav>
          )}
          <span className="spacer" />
          <form action={setLangAction}>
            <input type="hidden" name="lang" value={tr.lang === 'my' ? 'en' : 'my'} />
            <button className="link" type="submit">{tr.language}</button>
          </form>
          {signedIn && (
            <form action={logoutAction}>
              <button className="link" type="submit">{tr.logout}</button>
            </form>
          )}
        </header>
        <main>{children}</main>
      </body>
    </html>
  );
}
