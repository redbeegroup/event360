import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { normalizeMyanmarPhone } from '../auth/phone';
import { mmk } from '../../common/util';
import { MediaService } from '../media/media.module';
import { NotifyService } from '../notifications/notify.service';
import { PrismaService } from '../prisma/prisma.service';
import { TicketTokenService } from './ticket-token.service';

@Injectable()
export class TicketsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TicketTokenService,
    private readonly media: MediaService,
    private readonly notify: NotifyService,
  ) {}

  /**
   * Free registration (Phase 1). Paid ticket types are rejected until payments land (Phase 2).
   * Inventory is reserved with a single conditional UPDATE so concurrent requests can never oversell.
   */
  async registerFree(userId: string, eventId: string, ticketTypeId: string, quantity: number) {
    const tt = await this.prisma.ticketType.findFirst({ where: { id: ticketTypeId, eventId }, include: { event: true } });
    if (!tt) throw new NotFoundException('Ticket type not found');
    const e = tt.event;
    if (e.status !== 'PUBLISHED') throw new ConflictException('Registration is not open for this event');
    const now = new Date();
    if (e.endsAt <= now) throw new ConflictException('This event has ended');
    if (tt.salesStartAt && tt.salesStartAt > now) throw new ConflictException('Registration has not opened yet');
    if (tt.salesEndAt && tt.salesEndAt < now) throw new ConflictException('Registration has closed');
    if (tt.priceMmk > 0n) throw new BadRequestException('Paid tickets are not available yet');
    if (quantity > tt.maxPerOrder) throw new BadRequestException(`At most ${tt.maxPerOrder} per person`);

    const result = await this.prisma.$transaction(async (tx) => {
      const already = await tx.ticket.count({ where: { holderUserId: userId, ticketTypeId, status: { in: ['VALID', 'CHECKED_IN'] } } });
      if (already + quantity > tt.maxPerOrder) {
        throw new ConflictException(`You already hold ${already} ticket(s); the limit is ${tt.maxPerOrder} per person`);
      }
      const reserved = await tx.$executeRaw`
        UPDATE ticket_types SET sold = sold + ${quantity}
        WHERE id = ${ticketTypeId}::uuid AND sold + held + ${quantity} <= quota`;
      if (reserved !== 1) throw new ConflictException('Not enough tickets left');

      const order = await tx.order.create({
        data: {
          userId,
          eventId,
          status: 'CONFIRMED',
          subtotalMmk: 0n,
          totalMmk: 0n,
          items: { create: { ticketTypeId, quantity, unitPriceMmk: 0n } },
        },
      });
      await tx.ticket.createMany({
        data: Array.from({ length: quantity }, () => ({ orderId: order.id, ticketTypeId, holderUserId: userId })),
      });
      const tickets = await tx.ticket.findMany({ where: { orderId: order.id }, select: { id: true } });
      return { orderId: order.id, ticketIds: tickets.map((t) => t.id) };
    });
    void this.notify.ticketConfirmed(result.orderId);
    void this.notify.checkSales(eventId, false);
    return result;
  }

  async myTickets(userId: string) {
    const rows = await this.prisma.ticket.findMany({
      where: { holderUserId: userId },
      orderBy: { createdAt: 'desc' },
      include: {
        ticketType: {
          include: { event: { include: { venue: true, organization: { select: { name: true } } } } },
        },
      },
    });
    return rows.map((t) => {
      const e = t.ticketType.event;
      return {
        id: t.id,
        status: t.status,
        createdAt: t.createdAt,
        ticketType: { id: t.ticketTypeId, name: t.ticketType.name, nameMy: t.ticketType.nameMy, priceMmk: mmk(t.ticketType.priceMmk) },
        event: {
          id: e.id,
          slug: e.slug,
          title: e.title,
          titleMy: e.titleMy,
          status: e.status,
          startsAt: e.startsAt,
          endsAt: e.endsAt,
          coverImageUrl: this.media.url(e.coverImageUrl),
          venue: e.venue,
          organization: e.organization.name,
        },
        qr: t.status === 'VALID' ? this.tokens.sign({ tid: t.id, eid: e.id, tt: t.ticketTypeId, v: t.qrVersion }) : null,
        canTransfer:
          t.status === 'VALID' &&
          e.transfersEnabled &&
          !['CANCELLED', 'COMPLETED'].includes(e.status) &&
          t.transferCount < TicketsService.MAX_TRANSFERS &&
          Date.now() < e.startsAt.getTime() - e.transferCutoffHours * 3600e3,
      };
    });
  }

  static readonly MAX_TRANSFERS = 3;

  /**
   * Gives a ticket to another phone number. The old QR stops working (qrVersion bump); the recipient sees the ticket
   * after signing in with that number (an account is created for it if needed) and gets a notification.
   */
  async transfer(userId: string, ticketId: string, rawPhone: string) {
    const phone = normalizeMyanmarPhone(rawPhone);
    if (!phone) throw new BadRequestException('Enter a valid Myanmar mobile number');
    const t = await this.prisma.ticket.findUnique({
      where: { id: ticketId },
      include: { ticketType: { include: { event: true } }, holder: { select: { phone: true, displayName: true } } },
    });
    if (!t || t.holderUserId !== userId) throw new NotFoundException('Ticket not found');
    const e = t.ticketType.event;
    if (t.status !== 'VALID') throw new ConflictException(t.status === 'CHECKED_IN' ? 'This ticket has already been used' : 'This ticket can no longer be transferred');
    if (!e.transfersEnabled) throw new ForbiddenException('The organizer does not allow ticket transfers for this event');
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException('This event is no longer running');
    if (Date.now() > e.startsAt.getTime() - e.transferCutoffHours * 3600e3) {
      throw new ConflictException(e.transferCutoffHours ? `Transfers close ${e.transferCutoffHours} hour(s) before the event starts` : 'Transfers are closed for this event');
    }
    if (t.transferCount >= TicketsService.MAX_TRANSFERS) throw new ConflictException(`A ticket can be transferred at most ${TicketsService.MAX_TRANSFERS} times`);
    if (t.holder.phone === phone) throw new BadRequestException('This ticket is already yours');

    const to = await this.prisma.user.upsert({
      where: { phone },
      update: {},
      create: { phone, identities: { create: { provider: 'PHONE', subject: phone } } },
    });
    await this.prisma.$transaction(async (tx) => {
      // Conditional update: a concurrent check-in or second transfer can't slip through
      const n = await tx.ticket.updateMany({
        where: { id: ticketId, holderUserId: userId, status: 'VALID', transferCount: { lt: TicketsService.MAX_TRANSFERS } },
        data: { holderUserId: to.id, qrVersion: { increment: 1 }, transferCount: { increment: 1 } },
      });
      if (n.count !== 1) throw new ConflictException('This ticket changed meanwhile; please refresh');
      await tx.ticketTransfer.create({ data: { ticketId, fromUserId: userId, toUserId: to.id } });
    });
    const from = t.holder.displayName || `${t.holder.phone?.slice(0, 6)}•••`;
    void this.notify.toUsers([to.id], {
      kind: 'ticket_received',
      title: 'You received a ticket',
      titleMy: 'လက်မှတ် လက်ခံရရှိပါသည်',
      body: `${from} sent you a ${t.ticketType.name} ticket for ${e.title}.`,
      bodyMy: `${from} က ${e.titleMy || e.title} အတွက် ${t.ticketType.nameMy || t.ticketType.name} လက်မှတ် ပေးပို့ထားပါသည်။`,
      link: '/tickets',
      eventId: e.id,
    });
    return { ok: true, to: `${phone.slice(0, 6)}•••${phone.slice(-3)}` };
  }

  async myTicket(userId: string, ticketId: string) {
    const all = await this.myTickets(userId);
    const t = all.find((x) => x.id === ticketId);
    if (!t) throw new NotFoundException('Ticket not found');
    return t;
  }
}
