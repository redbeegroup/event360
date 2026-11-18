import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { Event, EventStatus, Prisma } from '@prisma/client';
import { makeSlug, mmk } from '../../common/util';
import { MediaService } from '../media/media.module';
import { PrismaService } from '../prisma/prisma.service';
import { CreateEventDto, ListEventsQuery, TicketTypeDto, UpdateEventDto, UpdateTicketTypeDto } from './events.dto';

/** Fields whose change on a published event needs re-review when the organizer is not verified. */
const REVIEWED_FIELDS: (keyof UpdateEventDto)[] = [
  'title', 'titleMy', 'summary', 'summaryMy', 'description', 'descriptionMy', 'coverImageKey', 'startsAt', 'endsAt', 'venue', 'categoryId',
];
const EDITABLE: EventStatus[] = ['DRAFT', 'SUBMITTED', 'REJECTED', 'PUBLISHED'];

const cardInclude = {
  category: { select: { id: true, slug: true, nameEn: true, nameMy: true, parent: { select: { slug: true, nameEn: true, nameMy: true } } } },
  venue: true,
  organization: { select: { id: true, name: true, slug: true, kycStatus: true } },
  ticketTypes: { orderBy: { priceMmk: 'asc' as const } },
} satisfies Prisma.EventInclude;
type EventWithRelations = Prisma.EventGetPayload<{ include: typeof cardInclude }>;

