import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { MicroCache, publicCacheMs } from '../../common/micro-cache';
import { mmk } from '../../common/util';
import { EDITABLE_STATUSES, needsReReview } from '../events/events.service';
import { NotifyService } from '../notifications/notify.service';
import { PrismaService } from '../prisma/prisma.service';
import { expandSeats, Layout } from './layout';
import { SeatMapsService } from './seat-maps.service';

export interface AssignmentRule {
  sectionKey: string;
  rowLabel?: string | null;
  ticketTypeId: string;
}

/** Index characters for GET /events/:id/seats `seatTypes`: one per seated ticket type. */
const TYPE_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
export const MAX_SEATED_TYPES = TYPE_CHARS.length;
/** Used when a ticket type has no colour of its own, by price order. */
export const SEAT_PALETTE = ['#f2b632', '#1f8a70', '#3b6fd8', '#c2410c', '#7c3aed', '#0891b2', '#be185d', '#4d7c0f'];
const STATUS_CHAR: Record<string, string> = { AVAILABLE: 'A', CHECKOUT_HOLD: 'T', SOLD: 'T', GUEST_HOLD: 'G', UNSOLD: 'U' };
const VISIBLE = ['PUBLISHED', 'ONGOING', 'COMPLETED', 'CANCELLED'] as const;

type Db = Prisma.TransactionClient;

