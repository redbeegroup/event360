import type { Metadata } from 'next';
import { Legal } from '../../components/Legal';
import { CONTACT_EMAIL, OPERATOR } from '../../lib/config';
import { dict, href, isLang, type Lang } from '../../lib/i18n';

type P = { params: Promise<{ lang: string }> };
export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang } = await params;
  return { title: dict(isLang(lang) ? lang : 'en').terms, alternates: { canonical: href(lang as Lang, '/terms'), languages: { en: '/terms', my: '/my/terms' } } };
}

export default async function Terms({ params }: P) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  return (
    <Legal
      lang={lang}
      title={dict(lang).terms}
      updated="20 Nov 2026"
      summaryMy={
        <ul>
          <li>Event 360 သည် ပွဲစီစဉ်သူများနှင့် တက်ရောက်သူများကို ချိတ်ဆက်ပေးသော ပလက်ဖောင်း ဖြစ်ပါသည်။ ပွဲကို စီစဉ်သူက တာဝန်ယူပါသည်။</li>
          <li>လက်မှတ်တစ်စောင်ကို တစ်ကြိမ်သာ ဝင်ရောက်နိုင်ပါသည်။ စီစဉ်သူ ခွင့်ပြုပါက App ထဲမှ လွှဲပြောင်းနိုင်ပါသည်။</li>
          <li>ငွေပြန်အမ်းခြင်းသည် ပွဲ၏ ငွေပြန်အမ်းမူဝါဒအတိုင်း ဖြစ်ပါသည်။ ပွဲဖျက်သိမ်းပါက ငွေပြန်အမ်းပါသည်။</li>
          <li>လက်မှတ်များကို ပြန်ရောင်းခြင်း၊ အတုလုပ်ခြင်း မပြုရပါ။</li>
        </ul>
      }
    >
      <p>These terms apply when you use Event 360, operated by {OPERATOR}. By creating an account or getting a ticket you agree to them.</p>
      <h2>What Event 360 does</h2>
      <p>
        Event 360 lets organizers list events and sell or give away tickets, and lets attendees find events, get tickets on their phone and check in at the door. Each event is run
        by its organizer, who is responsible for the event itself: its content, safety, timing, venue and anything promised on the event page. Event 360 is not the organizer
        unless the event page says so.
      </p>
      <h2>Your account</h2>
      <ul>
        <li>Use your own phone number and keep access to it; whoever can receive your login codes can use your account.</li>
        <li>Organizer and staff accounts are personal; don’t share passwords.</li>
      </ul>
      <h2>Tickets</h2>
      <ul>
        <li>A ticket admits one person once, unless the event page says otherwise. The QR code is checked at the door; screenshots and copies of a ticket that has been used will be refused.</li>
        <li>You may send an unused ticket to another phone number in the app when the organizer allows transfers, up to the time the organizer sets before the start. The old QR code stops working when you do.</li>
        <li>Tickets may not be resold for more than their price, copied or altered. We may cancel tickets obtained by fraud or in breach of these terms.</li>
        <li>Organizers may limit how many tickets one person can hold and may refuse entry for reasons stated on the event page (for example age limits).</li>
      </ul>
      <h2>Prices, payment and fees</h2>
      <ul>
        <li>Prices are in Myanmar kyat (MMK). You pay the price shown at checkout, after any promo code. Your seats are held for a short time while you pay.</li>
        <li>Payments are processed by the payment provider you choose (for example KBZPay or WavePay) under its own terms.</li>
        <li>Organizers pay Event 360 a service fee on paid tickets; buyers are not charged an extra fee unless checkout shows one.</li>
      </ul>
      <h2>Changes, cancellations and refunds</h2>
      <p>
        Organizers may change an event’s time or place; we notify ticket holders. Refunds follow the event’s refund policy and our <a href={href(lang, '/refunds')}>refund page</a>. If an event is
        cancelled, paid tickets are refunded.
      </p>
      <h2>Organizers</h2>
      <ul>
        <li>Organizers must give accurate event information, hold the rights to the content they upload (images, recordings, performer details) and follow the law.</li>
        <li>We review events from unverified organizers before they appear and may remove events that break these terms.</li>
        <li>Money owed to organizers for paid tickets, minus fees and refunds, is paid out to them separately.</li>
      </ul>
      <h2>Live streams and recordings</h2>
      <p>Streams and recordings are for ticket holders’ personal viewing. Recording, re-streaming or sharing them is not allowed.</p>
      <h2>Liability</h2>
      <p>
        We work to keep Event 360 available but can’t promise it will never be interrupted. To the extent the law allows, Event 360 is not liable for the event itself or for losses
        caused by an organizer, a venue or a payment provider; our liability for a ticket is limited to the amount paid for it.
      </p>
      <h2>Changes to these terms</h2>
      <p>We may update these terms; the date above shows the latest version. Important changes will be announced in the app.</p>
      <h2>Contact</h2>
      <p><a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a></p>
    </Legal>
  );
}
