import type { Metadata } from 'next';
import { Inter, Noto_Sans_Myanmar } from 'next/font/google';
import Link from 'next/link';
import type { ReactNode } from 'react';
import { setLangAction, logoutAction } from './actions';
import { ACCESS_COOKIE } from './lib/api';
import { t } from './lib/i18n';
import { cookies } from 'next/headers';
import './globals.css';

const inter = Inter({ subsets: ['latin'], variable: '--font-sans' });
const myanmar = Noto_Sans_Myanmar({ subsets: ['myanmar'], weight: ['400', '600', '700'], variable: '--font-my' });

export const metadata: Metadata = { title: 'Event 360 Portal', description: 'Admin & organizer portal' };

export default async function RootLayout({ children }: { children: ReactNode }) {
  const tr = await t();
  const signedIn = Boolean((await cookies()).get(ACCESS_COOKIE)?.value);
  return (
    <html lang={tr.lang === 'my' ? 'my' : 'en'} className={`${inter.variable} ${myanmar.variable}`}>
      <body>
        <header className="top">
          <Link href="/" className="brand">Event 360</Link>
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