@Injectable()
export class EventSeatsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly maps: SeatMapsService,
    private readonly notify: NotifyService,
  ) {}

  /** "<section> · Row <row> · Seat <seat>" in English and Myanmar, built like expandSeats does. */
  labelFor(seat: { sectionKey: string; rowLabel: string; seatLabel: string }, layout: Layout): { label: string; labelMy: string } {
    const sec = layout.sections.find((s) => s.key === seat.sectionKey);
    const name = sec?.name ?? seat.sectionKey;
    return {
      label: `${name} · Row ${seat.rowLabel} · Seat ${seat.seatLabel}`,
      labelMy: `${sec?.nameMy ?? name} · အတန်း ${seat.rowLabel} · ခုံ ${seat.seatLabel}`,
    };
  }

  /**
   * Sets quota, held and sold of the event's seated ticket types from event_seats (same transaction as the
   * seat change). Only types that have at least one seat (plus `alsoTypeIds`, e.g. types that just lost
   * their last seat) are touched; standing and unseated types keep the organizer's quota and counters.
   * quota = AVAILABLE + CHECKOUT_HOLD + SOLD seats; comps (SOLD seats whose ticket is complimentary) are
   * excluded from quota and sold; GUEST_HOLD seats are not for sale.
   */
  async recountTicketTypes(tx: Db, eventId: string, alsoTypeIds: string[] = []): Promise<void> {
    await tx.$executeRaw`
      UPDATE ticket_types tt SET quota = c.quota, held = c.held, sold = c.sold
      FROM (
        SELECT tt2.id,
          count(*) FILTER (WHERE s.status IN ('AVAILABLE', 'CHECKOUT_HOLD') OR (s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false)))::int AS quota,
          count(*) FILTER (WHERE s.status = 'CHECKOUT_HOLD')::int AS held,
          count(*) FILTER (WHERE s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false))::int AS sold
        FROM ticket_types tt2
        LEFT JOIN event_seats s ON s.ticket_type_id = tt2.id
        LEFT JOIN tickets t ON t.id = s.ticket_id
        WHERE tt2.event_id = ${eventId}::uuid
          AND (tt2.id = ANY(${alsoTypeIds}::uuid[]) OR EXISTS (SELECT 1 FROM event_seats x WHERE x.ticket_type_id = tt2.id))
        GROUP BY tt2.id
      ) c
      WHERE tt.id = c.id`;
  }

  // ───────────── Organizer: map ─────────────

  private async lockedEvent(tx: Db, orgId: string, eventId: string) {
    const rows = await tx.$queryRaw<{ id: string }[]>`SELECT id FROM events WHERE id = ${eventId}::uuid AND organization_id = ${orgId}::uuid FOR UPDATE`;
    if (!rows.length) throw new NotFoundException('Event not found');
    const e = await tx.event.findUniqueOrThrow({ where: { id: eventId }, include: { venue: true } });
    if (!EDITABLE_STATUSES.includes(e.status)) throw new ConflictException(`Cannot edit an event that is ${e.status}`);
    return e;
  }

  /** Deletes the event's seats and rules. Refuses (409, rolled back) if any seat is sold or held. */
  private async dropSeats(tx: Db, eventId: string) {
    await tx.eventSection.deleteMany({ where: { eventId } });
    await tx.eventSeat.deleteMany({ where: { eventId, status: { in: ['AVAILABLE', 'UNSOLD'] } } });
    if (await tx.eventSeat.count({ where: { eventId } })) throw new ConflictException('The map cannot change once seats are sold or held');
  }

  async setMap(orgId: string, eventId: string, seatMapVersionId: string, orgVerified: boolean) {
    const { id: versionId, layout, seatMap } = await this.maps.publishedVersion(seatMapVersionId);
    if (!seatMap.isActive) throw new BadRequestException('This venue map is not available');
    const seats = expandSeats(layout);
    const out = await this.prisma.$transaction(async (tx) => {
      const e = await this.lockedEvent(tx, orgId, eventId);
      if (e.seatMapVersionId === versionId) return { event: e, reReview: false, moved: false };
      const touched = await tx.ticketType.findMany({ where: { eventId, eventSeats: { some: {} } }, select: { id: true } });
      await this.dropSeats(tx, eventId);
      const venue = { name: seatMap.venueName, nameMy: seatMap.venueNameMy, address: seatMap.address, city: seatMap.city, latitude: seatMap.latitude, longitude: seatMap.longitude, mapUrl: seatMap.mapUrl };
      const venueId = e.venueId
        ? (await tx.venue.update({ where: { id: e.venueId }, data: venue })).id
        : (await tx.venue.create({ data: venue })).id;
      await tx.eventSeat.createMany({
        data: seats.map((s) => ({ eventId, seatKey: s.seatKey, sectionKey: s.sectionKey, rowLabel: s.rowLabel, seatLabel: s.seatLabel, label: this.labelFor(s, layout).label })),
      });
      const reReview = needsReReview(e.status, orgVerified, ['venue']);
      await tx.event.update({ where: { id: eventId }, data: { seatMapVersionId: versionId, venueId, ...(reReview ? { status: 'SUBMITTED', submittedAt: new Date() } : {}) } });
      await this.recountTicketTypes(tx, eventId, touched.map((t) => t.id));
      return { event: e, reReview, moved: this.place(e.venue) !== this.place(venue) };
    });
    await this.afterMapChange(eventId, out.event.publishedAt, out.moved);
    return this.result(eventId, out.reReview);
  }

  async clearMap(orgId: string, eventId: string, orgVerified: boolean) {
    const out = await this.prisma.$transaction(async (tx) => {
      const e = await this.lockedEvent(tx, orgId, eventId);
      if (!e.seatMapVersionId) return { event: e, reReview: false };
      const touched = await tx.ticketType.findMany({ where: { eventId, eventSeats: { some: {} } }, select: { id: true } });
      await this.dropSeats(tx, eventId);
      const reReview = needsReReview(e.status, orgVerified, ['venue']);
      await tx.event.update({ where: { id: eventId }, data: { seatMapVersionId: null, ...(reReview ? { status: 'SUBMITTED', submittedAt: new Date() } : {}) } });
      await this.recountTicketTypes(tx, eventId, touched.map((t) => t.id));
      return { event: e, reReview };
    });
    await this.afterMapChange(eventId, out.event.publishedAt, false);
    return this.result(eventId, out.reReview);
  }

  private place(v: { name?: string | null; address?: string | null; city?: string | null } | null | undefined) {
    return [v?.name, v?.address, v?.city].map((x) => x ?? '').join('|');
  }

  /** Ticket holders of a live listing hear about a new place, as with a venue edit. */
  private async afterMapChange(eventId: string, publishedAt: Date | null, moved: boolean) {
    if (!publishedAt || !moved) return;
    const e = await this.prisma.event.findUniqueOrThrow({ where: { id: eventId }, include: { venue: true } });
    void this.notify.eventChanged({ id: eventId, title: e.title, titleMy: e.titleMy, startsAt: e.startsAt, venue: e.venue?.name ?? null });
  }

  private async result(eventId: string, reReviewRequired: boolean) {
    const e = await this.prisma.event.findUniqueOrThrow({ where: { id: eventId }, include: { venue: true } });
    return {
      id: e.id,
      status: e.status,
      venue: e.venue,
      seating: e.seatMapVersionId ? { seatMapVersionId: e.seatMapVersionId, venueName: e.venue?.name ?? null } : null,
      reReviewRequired,
    };
  }

  // ───────────── Organizer: assignments ─────────────

  async setAssignments(orgId: string, eventId: string, rules: AssignmentRule[]) {
    await this.prisma.$transaction(async (tx) => {
      const e = await this.lockedEvent(tx, orgId, eventId);
      if (!e.seatMapVersionId) throw new ConflictException('This event has no seat map');
      const { layout } = await this.maps.publishedVersion(e.seatMapVersionId);
      const types = new Set((await tx.ticketType.findMany({ where: { eventId }, select: { id: true } })).map((t) => t.id));
      this.validateRules(rules, layout, types);
      const before = await tx.ticketType.findMany({ where: { eventId, eventSeats: { some: {} } }, select: { id: true } });
      await tx.eventSection.deleteMany({ where: { eventId } });
      await tx.eventSection.createMany({ data: rules.map((r) => ({ eventId, sectionKey: r.sectionKey, rowLabel: r.rowLabel ?? null, ticketTypeId: r.ticketTypeId })) });
      // Only seats nobody holds or owns follow the rules; SOLD and CHECKOUT_HOLD keep their type and price.
      await tx.$executeRaw`UPDATE event_seats SET ticket_type_id = NULL WHERE event_id = ${eventId}::uuid AND status IN ('AVAILABLE', 'UNSOLD', 'GUEST_HOLD')`;
      await tx.$executeRaw`
        UPDATE event_seats s SET ticket_type_id = r.ticket_type_id FROM event_sections r
        WHERE s.event_id = ${eventId}::uuid AND r.event_id = s.event_id AND r.section_key = s.section_key AND r.row_label IS NULL
          AND s.status IN ('AVAILABLE', 'UNSOLD', 'GUEST_HOLD')`;
      await tx.$executeRaw`
        UPDATE event_seats s SET ticket_type_id = r.ticket_type_id FROM event_sections r
        WHERE s.event_id = ${eventId}::uuid AND r.event_id = s.event_id AND r.section_key = s.section_key AND r.row_label = s.row_label
          AND s.status IN ('AVAILABLE', 'UNSOLD', 'GUEST_HOLD')`;
      await tx.$executeRaw`
        UPDATE event_seats SET status = CASE WHEN ticket_type_id IS NULL THEN 'UNSOLD'::"SeatStatus" ELSE 'AVAILABLE'::"SeatStatus" END
        WHERE event_id = ${eventId}::uuid AND status IN ('AVAILABLE', 'UNSOLD')`;
      await this.recountTicketTypes(tx, eventId, before.map((t) => t.id));
    });
    return this.result(eventId, false);
  }

  private validateRules(rules: AssignmentRule[], layout: Layout, eventTypes: Set<string>) {
    const seen = new Set<string>();
    const used = new Set<string>();
    for (const r of rules) {
      const sec = layout.sections.find((s) => s.key === r.sectionKey);
      if (!sec) throw new BadRequestException(`Unknown section "${r.sectionKey}"`);
      if (r.rowLabel != null) {
        if (sec.kind !== 'SEATED') throw new BadRequestException(`Section "${r.sectionKey}" is standing and has no rows`);
        if (!sec.rows?.some((row) => row.label === r.rowLabel)) throw new BadRequestException(`Unknown row "${r.rowLabel}" in section "${r.sectionKey}"`);
      }
      if (!eventTypes.has(r.ticketTypeId)) throw new BadRequestException('Unknown ticket type for this event');
      const k = JSON.stringify([r.sectionKey, r.rowLabel ?? null]);
      if (seen.has(k)) throw new BadRequestException(`More than one rule for section "${r.sectionKey}"${r.rowLabel != null ? ` row "${r.rowLabel}"` : ''}`);
      seen.add(k);
      if (sec.kind === 'SEATED') used.add(r.ticketTypeId);
    }
    if (used.size > MAX_SEATED_TYPES) throw new BadRequestException(`At most ${MAX_SEATED_TYPES} seated ticket types per event`);
  }

  /** Organizer view: layout, rules, per-type counts and every seat's state. Unseated events get an empty shape. */
  async overview(orgId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId: orgId } });
    if (!e) throw new NotFoundException('Event not found');
    if (!e.seatMapVersionId) return { layout: null, versionId: null, rules: [], counts: {}, seats: [] };
    const { layout } = await this.maps.publishedVersion(e.seatMapVersionId);
    const [rules, seats, counted] = await Promise.all([
      this.prisma.eventSection.findMany({ where: { eventId }, select: { sectionKey: true, rowLabel: true, ticketTypeId: true }, orderBy: [{ sectionKey: 'asc' }, { rowLabel: 'asc' }] }),
      this.prisma.eventSeat.findMany({ where: { eventId }, select: { seatKey: true, status: true, ticketTypeId: true, holdLabel: true } }),
      this.prisma.$queryRaw<{ ticket_type_id: string; available: number; held: number; guest: number; sold: number; comp: number }[]>`
        SELECT s.ticket_type_id,
          count(*) FILTER (WHERE s.status = 'AVAILABLE')::int AS available,
          count(*) FILTER (WHERE s.status = 'CHECKOUT_HOLD')::int AS held,
          count(*) FILTER (WHERE s.status = 'GUEST_HOLD')::int AS guest,
          count(*) FILTER (WHERE s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false))::int AS sold,
          count(*) FILTER (WHERE s.status = 'SOLD' AND COALESCE(t.is_complimentary, false))::int AS comp
        FROM event_seats s LEFT JOIN tickets t ON t.id = s.ticket_id
        WHERE s.event_id = ${eventId}::uuid AND s.ticket_type_id IS NOT NULL
        GROUP BY s.ticket_type_id`,
    ]);
    const order = new Map(expandSeats(layout).map((s, i) => [s.seatKey, i]));
    seats.sort((a, b) => (order.get(a.seatKey) ?? 0) - (order.get(b.seatKey) ?? 0));
    const counts: Record<string, { available: number; held: number; guest: number; sold: number; comp: number }> = {};
    for (const c of counted) counts[c.ticket_type_id] = { available: c.available, held: c.held, guest: c.guest, sold: c.sold, comp: c.comp };
    return { layout, versionId: e.seatMapVersionId, rules, counts, seats };
  }

  // ───────────── Public availability ─────────────

  /** Layout and seat order never change for a version; kept long. */
  private readonly layouts = new MicroCache<{ layout: Layout; index: Map<string, number> }>(publicCacheMs(3_600_000), 50);
  /** Types and seat status change with every order; kept at most 2 s per pod. */
  private readonly availability = new MicroCache<{ id: string; versionId: string; types: unknown[]; seatTypes: string; status: string }>(publicCacheMs(2000));

  async publicSeats(idOrSlug: string) {
    const a = await this.availability.get(idOrSlug, () => this.loadAvailability(idOrSlug));
    const { layout } = await this.layouts.get(a.versionId, () => this.loadLayout(a.versionId));
    return { versionId: a.versionId, layout, types: a.types, seatTypes: a.seatTypes, status: a.status };
  }

  private async loadLayout(versionId: string) {
    const { layout } = await this.maps.publishedVersion(versionId);
    return { layout, index: new Map(expandSeats(layout).map((s, i) => [s.seatKey, i] as const)) };
  }

  private async loadAvailability(idOrSlug: string) {
    const isUuid = /^[0-9a-f-]{36}$/i.test(idOrSlug);
    const e = await this.prisma.event.findFirst({
      where: { ...(isUuid ? { id: idOrSlug } : { slug: idOrSlug }), status: { in: [...VISIBLE] } },
      select: { id: true, seatMapVersionId: true },
    });
    if (!e || !e.seatMapVersionId) throw new NotFoundException('Seated event not found');
    const versionId = e.seatMapVersionId;
    const { index } = await this.layouts.get(versionId, () => this.loadLayout(versionId));
    const [types, seats] = await Promise.all([
      this.prisma.ticketType.findMany({ where: { eventId: e.id, eventSeats: { some: {} } }, orderBy: [{ priceMmk: 'asc' }, { id: 'asc' }] }),
      this.prisma.eventSeat.findMany({ where: { eventId: e.id }, select: { seatKey: true, ticketTypeId: true, status: true } }),
    ]);
    const typeIndex = new Map(types.map((t, i) => [t.id, i]));
    const seatTypes = new Array<string>(index.size).fill('-');
    const status = new Array<string>(index.size).fill('U');
    for (const s of seats) {
      const i = index.get(s.seatKey);
      if (i === undefined) continue;
      const ti = s.ticketTypeId ? typeIndex.get(s.ticketTypeId) : undefined;
      if (ti !== undefined && ti < MAX_SEATED_TYPES) seatTypes[i] = TYPE_CHARS[ti];
      status[i] = STATUS_CHAR[s.status] ?? 'U';
    }
    return {
      id: e.id,
      versionId,
      types: types.map((t, i) => ({ id: t.id, name: t.name, nameMy: t.nameMy, priceMmk: mmk(t.priceMmk), color: t.color ?? SEAT_PALETTE[i % SEAT_PALETTE.length] })),
      seatTypes: seatTypes.join(''),
      status: status.join(''),
    };
  }
}
