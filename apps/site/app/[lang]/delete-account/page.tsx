import type { Metadata } from 'next';
import { Legal } from '../../components/Legal';
import { CONTACT_EMAIL } from '../../lib/config';
import { dict, href, isLang, type Lang } from '../../lib/i18n';

type P = { params: Promise<{ lang: string }> };
export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang } = await params;
  return { title: dict(isLang(lang) ? lang : 'en').deleteAccount, alternates: { canonical: href(lang as Lang, '/delete-account'), languages: { en: '/delete-account', my: '/my/delete-account' } } };
}

export default async function DeleteAccount({ params }: P) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  const subject = encodeURIComponent('Delete my Event 360 account');
  return (
    <Legal
      lang={lang}
      title={dict(lang).deleteAccount}
      updated="20 Nov 2026"
      summaryMy={
        <>
          <p>သင့် Event 360 အကောင့်ကို ဖျက်လိုပါက အကောင့်၏ ဖုန်းနံပါတ်ကို ဖော်ပြ၍ {CONTACT_EMAIL} သို့ အီးမေးလ် ပို့ပါ။</p>
          <p style={{ marginTop: 8 }}>ရက် ၃၀ အတွင်း ဖျက်ပေးပါမည်။ လာမည့်ပွဲများအတွက် လက်မှတ်များ အသုံးမပြုနိုင်တော့ပါ။</p>
        </>
      }
    >
      <p>You can ask us to delete your Event 360 account and the personal data linked to it.</p>
      <h2>How to ask</h2>
      <p>
        Email <a href={`mailto:${CONTACT_EMAIL}?subject=${subject}`}>{CONTACT_EMAIL}</a> with the subject “Delete my Event 360 account” and the phone number (attendees) or email
        address (organizers) of the account. We may send a code to that phone number to confirm it’s you.
      </p>
      <h2>What happens</h2>
      <ul>
        <li>We delete your account within 30 days: your phone number, name, devices, notifications and sign-in sessions.</li>
        <li>Tickets for events that haven’t happened yet stop working. Ask for a refund first if the event’s policy allows one.</li>
        <li>
          Order, payment and refund records are kept as long as accounting rules require, without your name or phone number. Anonymous counts (for example how many people checked in)
          stay with the organizer.
        </li>
      </ul>
      <p>
        See the <a href={href(lang, '/privacy')}>privacy policy</a> for what we collect.
      </p>
    </Legal>
  );
}