@Injectable()
export class EventsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly media: MediaService,
  ) {}

  // ───────────── Serialization ─────────────

  toDto(e: EventWithRelations, opts: { full?: boolean } = {}) {
    const tickets = e.ticketTypes.map((t) => ({
      id: t.id,
      name: t.name,
      nameMy: t.nameMy,
      priceMmk: mmk(t.priceMmk),
      quota: t.quota,
      remaining: Math.max(0, t.quota - t.sold - t.held),
      maxPerOrder: t.maxPerOrder,
      deliveryMode: t.deliveryMode,
      salesStartAt: t.salesStartAt,
      salesEndAt: t.salesEndAt,
      ...(opts.full ? { sold: t.sold } : {}),
    }));
    return {
      id: e.id,
      slug: e.slug,
      status: e.status,
      title: e.title,
      titleMy: e.titleMy,
      summary: e.summary,
      summaryMy: e.summaryMy,
      ...(opts.full ? { description: e.description, descriptionMy: e.descriptionMy, rejectionReason: e.rejectionReason } : {}),
      coverImageKey: e.coverImageUrl,
      coverImageUrl: this.media.url(e.coverImageUrl),
      format: e.format,
      visibility: e.visibility,
      isFree: e.isFree,
      minPriceMmk: tickets.length ? Math.min(...tickets.map((t) => t.priceMmk)) : null,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      publishedAt: e.publishedAt,
      category: e.category,
      venue: e.venue,
      organization: e.organization,
      ticketTypes: tickets,
      soldOut: tickets.length > 0 && tickets.every((t) => t.remaining === 0),
    };
  }

  // ───────────── Public ─────────────

  async listPublic(q: ListEventsQuery) {
    const page = q.page ?? 1;
    const limit = q.limit ?? 20;
    const where: Prisma.EventWhereInput = {
      status: 'PUBLISHED',
      visibility: 'PUBLIC',
      endsAt: { gte: q.from ? new Date(q.from) : new Date() },
      ...(q.to ? { startsAt: { lte: new Date(q.to) } } : {}),
      ...(q.free ? { isFree: q.free === 'true' } : {}),
      ...(q.format ? { format: q.format } : {}),
      ...(q.city ? { venue: { city: { equals: q.city, mode: 'insensitive' } } } : {}),
    };
    if (q.category) {
      const cat = await this.prisma.category.findUnique({ where: { slug: q.category }, include: { children: { select: { id: true } } } });
      if (!cat) return { items: [], page, limit, total: 0 };
      where.categoryId = { in: [cat.id, ...cat.children.map((c) => c.id)] };
    }
    if (q.q?.trim()) {
      const term = q.q.trim();
      where.OR = (['title', 'titleMy', 'summary', 'summaryMy'] as const).map((f) => ({ [f]: { contains: term, mode: 'insensitive' } }));
    }
    const [total, rows] = await Promise.all([
      this.prisma.event.count({ where }),
      this.prisma.event.findMany({ where, include: cardInclude, orderBy: { startsAt: 'asc' }, skip: (page - 1) * limit, take: limit }),
    ]);
    return { items: rows.map((e) => this.toDto(e)), page, limit, total };
  }

  /** Detail by id or slug. Private events are reachable by direct link, never listed. */
  async getPublic(idOrSlug: string) {
    const isUuid = /^[0-9a-f-]{36}$/i.test(idOrSlug);
    const e = await this.prisma.event.findFirst({
      where: { ...(isUuid ? { id: idOrSlug } : { slug: idOrSlug }), status: { in: ['PUBLISHED', 'ONGOING', 'COMPLETED', 'CANCELLED'] } },
      include: cardInclude,
    });
    if (!e) throw new NotFoundException('Event not found');
    return this.toDto(e, { full: true });
  }

  // ───────────── Organizer ─────────────

  listForOrg(organizationId: string) {
    return this.prisma.event
      .findMany({ where: { organizationId }, include: cardInclude, orderBy: { startsAt: 'desc' } })
      .then((rows) => rows.map((e) => this.toDto(e, { full: true })));
  }

  async getForOrg(organizationId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId }, include: cardInclude });
    if (!e) throw new NotFoundException('Event not found');
    return this.toDto(e, { full: true });
  }

  private validateDates(startsAt: Date, endsAt: Date) {
    if (endsAt <= startsAt) throw new BadRequestException('endsAt must be after startsAt');
  }

  private async assertCategory(categoryId: string) {
    const c = await this.prisma.category.findUnique({ where: { id: categoryId } });
    if (!c || !c.isActive) throw new BadRequestException('Unknown category');
  }

  async create(organizationId: string, dto: CreateEventDto) {
    await this.assertCategory(dto.categoryId);
    const startsAt = new Date(dto.startsAt);
    const endsAt = new Date(dto.endsAt);
    this.validateDates(startsAt, endsAt);
    if (dto.coverImageKey && !this.media.isOwnKey(dto.coverImageKey)) throw new BadRequestException('Invalid coverImageKey');
    const e = await this.prisma.event.create({
      data: {
        organization: { connect: { id: organizationId } },
        category: { connect: { id: dto.categoryId } },
        title: dto.title,
        titleMy: dto.titleMy,
        slug: makeSlug(dto.title),
        summary: dto.summary,
        summaryMy: dto.summaryMy,
        description: dto.description,
        descriptionMy: dto.descriptionMy,
        coverImageUrl: dto.coverImageKey,
        format: dto.format,
        visibility: dto.visibility ?? 'PUBLIC',
        startsAt,
        endsAt,
        ...(dto.venue ? { venue: { create: dto.venue } } : {}),
      },
      include: cardInclude,
    });
    return this.toDto(e, { full: true });
  }

  async update(organizationId: string, id: string, dto: UpdateEventDto, orgVerified: boolean) {
    const current = await this.prisma.event.findFirst({ where: { id, organizationId } });
    if (!current) throw new NotFoundException('Event not found');
    if (!EDITABLE.includes(current.status)) throw new ConflictException(`Cannot edit an event that is ${current.status}`);
    if (dto.categoryId) await this.assertCategory(dto.categoryId);
    if (dto.coverImageKey && !this.media.isOwnKey(dto.coverImageKey)) throw new BadRequestException('Invalid coverImageKey');
    const startsAt = dto.startsAt ? new Date(dto.startsAt) : current.startsAt;
    const endsAt = dto.endsAt ? new Date(dto.endsAt) : current.endsAt;
    this.validateDates(startsAt, endsAt);

    const needsReview =
      current.status === 'PUBLISHED' && !orgVerified && REVIEWED_FIELDS.some((f) => (dto as Record<string, unknown>)[f] !== undefined);
    const { venue, coverImageKey, categoryId, startsAt: _s, endsAt: _e, ...rest } = dto;
    const data: Prisma.EventUpdateInput = {
      ...rest,
      ...(categoryId ? { category: { connect: { id: categoryId } } } : {}),
      ...(coverImageKey !== undefined ? { coverImageUrl: coverImageKey } : {}),
      startsAt,
      endsAt,
      ...(needsReview ? { status: 'SUBMITTED', submittedAt: new Date() } : {}),
    };
    if (venue) {
      data.venue = current.venueId ? { update: venue } : { create: venue };
    }
    const e = await this.prisma.event.update({ where: { id }, data, include: cardInclude });
    return { ...this.toDto(e, { full: true }), reReviewRequired: needsReview };
  }

  private async recomputeIsFree(eventId: string) {
    const types = await this.prisma.ticketType.findMany({ where: { eventId }, select: { priceMmk: true } });
    await this.prisma.event.update({ where: { id: eventId }, data: { isFree: types.length > 0 && types.every((t) => t.priceMmk === 0n) } });
  }

  private async eventOf(organizationId: string, eventId: string): Promise<Event> {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId } });
    if (!e) throw new NotFoundException('Event not found');
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException(`Event is ${e.status}`);
    return e;
  }

  async addTicketType(organizationId: string, eventId: string, dto: TicketTypeDto) {
    await this.eventOf(organizationId, eventId);
    const t = await this.prisma.ticketType.create({
      data: {
        eventId,
        name: dto.name,
        nameMy: dto.nameMy,
        priceMmk: BigInt(dto.priceMmk),
        quota: dto.quota,
        maxPerOrder: dto.maxPerOrder ?? 10,
        deliveryMode: dto.deliveryMode ?? 'IN_PERSON',
        salesStartAt: dto.salesStartAt ? new Date(dto.salesStartAt) : null,
        salesEndAt: dto.salesEndAt ? new Date(dto.salesEndAt) : null,
      },
    });
    await this.recomputeIsFree(eventId);
    return { ...t, priceMmk: mmk(t.priceMmk) };
  }

  async updateTicketType(organizationId: string, eventId: string, ticketTypeId: string, dto: UpdateTicketTypeDto) {
    await this.eventOf(organizationId, eventId);
    const t = await this.prisma.ticketType.findFirst({ where: { id: ticketTypeId, eventId } });
    if (!t) throw new NotFoundException('Ticket type not found');
    if (dto.quota !== undefined && dto.quota < t.sold + t.held) throw new BadRequestException(`Quota cannot be below the ${t.sold + t.held} tickets already issued`);
    if (dto.priceMmk !== undefined && t.sold > 0 && BigInt(dto.priceMmk) !== t.priceMmk) throw new ConflictException('Price cannot change after tickets are issued');
    const updated = await this.prisma.ticketType.update({
      where: { id: ticketTypeId },
      data: {
        name: dto.name,
        nameMy: dto.nameMy,
        priceMmk: dto.priceMmk !== undefined ? BigInt(dto.priceMmk) : undefined,
        quota: dto.quota,
        maxPerOrder: dto.maxPerOrder,
        deliveryMode: dto.deliveryMode,
        salesStartAt: dto.salesStartAt !== undefined ? new Date(dto.salesStartAt) : undefined,
        salesEndAt: dto.salesEndAt !== undefined ? new Date(dto.salesEndAt) : undefined,
      },
    });
    await this.recomputeIsFree(eventId);
    return { ...updated, priceMmk: mmk(updated.priceMmk) };
  }

  async deleteTicketType(organizationId: string, eventId: string, ticketTypeId: string) {
    await this.eventOf(organizationId, eventId);
    const t = await this.prisma.ticketType.findFirst({ where: { id: ticketTypeId, eventId } });
    if (!t) throw new NotFoundException('Ticket type not found');
    if (t.sold + t.held > 0) throw new ConflictException('Tickets were already issued for this type');
    await this.prisma.ticketType.delete({ where: { id: ticketTypeId } });
    await this.recomputeIsFree(eventId);
    return { deleted: true };
  }

  /** Verified organizers publish directly; others go to the admin review queue. */
  async submit(organizationId: string, id: string, orgVerified: boolean) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId }, include: { ticketTypes: true, venue: true } });
    if (!e) throw new NotFoundException('Event not found');
    if (!['DRAFT', 'REJECTED'].includes(e.status)) throw new ConflictException(`Cannot submit an event that is ${e.status}`);
    const problems: string[] = [];
    if (e.ticketTypes.length === 0) problems.push('Add at least one ticket type');
    if (e.endsAt <= new Date()) problems.push('Event has already ended');
    if (e.format !== 'ONLINE' && !e.venue) problems.push('In-person and hybrid events need a venue');
    if (problems.length) throw new BadRequestException({ message: 'Event is not ready', problems });
    const now = new Date();
    const updated = await this.prisma.event.update({
      where: { id },
      data: orgVerified
        ? { status: 'PUBLISHED', publishedAt: now, submittedAt: now, rejectionReason: null }
        : { status: 'SUBMITTED', submittedAt: now, rejectionReason: null },
      include: cardInclude,
    });
    return this.toDto(updated, { full: true });
  }

  async cancel(organizationId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId } });
    if (!e) throw new NotFoundException('Event not found');
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException(`Event is already ${e.status}`);
    // Ticket holders are notified in a later phase (notifications module).
    const updated = await this.prisma.event.update({ where: { id }, data: { status: 'CANCELLED' }, include: cardInclude });
    return this.toDto(updated, { full: true });
  }

  attendees(organizationId: string, eventId: string) {
    return this.prisma.ticket.findMany({
      where: { ticketType: { event: { id: eventId, organizationId } } },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        status: true,
        createdAt: true,
        ticketType: { select: { id: true, name: true } },
        holder: { select: { id: true, displayName: true, phone: true } },
      },
    });
  }

  // ───────────── Admin moderation ─────────────

  listForAdmin(status: EventStatus) {
    return this.prisma.event
      .findMany({ where: { status }, include: cardInclude, orderBy: { submittedAt: 'asc' } })
      .then((rows) => rows.map((e) => this.toDto(e, { full: true })));
  }

  async approve(id: string) {
    const e = await this.prisma.event.findUnique({ where: { id } });
    if (!e) throw new NotFoundException('Event not found');
    if (e.status !== 'SUBMITTED') throw new ConflictException(`Only SUBMITTED events can be approved (is ${e.status})`);
    const updated = await this.prisma.event.update({
      where: { id },
      data: { status: 'PUBLISHED', publishedAt: e.publishedAt ?? new Date(), rejectionReason: null },
      include: cardInclude,
    });
    return this.toDto(updated, { full: true });
  }

  /** Reject a submission, or take down a published event. */
  async reject(id: string, reason: string) {
    const e = await this.prisma.event.findUnique({ where: { id } });
    if (!e) throw new NotFoundException('Event not found');
    if (!['SUBMITTED', 'PUBLISHED'].includes(e.status)) throw new ConflictException(`Cannot reject an event that is ${e.status}`);
    const updated = await this.prisma.event.update({ where: { id }, data: { status: 'REJECTED', rejectionReason: reason }, include: cardInclude });
    return this.toDto(updated, { full: true });
  }
}
