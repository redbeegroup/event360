import type { ReactNode } from 'react';
import { dict, type Lang } from '../lib/i18n';

/** Legal page: Myanmar readers get a Myanmar summary first; the English text is the full version. */
export function Legal({ lang, title, updated, summaryMy, children }: { lang: Lang; title: string; updated: string; summaryMy: ReactNode; children: ReactNode }) {
  const t = dict(lang);
  return (
    <article className="wrap legal">
      <h1>{title}</h1>
      <p className="muted">{t.lastUpdated}: {updated}</p>
      {lang === 'my' && (
        <div style={{ marginTop: 20, padding: 16, background: '#fff', border: '1px solid var(--line)', borderRadius: 12 }}>
          {summaryMy}
          <p className="muted small" style={{ marginTop: 10 }}>အောက်ပါ အင်္ဂလိပ်ဘာသာ စာသားသည် အပြည့်အစုံ ဖြစ်ပါသည်။</p>
        </div>
      )}
      <div lang="en">{children}</div>
    </article>
  );
}
