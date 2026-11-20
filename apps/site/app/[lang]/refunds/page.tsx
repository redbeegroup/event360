import type { Metadata } from 'next';
import { Legal } from '../../components/Legal';
import { CONTACT_EMAIL } from '../../lib/config';
import { dict, href, isLang, type Lang } from '../../lib/i18n';

type P = { params: Promise<{ lang: string }> };
export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang } = await params;
  return { title: dict(isLang(lang) ? lang : 'en').refunds, alternates: { canonical: href(lang as Lang, '/refunds'), languages: { en: '/refunds', my: '/my/refunds' } } };
}

export default async function Refunds({ params }: P) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  return (
    <Legal
      lang={lang}
      title={dict(lang).refunds}
      updated="20 Nov 2026"
      summaryMy={
        <ul>
          <li>ပွဲတစ်ခုစီ၏ စာမျက်နှာတွင် ၎င်း၏ ငွေပြန်အမ်းမူဝါဒ ပါရှိပါသည်။</li>
          <li>ပွဲဖျက်သိမ်းပါက ငွေပေးလက်မှတ်များကို ပြန်အမ်းပါမည်။</li>
          <li>ငွေကို ပေးချေခဲ့သော ပိုက်ဆံအိတ်သို့ ပြန်ပို့ပါသည်။ မဖြစ်နိုင်ပါက ကျွန်ုပ်တို့ ဆက်သွယ်ပါမည်။</li>
          <li>ငွေပြန်အမ်းပြီးသော လက်မှတ်များ အသုံးမပြုနိုင်တော့ပါ။</li>
        </ul>
      }
    >
      <h2>Each event’s policy</h2>
      <p>Organizers set a refund policy for their event; it is shown on the event page under “Refund policy”. If an event has no policy, tickets are not refundable except as below.</p>
      <h2>When you always get your money back</h2>
      <ul>
        <li>The event is cancelled.</li>
        <li>You paid but your tickets couldn’t be issued (for example the tickets sold out before your payment arrived). These orders are refunded automatically by our team.</li>
        <li>You were charged twice for the same order.</li>
      </ul>
      <h2>How refunds are paid</h2>
      <p>
        Refunds go back to the wallet or account you paid with. Where the payment provider doesn’t support automatic refunds, our team sends the money back by transfer and the order
        shows the transfer reference. The whole order is refunded; its tickets stop working.
      </p>
      <h2>Asking for a refund</h2>
      <p>
        Contact the organizer first (their details are on their organizer page), or write to <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> with your phone number and the
        order or ticket code shown in the app.
      </p>
      <p><a href={href(lang, '/terms')}>Terms of service</a></p>
    </Legal>
  );
}
