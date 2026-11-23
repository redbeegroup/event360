import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { maskPhone } from '../../common/util';
import { normalizeMyanmarPhone, upsertUserByPhone } from '../auth/phone';
import { NotifyService } from '../notifications/notify.service';
import { PrismaService } from '../prisma/prisma.service';
import { TicketTokenService } from '../tickets/ticket-token.service';
import { EventSeatsService } from './event-seats.service';
import { CURRENT_RULE_TYPE, returnSeatsToSale } from './seat-claims';
import { PdfTicket, renderTicketsPdf } from './ticket-pdf';

type Tx = Prisma.TransactionClient;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const taken = (message: string, takenSeats: string[], reasonCode: string) => new ConflictException({ message, takenSeats, reasonCode });

/**
 * Organizer seat-state changes for guests: hold seats off sale, release them, issue complimentary tickets
 * (a zero-total order with channel COMP) and revoke them. Like seat assignments these take the event row
 * FOR UPDATE, so they exclude every checkout (FOR SHARE) for the duration. Comps stay out of quota/sold
 * (EventSeatsService.recountTicketTypes), revenue figures and milestones, and write no ledger entries.
 */
@Injectable()
export class GuestsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly seats: EventSeatsService,
    private readonly notify: NotifyService,
    private readonly tokens: TicketTokenService,
  ) {}

  private async lockedEvent(tx: Tx, orgId: string, eventId: string) {
    const rows = await tx.$queryRaw<{ id: string }[]>`SELECT id FROM events WHERE id = ${eventId}::uuid AND organization_id = ${orgId}::uuid FOR UPDATE`;
    if (!rows.length) throw new NotFoundException('Event not found');
    const e = await tx.event.findUniqueOrThrow({ where: { id: eventId } });
    if (!e.seatMapVersionId) throw new ConflictException({ message: 'This event has no seat map', reasonCode: 'NO_SEAT_MAP' });
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException({ message: `Event is already ${e.status}`, reasonCode: 'EVENT_ENDED' });
    return e;
  }

  private keys(seats: string[]) {
    return [...new Set(seats)];
  }

  async hold(orgId: string, eventId: string, seats: string[], label: string) {
    const keys = this.keys(seats);
    await this.prisma.$transaction(async (tx) => {
      await this.lockedEvent(tx, orgId, eventId);
      const rows = await tx.$queryRaw<{ seat_key: string; ticket_type_id: string | null }[]>`
        UPDATE event_seats SET status = 'GUEST_HOLD', hold_label = ${label}
        WHERE id IN (
          SELECT id FROM event_seats
          WHERE event_id = ${eventId}::uuid AND seat_key = ANY(${keys}::text[]) AND status = 'AVAILABLE'
          ORDER BY seat_key FOR UPDATE
        ) AND status = 'AVAILABLE'
        RETURNING seat_key, ticket_type_id`;
      if (rows.length !== keys.length) {
        const got = new Set(rows.map((r) => r.seat_key));
        throw taken('Some seats are not available', keys.filter((k) => !got.has(k)), 'SEATS_NOT_AVAILABLE');
      }
      await this.seats.recountTicketTypes(tx, eventId, rows.map((r) => r.ticket_type_id).filter((x): x is string => !!x));
    });
    return { held: keys.length };
  }

  async release(orgId: string, eventId: string, seats: string[]) {
    const keys = this.keys(seats);
    await this.prisma.$transaction(async (tx) => {
      await this.lockedEvent(tx, orgId, eventId);
      // Back on sale under the current rules: a seat whose row or section lost its rule becomes UNSOLD
      const back = await returnSeatsToSale(tx, Prisma.sql`event_id = ${eventId}::uuid AND seat_key = ANY(${keys}::text[]) AND status = 'GUEST_HOLD'`);
      if (back.seatKeys.length !== keys.length) {
        const got = new Set(back.seatKeys);
        throw taken('Some seats are not held for guests', keys.filter((k) => !got.has(k)), 'SEATS_NOT_HELD');
      }
      await this.seats.recountTicketTypes(tx, eventId, back.typeIds);
    });
    return { released: keys.length };
  }

  async issue(orgId: string, eventId: string, dto: { seats: string[]; guestName: string; phone: string; label?: string }) {
    const phone = normalizeMyanmarPhone(dto.phone);
    if (!phone) throw new BadRequestException('Enter a valid Myanmar mobile number');
    const keys = this.keys(dto.seats);
    const out = await this.prisma.$transaction(async (tx) => {
      // The guest's user row before the event row, as in checkout (user → event): the guest may be buying a
      // ticket for this event right now, and their order row references the same user
      const guest = await upsertUserByPhone(tx, phone);
      await tx.$queryRaw`SELECT id FROM users WHERE id = ${guest.id}::uuid FOR NO KEY UPDATE`;
      const e = await this.lockedEvent(tx, orgId, eventId);
      const rows = await tx.eventSeat.findMany({ where: { eventId, seatKey: { in: keys } }, orderBy: { seatKey: 'asc' } });
      const ok = rows.filter((s) => s.status === 'GUEST_HOLD' && s.ticketTypeId);
      if (ok.length !== keys.length) {
        const good = new Set(ok.map((s) => s.seatKey));
        throw taken('Seats must be held for guests first', keys.filter((k) => !good.has(k)), 'SEATS_MUST_BE_HELD_FIRST');
      }
      const perType = new Map<string, number>();
      for (const s of ok) perType.set(s.ticketTypeId!, (perType.get(s.ticketTypeId!) ?? 0) + 1);
      const order = await tx.order.create({
        data: {
          userId: guest.id,
          eventId,
          status: 'CONFIRMED',
          channel: 'COMP',
          subtotalMmk: 0n,
          totalMmk: 0n,
          commissionMmk: 0n,
          items: { create: [...perType].map(([ticketTypeId, quantity]) => ({ ticketTypeId, quantity, unitPriceMmk: 0n })) },
        },
      });
      const tickets: { id: string; seatKey: string; seatLabel: string }[] = [];
      for (const s of ok) {
        const t = await tx.ticket.create({
          data: {
            orderId: order.id,
            ticketTypeId: s.ticketTypeId!,
            holderUserId: guest.id,
            seatKey: s.seatKey,
            seatLabel: s.label,
            seatLabelMy: s.labelMy,
            isComplimentary: true,
            compLabel: dto.label || s.holdLabel || 'Guest',
            guestName: dto.guestName,
          },
        });
        const n = await tx.eventSeat.updateMany({ where: { id: s.id, status: 'GUEST_HOLD' }, data: { status: 'SOLD', orderId: order.id, ticketId: t.id, holdLabel: null, heldUntil: null } });
        if (n.count !== 1) throw taken('Seats must be held for guests first', [s.seatKey], 'SEATS_MUST_BE_HELD_FIRST');
        tickets.push({ id: t.id, seatKey: s.seatKey, seatLabel: s.label });
      }
      await this.seats.recountTicketTypes(tx, eventId, [...perType.keys()]);
      return { orderId: order.id, guestId: guest.id, tickets, event: e };
    });
    // Inbox and push only: guest tickets never send SMS
    const e = out.event;
    const seatsText = out.tickets.map((t) => t.seatLabel).join('; ');
    void this.notify.toUsers([out.guestId], {
      kind: 'ticket_received',
      title: 'You received a ticket',
      titleMy: 'လက်မှတ် လက်ခံရရှိပါသည်',
      body: `You have a complimentary ticket for ${e.title} (${seatsText}).`,
      bodyMy: `${e.titleMy || e.title} အတွက် အခမဲ့ လက်မှတ် ရရှိပါသည် (${seatsText})။`,
      link: '/tickets',
      eventId,
    });
    return { orderId: out.orderId, tickets: out.tickets };
  }

  async list(orgId: string, eventId: string) {
    await this.assertEvent(orgId, eventId);
    const rows = await this.prisma.ticket.findMany({
      where: { isComplimentary: true, ticketType: { eventId } },
      orderBy: [{ createdAt: 'asc' }, { seatKey: 'asc' }],
      include: { holder: { select: { phone: true } } },
    });
    return rows.map((t) => ({
      id: t.id,
      guestName: t.guestName,
      phone: maskPhone(t.holder.phone),
      seatKey: t.seatKey,
      seatLabel: t.seatLabel,
      seatLabelMy: t.seatLabelMy,
      label: t.compLabel,
      status: t.status,
      checkedIn: t.status === 'CHECKED_IN',
      orderId: t.orderId,
      createdAt: t.createdAt,
    }));
  }

  private async assertEvent(orgId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId: orgId }, include: { venue: true } });
    if (!e) throw new NotFoundException('Event not found');
    return e;
  }

  /** The ticket becomes VOID (its QR dies with it) and the seat goes back to GUEST_HOLD under the comp's label, as the type the current rules give it. */
  async revoke(orgId: string, eventId: string, ticketId: string) {
    await this.prisma.$transaction(async (tx) => {
      await this.lockedEvent(tx, orgId, eventId);
      const t = await tx.ticket.findFirst({ where: { id: ticketId, isComplimentary: true, ticketType: { eventId } } });
      if (!t) throw new NotFoundException({ message: 'Guest ticket not found', reasonCode: 'GUEST_TICKET_NOT_FOUND' });
      if (t.status === 'CHECKED_IN') throw new ConflictException({ message: 'This guest has already checked in', reasonCode: 'GUEST_ALREADY_CHECKED_IN' });
      if (t.status !== 'VALID') throw new ConflictException({ message: 'This ticket was already revoked', reasonCode: 'GUEST_ALREADY_REVOKED' });
      // Conditional: a gate check-in that committed meanwhile must win
      const n = await tx.ticket.updateMany({ where: { id: t.id, status: 'VALID' }, data: { status: 'VOID', qrVersion: { increment: 1 } } });
      if (n.count !== 1) throw new ConflictException({ message: 'This guest has already checked in', reasonCode: 'GUEST_ALREADY_CHECKED_IN' });
      // Back to GUEST_HOLD under the comp's label, as whatever type the current rules give the seat (rules may have changed)
      const back = await tx.$queryRaw<{ old_type: string | null; new_type: string | null }[]>`
        WITH s AS (
          SELECT seat.id, seat.ticket_type_id AS old_type, ${CURRENT_RULE_TYPE} AS new_type
          FROM event_seats seat WHERE seat.ticket_id = ${t.id}::uuid
          FOR UPDATE OF seat
        )
        UPDATE event_seats e SET status = 'GUEST_HOLD', hold_label = ${t.compLabel}, ticket_type_id = s.new_type, ticket_id = NULL, order_id = NULL, held_until = NULL
        FROM s WHERE e.id = s.id
        RETURNING s.old_type::text AS old_type, s.new_type::text AS new_type`;
      const live = await tx.ticket.count({ where: { orderId: t.orderId, status: { not: 'VOID' } } });
      if (!live) await tx.order.update({ where: { id: t.orderId }, data: { status: 'CANCELLED' } });
      const types = new Set([t.ticketTypeId, ...back.flatMap((r) => [r.old_type, r.new_type])].filter((x): x is string => !!x));
      await this.seats.recountTicketTypes(tx, eventId, [...types]);
    });
    return { ok: true };
  }

  /** VALID comp tickets of the event (optionally limited to `ids`, comma-separated ticket ids), with their signed QR tokens. */
  private async printable(orgId: string, eventId: string, ids?: string) {
    const e = await this.assertEvent(orgId, eventId);
    let only: string[] | undefined;
    if (ids !== undefined && ids !== '') {
      only = ids.split(',').map((s) => s.trim()).filter(Boolean);
      if (!only.length || only.some((s) => !UUID.test(s))) throw new BadRequestException('ids must be a comma-separated list of ticket ids');
    }
    const rows = await this.prisma.ticket.findMany({
      where: { isComplimentary: true, status: 'VALID', ticketType: { eventId }, ...(only ? { id: { in: only } } : {}) },
      orderBy: [{ seatKey: 'asc' }, { createdAt: 'asc' }],
      include: { holder: { select: { phone: true } } },
    });
    if (!rows.length) throw new NotFoundException('No guest tickets to print');
    const venue = e.venue ? [e.venue.name, e.venue.city].filter(Boolean).join(', ') : '';
    const venueMy = e.venue ? [e.venue.nameMy || e.venue.name, e.venue.city].filter(Boolean).join(', ') : '';
    const tickets = rows.map((t) => ({
      id: t.id,
      guestName: t.guestName ?? '',
      phoneHint: maskPhone(t.holder.phone) ?? '',
      seatLabel: t.seatLabel ?? '',
      seatLabelMy: t.seatLabelMy,
      compLabel: t.compLabel ?? '',
      token: this.tokens.sign({ tid: t.id, eid: e.id, tt: t.ticketTypeId, v: t.qrVersion }),
      code: t.id.slice(0, 8).toUpperCase(),
    }));
    return { e, venue, venueMy, tickets };
  }

  /** Data for the portal's print page (it renders Myanmar script, which the PDF cannot). Same guard as comps.pdf: live QR tokens. */
  async printData(orgId: string, eventId: string, ids?: string) {
    const { e, venue, venueMy, tickets } = await this.printable(orgId, eventId, ids);
    return { event: { title: e.title, titleMy: e.titleMy, startsAt: e.startsAt, venue, venueMy }, tickets };
  }

  /** One A5 page per ticket; `ids` (comma-separated ticket ids) limits it, otherwise every live comp of the event. */
  async pdf(orgId: string, eventId: string, ids?: string): Promise<Buffer> {
    const { e, venue, tickets } = await this.printable(orgId, eventId, ids);
    const items: PdfTicket[] = tickets.map((t) => ({ title: e.title, titleMy: e.titleMy, startsAt: e.startsAt, venue, ...t }));
    return renderTicketsPdf(items);
  }
}
