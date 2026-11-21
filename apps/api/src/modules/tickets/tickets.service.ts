import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import { Prisma } from '@prisma/client';
import { EventSeatsService } from '../seating/event-seats.service';
import { normalizeMyanmarPhone, upsertUserByPhone } from '../auth/phone';
import { mmk } from '../../common/util';
import { MediaService } from '../media/media.module';
import { NotifyService } from '../notifications/notify.service';
import { returnSeatsToSale, SEATED_TX, shareLockEvent } from '../seating/seat-claims';
import { PrismaService } from '../prisma/prisma.service';
import { TicketTokenService } from './ticket-token.service';

@Injectable()
export class TicketsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TicketTokenService,
    private readonly media: MediaService,
    private readonly notify: NotifyService,
    private readonly moduleRef: ModuleRef,
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
    // Seated types are sold seat by seat through checkout (their quota is recounted from event_seats)
    if (await this.prisma.eventSeat.findFirst({ where: { eventId, ticketTypeId }, select: { id: true } })) throw new BadRequestException('Seated tickets are bought by choosing seats');

    const result = await this.prisma.$transaction(async (tx) => {
      // Seated event: share-lock the event row so seat assignments can't change during this registration
      if (e.seatMapVersionId) await shareLockEvent(tx, eventId);
      const already = await tx.ticket.count({ where: { holderUserId: userId, ticketTypeId, isComplimentary: false, status: { in: ['VALID', 'CHECKED_IN'] } } });
      if (already + quantity > tt.maxPerOrder) {
        throw new ConflictException(`You already hold ${already} ticket(s); the limit is ${tt.maxPerOrder} per person`);
      }
      const reserved = await tx.$executeRaw`
        UPDATE ticket_types SET sold = sold + ${quantity}
        WHERE id = ${ticketTypeId}::uuid AND sold + held + ${quantity} <= quota`;
      if (reserved !== 1) throw new ConflictException('Not enough tickets left');
      // Checked again with the counter row locked (see PaymentsService.createOrder)
      if (await tx.eventSeat.findFirst({ where: { eventId, ticketTypeId }, select: { id: true } })) throw new BadRequestException('Seated tickets are bought by choosing seats');

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
        order: { select: { totalMmk: true, channel: true } },
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
        seatKey: t.seatKey,
        seatLabel: t.seatLabel,
        seatLabelMy: t.seatLabelMy,
        isComplimentary: t.isComplimentary,
        compLabel: t.compLabel,
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
        canCancel: TicketsService.cancelBlock(t, t.order, e) === null,
        canTransfer:
          t.status === 'VALID' &&
          !t.isComplimentary &&
          e.transfersEnabled &&
          !['CANCELLED', 'COMPLETED'].includes(e.status) &&
          t.transferCount < TicketsService.MAX_TRANSFERS &&
          Date.now() < e.startsAt.getTime() - e.transferCutoffHours * 3600e3,
      };
    });
  }

  static readonly MAX_TRANSFERS = 3;

  /** Why an attendee cannot cancel this ticket (null = allowed): free, own, valid, not a guest ticket, before the event starts. */
  private static cancelBlock(
    t: { status: string; isComplimentary: boolean },
    o: { totalMmk: bigint; channel: string },
    e: { startsAt: Date },
  ): string | null {
    if (t.isComplimentary || o.channel === 'COMP') return "Guest tickets can't be cancelled by the holder";
    if (o.totalMmk !== 0n) return 'Paid tickets cannot be cancelled here; contact the organizer for a refund';
    if (t.status !== 'VALID') return t.status === 'CHECKED_IN' ? 'This ticket has already been used' : 'This ticket is no longer valid';
    if (Date.now() >= e.startsAt.getTime()) return 'The event has already started';
    return null;
  }

  /**
   * Attendee gives back a free ticket before the event starts. A checkout-like path: shares the event row lock
   * with other checkouts and uses conditional updates, so a concurrent check-in, transfer or second cancel can't
   * double-release. Seated: the seat goes back on sale and the type is recounted; unseated: sold -= 1.
   */
  async cancel(userId: string, ticketId: string) {
    const t = await this.prisma.ticket.findUnique({ where: { id: ticketId }, include: { order: { select: { id: true, totalMmk: true, channel: true, promoCodeId: true } }, ticketType: { include: { event: true } } } });
    if (!t || t.holderUserId !== userId) throw new NotFoundException('Ticket not found');
    const e = t.ticketType.event;
    const why = TicketsService.cancelBlock(t, t.order, e);
    if (why) throw new ConflictException(why);
    await this.prisma.$transaction(async (tx) => {
      await shareLockEvent(tx, e.id);
      const n = await tx.ticket.updateMany({
        where: { id: ticketId, holderUserId: userId, status: 'VALID', isComplimentary: false },
        data: { status: 'VOID', qrVersion: { increment: 1 } },
      });
      if (n.count !== 1) throw new ConflictException('This ticket changed meanwhile; please refresh');
      if (t.seatKey) {
        // Back on sale under the current rules (another type, or UNSOLD, if they changed since the sale)
        const back = await returnSeatsToSale(tx, Prisma.sql`ticket_id = ${ticketId}::uuid AND status = 'SOLD'`);
        await this.moduleRef.get(EventSeatsService, { strict: false }).recountTicketTypes(tx, e.id, back.typeIds, [...new Set([t.ticketTypeId, ...back.typeIds])]);
      } else {
        await tx.$executeRaw`UPDATE ticket_types SET sold = GREATEST(sold - 1, 0) WHERE id = ${t.ticketTypeId}::uuid`;
      }
      // Serialise cancels within one order so the last one to commit sees every VOID and cancels the order
      await tx.$queryRaw`SELECT id FROM orders WHERE id = ${t.orderId}::uuid FOR UPDATE`;
      if ((await tx.ticket.count({ where: { orderId: t.orderId, status: { not: 'VOID' } } })) === 0) {
        const closed = await tx.order.updateMany({ where: { id: t.orderId, status: { in: ['PAID', 'CONFIRMED'] } }, data: { status: 'CANCELLED' } });
        // A fully cancelled free order gives its promo use back (once: only the call that flipped the status)
        if (closed.count === 1 && t.order.promoCodeId) {
          await tx.$executeRaw`UPDATE promo_codes SET used = GREATEST(used - 1, 0) WHERE id = ${t.order.promoCodeId}::uuid`;
        }
      }
    }, t.seatKey || e.seatMapVersionId ? SEATED_TX : undefined);
    return { ok: true };
  }

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
    if (t.isComplimentary) throw new ConflictException("Guest tickets can't be transferred");
    if (t.status !== 'VALID') throw new ConflictException(t.status === 'CHECKED_IN' ? 'This ticket has already been used' : 'This ticket can no longer be transferred');
    if (!e.transfersEnabled) throw new ForbiddenException('The organizer does not allow ticket transfers for this event');
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException('This event is no longer running');
    if (Date.now() > e.startsAt.getTime() - e.transferCutoffHours * 3600e3) {
      throw new ConflictException(e.transferCutoffHours ? `Transfers close ${e.transferCutoffHours} hour(s) before the event starts` : 'Transfers are closed for this event');
    }
    if (t.transferCount >= TicketsService.MAX_TRANSFERS) throw new ConflictException(`A ticket can be transferred at most ${TicketsService.MAX_TRANSFERS} times`);
    if (t.holder.phone === phone) throw new BadRequestException('This ticket is already yours');

    const to = await upsertUserByPhone(this.prisma, phone);
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
