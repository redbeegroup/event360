import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { FcmClient } from './fcm';
import { PushSettingsService } from './settings.service';
import { SmsService } from './sms.service';

export type NotificationKind =
  | 'ticket_confirmed'
  | 'event_reminder'
  | 'event_changed'
  | 'event_cancelled'
  | 'live_now'
  | 'order_refunded'
  | 'announcement'
  | 'ticket_received'
  | 'test';

export interface NoticeText {
  kind: NotificationKind;
  title: string;
  titleMy?: string | null;
  body: string;
  bodyMy?: string | null;
  link?: string | null;
  eventId?: string | null;
  /** English-only SMS (one part where possible); only sent when SMS is enabled. */
  sms?: string;
}

const TZ = 'Asia/Yangon';
export const when = (d: Date, lang: 'en' | 'my' = 'en') =>
  new Intl.DateTimeFormat(lang === 'my' ? 'my-MM' : 'en-GB', { timeZone: TZ, weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }).format(d);
const short = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/**
 * Delivers notifications: every one is stored in the user's in-app inbox, then pushed to their devices (Firebase),
 * and — only for event changes/cancellations — sent by SMS. Delivery runs in the background so the request that
 * caused it (cancel an event, a payment callback, …) is not slowed down; `idle()` waits for it (tests, shutdown).
 */
