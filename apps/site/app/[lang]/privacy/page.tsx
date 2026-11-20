import type { Metadata } from 'next';
import { Legal } from '../../components/Legal';
import { CONTACT_EMAIL, OPERATOR } from '../../lib/config';
import { dict, href, isLang, type Lang } from '../../lib/i18n';

type P = { params: Promise<{ lang: string }> };
export async function generateMetadata({ params }: P): Promise<Metadata> {
  const { lang } = await params;
  return { title: dict(isLang(lang) ? lang : 'en').privacy, alternates: { canonical: href(lang as Lang, '/privacy'), languages: { en: '/privacy', my: '/my/privacy' } } };
}

export default async function Privacy({ params }: P) {
  const { lang: l } = await params;
  const lang: Lang = isLang(l) ? l : 'en';
  return (
    <Legal
      lang={lang}
      title={dict(lang).privacy}
      updated="20 Nov 2026"
      summaryMy={
        <ul>
          <li>ဝင်ရောက်ရန် ဖုန်းနံပါတ်ကို အသုံးပြုပြီး SMS ဖြင့် ကုဒ်ပို့ပါသည်။</li>
          <li>လက်မှတ်၊ အော်ဒါနှင့် ဝင်ပေါက်စစ်ဆေးမှု မှတ်တမ်းများကို သိမ်းဆည်းပါသည်။</li>
          <li>ပွဲစီစဉ်သူများသည် သင့်အမည်နှင့် ဖုန်းနံပါတ်၏ တစ်စိတ်တစ်ပိုင်း (ဥပမာ 0979•••123) ကိုသာ မြင်ရပါသည်။</li>
          <li>ကတ်/ပိုက်ဆံအိတ် အချက်အလက်များကို ကျွန်ုပ်တို့ မသိမ်းပါ — KBZPay/WavePay က ကိုင်တွယ်ပါသည်။</li>
          <li>အကောင့်ဖျက်ရန် {CONTACT_EMAIL} သို့ ဆက်သွယ်ပါ။</li>
        </ul>
      }
    >
      <p>
        This policy explains what {OPERATOR} (“Event 360”, “we”) collects when you use the Event 360 apps, the web app at app.event360.app, the organizer portal and this
        website, and how we use it.
      </p>
      <h2>What we collect</h2>
      <ul>
        <li><strong>Phone number.</strong> Attendees sign in with a Myanmar mobile number. We send a one-time code by SMS (through our SMS provider) to confirm it.</li>
        <li><strong>Name</strong>, if you add one to your profile, and your language choice.</li>
        <li><strong>Tickets and orders:</strong> which events you registered for or bought tickets to, amounts paid, discounts used, refunds, and ticket transfers you make or receive.</li>
        <li><strong>Payments:</strong> the payment provider (for example KBZPay or WavePay), its reference and the status. We never see or store your wallet PIN, card number or bank details.</li>
        <li><strong>Check-ins:</strong> when and at which gate your ticket was scanned.</li>
        <li><strong>Watching:</strong> when you watch a live stream or recording we record a playback session so a ticket is used on one device at a time.</li>
        <li><strong>Notifications:</strong> if you allow notifications, a device token from Firebase Cloud Messaging so we can send them, and the notifications we sent you.</li>
        <li><strong>Organizer and staff accounts:</strong> email, name, password (stored hashed) and the organizations you belong to.</li>
        <li><strong>Technical data:</strong> IP address in server logs and rate limits, and an anonymous daily count of event page views. This website does not use advertising or tracking cookies.</li>
      </ul>
      <h2>How we use it</h2>
      <ul>
        <li>To sign you in, issue and check tickets, process payments and refunds, and run live streams.</li>
        <li>To send you messages about your tickets: confirmations, reminders, changes, cancellations and organizer announcements. Event changes and cancellations may also be sent by SMS.</li>
        <li>To prevent fraud and abuse (for example limits on login codes and on tickets per person).</li>
        <li>To keep accounting records of sales, fees and refunds.</li>
      </ul>
      <h2>Who we share it with</h2>
      <ul>
        <li><strong>Event organizers</strong> see, for their own events, attendees’ names and a masked phone number (for example 0979•••123), ticket types, order status and check-ins. They do not see full phone numbers.</li>
        <li><strong>Service providers</strong> that run parts of the service for us: the SMS provider, payment providers (KBZPay, WavePay), Firebase Cloud Messaging for push notifications, and our hosting and storage.</li>
        <li><strong>Authorities</strong>, when the law requires it.</li>
      </ul>
      <p>We do not sell personal data.</p>
      <h2>How long we keep it</h2>
      <p>
        We keep your account while you use it. Order, payment and refund records are kept for as long as accounting rules require, even after an account is deleted, but they are
        then no longer linked to your phone number or name. Server logs are kept for a short period.
      </p>
      <h2>Your choices</h2>
      <ul>
        <li>Change your name and language in the app’s profile.</li>
        <li>Turn notifications off in your phone’s settings.</li>
        <li>Ask for a copy of your data or ask us to delete your account: see <a href={href(lang, '/delete-account')}>Delete your account</a>.</li>
      </ul>
      <h2>Contact</h2>
      <p>Questions about this policy: <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.</p>
    </Legal>
  );
}
