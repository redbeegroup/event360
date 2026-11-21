'use client';

import { usePathname } from 'next/navigation';
import type { Lang } from '../lib/i18n';

/** Same page in the other language (/x ↔ /my/x). */
export function LangSwitch({ lang }: { lang: Lang }) {
  const path = usePathname() ?? '/';
  const bare = path === '/my' ? '/' : path.startsWith('/my/') ? path.slice(3) : path.replace(/^\/en(?=\/|$)/, '') || '/';
  const to = lang === 'en' ? `/my${bare === '/' ? '' : bare}` : bare;
  return (
    <a href={to} hrefLang={lang === 'en' ? 'my' : 'en'} lang={lang === 'en' ? 'my' : 'en'}>
      {lang === 'en' ? 'မြန်မာ' : 'English'}
    </a>
  );
}