@Injectable()
export class NotifyService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotifyService.name);
  private timer?: NodeJS.Timeout;
  private readonly inflight = new Set<Promise<unknown>>();
  fcm = new FcmClient();

  constructor(
    private readonly prisma: PrismaService,
    private readonly push: PushSettingsService,
    private readonly sms: SmsService,
  ) {}

  onModuleInit() {
    if ((process.env.APP_ROLE ?? 'api') === 'api' && process.env.NODE_ENV !== 'test') {
      this.timer = setInterval(() => this.sendReminders().catch((e) => this.logger.warn(`reminders: ${e.message}`)), 5 * 60_000);
    }
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  idle() {
    return Promise.allSettled([...this.inflight]);
  }

  private background<T>(p: Promise<T>) {
    const tracked = p.catch((e) => this.logger.warn(`notify: ${(e as Error).message}`)).finally(() => this.inflight.delete(tracked));
    this.inflight.add(tracked);
    return tracked;
  }

  /** Users holding a ticket that still counts for this event. */
  async holders(eventId: string): Promise<string[]> {
    const rows = await this.prisma.ticket.findMany({
      where: { ticketType: { eventId }, status: { in: ['VALID', 'CHECKED_IN'] } },
      select: { holderUserId: true },
      distinct: ['holderUserId'],
    });
    return rows.map((r) => r.holderUserId);
  }

  toUsers(userIds: string[], n: NoticeText) {
    return this.background(this.deliver([...new Set(userIds)], n));
  }

  toEventHolders(eventId: string, n: NoticeText) {
    return this.background(this.holders(eventId).then((ids) => this.deliver(ids, n)));
  }

  /** Returns how many users got the notice. */
  async deliver(userIds: string[], n: NoticeText): Promise<number> {
    if (!userIds.length) return 0;
    for (let i = 0; i < userIds.length; i += 1000) {
      await this.prisma.notification.createMany({
        data: userIds.slice(i, i + 1000).map((userId) => ({
          userId,
          kind: n.kind,
          title: n.title.slice(0, 200),
          titleMy: n.titleMy?.slice(0, 200) ?? null,
          body: n.body.slice(0, 1000),
          bodyMy: n.bodyMy?.slice(0, 1000) ?? null,
          link: n.link ?? null,
          eventId: n.eventId ?? null,
        })),
      });
    }
    await this.pushTo(userIds, n).catch((e) => this.logger.warn(`push: ${(e as Error).message}`));
    if (n.sms) await this.smsTo(userIds, n.sms).catch((e) => this.logger.warn(`sms: ${(e as Error).message}`));
    return userIds.length;
  }

  private async pushTo(userIds: string[], n: NoticeText) {
    const cfg = await this.push.config();
    if (!cfg?.enabled) return;
    const devices = await this.prisma.device.findMany({
      where: { userId: { in: userIds }, pushToken: { not: null } },
      select: { id: true, pushToken: true, user: { select: { locale: true } } },
    });
    let ok = 0;
    let removed = 0;
    for (let i = 0; i < devices.length; i += 10) {
      await Promise.all(
        devices.slice(i, i + 10).map(async (d) => {
          const my = d.user.locale === 'my';
          const r = await this.fcm
            .send(cfg, d.pushToken!, {
              title: (my && n.titleMy) || n.title,
              body: (my && n.bodyMy) || n.body,
              data: { kind: n.kind, ...(n.link ? { link: n.link } : {}), ...(n.eventId ? { eventId: n.eventId } : {}) },
            })
            .catch(() => 'error' as const);
          if (r === 'ok') ok++;
          if (r === 'invalid_token') {
            removed++;
            await this.prisma.device.delete({ where: { id: d.id } }).catch(() => undefined);
          }
        }),
      );
    }
    if (devices.length) this.logger.log(`push ${n.kind}: ${ok}/${devices.length} delivered, ${removed} stale tokens removed`);
  }

  private async smsTo(userIds: string[], text: string) {
    const cfg = await this.sms.settingsConfig();
    if (!cfg?.enabled) return;
    const users = await this.prisma.user.findMany({ where: { id: { in: userIds }, phone: { not: null } }, select: { phone: true } });
    for (let i = 0; i < users.length; i += 4) {
      await Promise.all(users.slice(i, i + 4).map((u) => this.sms.send(u.phone!, text, 'notify', cfg).catch(() => undefined)));
    }
  }

  // ───────────── messages ─────────────

  ticketConfirmed(orderId: string) {
    return this.background(this.buildTicketConfirmed(orderId));
  }

  private async buildTicketConfirmed(orderId: string) {
    const o = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { event: { select: { id: true, title: true, titleMy: true, startsAt: true } }, _count: { select: { tickets: true } } },
    });
    if (!o || !o._count.tickets) return;
    const n = o._count.tickets;
    return this.toUsers([o.userId], {
      kind: 'ticket_confirmed',
      title: n === 1 ? 'Your ticket is ready' : `Your ${n} tickets are ready`,
      titleMy: `လက်မှတ် ${n} စောင် အသင့်ဖြစ်ပါပြီ`,
      body: `${o.event.title} · ${when(o.event.startsAt)}. Show the QR code at the entrance.`,
      bodyMy: `${o.event.titleMy || o.event.title} · ${when(o.event.startsAt, 'my')}။ ဝင်ပေါက်တွင် QR ကုဒ်ကို ပြပါ။`,
      link: '/tickets',
      eventId: o.event.id,
    });
  }

  orderRefunded(orderId: string) {
    return this.background(this.buildOrderRefunded(orderId));
  }

  private async buildOrderRefunded(orderId: string) {
    const o = await this.prisma.order.findUnique({ where: { id: orderId }, include: { event: { select: { id: true, title: true, titleMy: true } } } });
    if (!o) return;
    const amount = Number(o.totalMmk).toLocaleString('en-US');
    return this.toUsers([o.userId], {
      kind: 'order_refunded',
      title: 'Order refunded',
      titleMy: 'ငွေပြန်အမ်းပြီးပါပြီ',
      body: `Your order for ${o.event.title} (${amount} MMK) was refunded. Its tickets no longer work.`,
      bodyMy: `${o.event.titleMy || o.event.title} အတွက် အော်ဒါ (${amount} ကျပ်) ကို ငွေပြန်အမ်းပြီးပါပြီ။ ၎င်း၏ လက်မှတ်များ အသုံးမပြုနိုင်တော့ပါ။`,
      link: '/tickets',
      eventId: o.event.id,
    });
  }

  eventCancelled(e: { id: string; title: string; titleMy: string | null; startsAt: Date }) {
    return this.toEventHolders(e.id, {
      kind: 'event_cancelled',
      title: 'Event cancelled',
      titleMy: 'ပွဲ ဖျက်သိမ်းလိုက်ပါပြီ',
      body: `${e.title} (${when(e.startsAt)}) has been cancelled by the organizer.`,
      bodyMy: `${e.titleMy || e.title} (${when(e.startsAt, 'my')}) ကို စီစဉ်သူက ဖျက်သိမ်းလိုက်ပါသည်။`,
      link: `/event/${e.id}`,
      eventId: e.id,
      sms: `Event 360: "${short(e.title, 60)}" on ${when(e.startsAt)} has been CANCELLED by the organizer. Details in the app.`,
    });
  }

  eventChanged(e: { id: string; title: string; titleMy: string | null; startsAt: Date; venue: string | null }) {
    const at = e.venue ? ` at ${e.venue}` : '';
    const atMy = e.venue ? ` · ${e.venue}` : '';
    return this.toEventHolders(e.id, {
      kind: 'event_changed',
      title: 'Event details changed',
      titleMy: 'ပွဲအချက်အလက် ပြောင်းလဲသွားပါသည်',
      body: `${e.title} is now ${when(e.startsAt)}${at}.`,
      bodyMy: `${e.titleMy || e.title} — ယခု ${when(e.startsAt, 'my')}${atMy}`,
      link: `/event/${e.id}`,
      eventId: e.id,
      sms: `Event 360: "${short(e.title, 50)}" changed. Now ${when(e.startsAt)}${short(at, 50)}. Details in the app.`,
    });
  }

  liveNow(e: { eventId: string; eventTitle: string; eventTitleMy: string | null; sessionTitle: string; channelId: string }) {
    const q = encodeURIComponent(e.sessionTitle);
    return this.toEventHolders(e.eventId, {
      kind: 'live_now',
      title: 'Live now',
      titleMy: 'ယခု တိုက်ရိုက်ထုတ်လွှင့်နေပါပြီ',
      body: `${e.sessionTitle} — ${e.eventTitle} is streaming now. Tap to watch.`,
      bodyMy: `${e.sessionTitle} — ${e.eventTitleMy || e.eventTitle} ယခု တိုက်ရိုက်ထုတ်လွှင့်နေပါသည်။ ကြည့်ရန် နှိပ်ပါ။`,
      link: `/watch/live/${e.channelId}?title=${q}`,
      eventId: e.eventId,
    });
  }

  /** Day-before reminders, once per event (safe with several API replicas: the claim is a conditional update). */
  async sendReminders(now = new Date()) {
    const due = await this.prisma.event.findMany({
      where: { status: 'PUBLISHED', reminderSentAt: null, startsAt: { gt: now, lte: new Date(now.getTime() + 24 * 3600e3) } },
      include: { venue: { select: { name: true } } },
      take: 50,
    });
    let sent = 0;
    for (const e of due) {
      const claim = await this.prisma.event.updateMany({ where: { id: e.id, reminderSentAt: null }, data: { reminderSentAt: now } });
      if (claim.count !== 1) continue;
      const at = e.venue?.name ? ` at ${e.venue.name}` : '';
      await this.toEventHolders(e.id, {
        kind: 'event_reminder',
        title: 'Coming up',
        titleMy: 'မကြာမီ စတင်ပါမည်',
        body: `${e.title} starts ${when(e.startsAt)}${at}. Your ticket is in the app.`,
        bodyMy: `${e.titleMy || e.title} — ${when(e.startsAt, 'my')}${e.venue?.name ? ` · ${e.venue.name}` : ''} တွင် စတင်ပါမည်။ လက်မှတ်သည် App ထဲတွင် ရှိပါသည်။`,
        link: '/tickets',
        eventId: e.id,
      });
      sent++;
    }
    return sent;
  }
}
