import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
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
      };
    });
  }

  async myTicket(userId: string, ticketId: string) {
    const all = await this.myTickets(userId);
    const t = all.find((x) => x.id === ticketId);
    if (!t) throw new NotFoundException('Ticket not found');
    return t;
  }
}
