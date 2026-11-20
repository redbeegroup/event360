import { BadRequestException, ConflictException, Injectable, NotFoundException, OnModuleDestroy } from '@nestjs/common';
import type { Event, EventStatus, Prisma } from '@prisma/client';
import { makeSlug, mmk } from '../../common/util';
import { MediaService } from '../media/media.module';
import { NotifyService } from '../notifications/notify.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateEventDto,
  FaqItemDto,
  ListEventsQuery,
  MediaItemDto,
  OrgProfileDto,
  PerformerItemDto,
  SessionItemDto,
  TicketTypeDto,
  UpdateEventDto,
  UpdateTicketTypeDto,
} from './events.dto';

/** Fields whose change on a published event needs re-review when the organizer is not verified. */
const REVIEWED_FIELDS: (keyof UpdateEventDto)[] = [
  'title', 'titleMy', 'summary', 'summaryMy', 'description', 'descriptionMy', 'coverImageKey', 'startsAt', 'endsAt', 'venue', 'categoryId',
  'dressCode', 'dressCodeMy', 'languages', 'languagesMy', 'parking', 'parkingMy', 'accessibility', 'accessibilityMy',
  'whatToBring', 'whatToBringMy', 'terms', 'termsMy', 'refundPolicy', 'refundPolicyMy', 'ageMin',
];
const EDITABLE: EventStatus[] = ['DRAFT', 'SUBMITTED', 'REJECTED', 'PUBLISHED'];

const cardInclude = {
  category: { select: { id: true, slug: true, nameEn: true, nameMy: true, parent: { select: { slug: true, nameEn: true, nameMy: true } } } },
  venue: true,
  organization: { select: { id: true, name: true, slug: true, kycStatus: true, logoUrl: true } },
  ticketTypes: { orderBy: { priceMmk: 'asc' as const } },
} satisfies Prisma.EventInclude;
type EventWithRelations = Prisma.EventGetPayload<{ include: typeof cardInclude }>;

/** Single-event views also load schedule, lineup, gallery and FAQ. */
const fullInclude = {
  ...cardInclude,
  sessions: { orderBy: { startsAt: 'asc' as const } },
  performers: { orderBy: { sortOrder: 'asc' as const } },
  media: { orderBy: { sortOrder: 'asc' as const } },
  faqs: { orderBy: { sortOrder: 'asc' as const } },
} satisfies Prisma.EventInclude;
type EventFull = Prisma.EventGetPayload<{ include: typeof fullInclude }>;

const pick = <T extends object, K extends keyof T>(o: T, keys: readonly K[]) =>
  Object.fromEntries(keys.map((k) => [k, o[k]])) as Pick<T, K>;
const PRACTICAL = [
  'ageMin', 'dressCode', 'dressCodeMy', 'languages', 'languagesMy', 'parking', 'parkingMy',
  'accessibility', 'accessibilityMy', 'whatToBring', 'whatToBringMy', 'terms', 'termsMy', 'refundPolicy', 'refundPolicyMy',
] as const;

@Injectable()
export class EventsService implements OnModuleDestroy {
  constructor(
    private readonly prisma: PrismaService,
    private readonly media: MediaService,
    private readonly notify: NotifyService,
  ) {}

  // ───────────── Serialization ─────────────

  toDto(e: EventWithRelations | EventFull, opts: { full?: boolean } = {}) {
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
      organization: { ...e.organization, logoUrl: this.media.url(e.organization.logoUrl) },
      ...(opts.full ? this.details(e) : {}),
      ticketTypes: tickets,
      soldOut: tickets.length > 0 && tickets.every((t) => t.remaining === 0),
      transfersEnabled: e.transfersEnabled,
      transferCutoffHours: e.transferCutoffHours,
    };
  }

  /** Practical info, terms and (when loaded) schedule, lineup, gallery, FAQ. */
  private details(e: EventWithRelations | EventFull) {
    const full = 'sessions' in e ? e : null;
    return {
      ...pick(e, PRACTICAL),
      sessions: full?.sessions.map((x) => pick(x, ['id', 'title', 'titleMy', 'description', 'descriptionMy', 'location', 'startsAt', 'endsAt'] as const)) ?? [],
      performers:
        full?.performers.map((x) => ({
          ...pick(x, ['id', 'name', 'nameMy', 'role', 'roleMy', 'bio', 'bioMy'] as const),
          photoKey: x.photoKey,
          photoUrl: this.media.url(x.photoKey),
        })) ?? [],
      media: full?.media.map((x) => ({ id: x.id, key: x.key, url: this.media.url(x.key), caption: x.caption, captionMy: x.captionMy })) ?? [],
      faqs: full?.faqs.map((x) => pick(x, ['id', 'question', 'questionMy', 'answer', 'answerMy'] as const)) ?? [],
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
      include: fullInclude,
    });
    if (!e) throw new NotFoundException('Event not found');
    void this.countView(e.id);
    return this.toDto(e, { full: true });
  }

  /**
   * Daily page-view counter (Myanmar date) for the organizer dashboard. Views are added up in memory and
   * written every 10 s: one write per event instead of one per page view, so a popular event's
   * counter row doesn't become a queue of locked updates during an on-sale rush.
   */
  private pendingViews = new Map<string, number>();
  private viewTimer?: NodeJS.Timeout;

  private countView(eventId: string) {
    const day = new Date(Date.now() + 6.5 * 3600e3).toISOString().slice(0, 10);
    const key = `${eventId}|${day}`;
    this.pendingViews.set(key, (this.pendingViews.get(key) ?? 0) + 1);
    if (!this.viewTimer) {
      this.viewTimer = setTimeout(() => void this.flushViews(), 10_000);
      this.viewTimer.unref();
    }
  }

  async flushViews() {
    if (this.viewTimer) clearTimeout(this.viewTimer);
    this.viewTimer = undefined;
    const batch = [...this.pendingViews];
    this.pendingViews.clear();
    for (const [key, n] of batch) {
      const [eventId, day] = key.split('|');
      await this.prisma.$executeRaw`
        INSERT INTO event_daily_stats (event_id, day, views) VALUES (${eventId}::uuid, ${day}::date, ${n})
        ON CONFLICT (event_id, day) DO UPDATE SET views = event_daily_stats.views + ${n}`.catch(() => undefined);
    }
  }

  async onModuleDestroy() {
    await this.flushViews();
  }

  // ───────────── Organizer ─────────────

  listForOrg(organizationId: string) {
    return this.prisma.event
      .findMany({ where: { organizationId }, include: cardInclude, orderBy: { startsAt: 'desc' } })
      .then((rows) => rows.map((e) => this.toDto(e, { full: true })));
  }

  async getForOrg(organizationId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId }, include: fullInclude });
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
        ...pick(dto, PRACTICAL),
        ...(dto.venue ? { venue: { create: dto.venue } } : {}),
      },
      include: fullInclude,
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
    const before = current.venueId ? await this.prisma.venue.findUnique({ where: { id: current.venueId } }) : null;
    const e = await this.prisma.event.update({ where: { id }, data, include: fullInclude });
    // Ticket holders hear about time or place changes of a live listing (push + inbox + SMS)
    const place = (v: { name?: string | null; address?: string | null; city?: string | null } | null | undefined) => [v?.name, v?.address, v?.city].map((x) => x ?? '').join('|');
    const moved = startsAt.getTime() !== current.startsAt.getTime() || endsAt.getTime() !== current.endsAt.getTime();
    const relocated = !!venue && place(before) !== place(e.venue);
    // (also while a published event is back in review: its ticket holders still need to know)
    if (current.publishedAt && (moved || relocated)) {
      void this.notify.eventChanged({ id, title: e.title, titleMy: e.titleMy, startsAt: e.startsAt, venue: e.venue?.name ?? null });
      if (moved) await this.prisma.event.update({ where: { id }, data: { reminderSentAt: null } }); // remind again for the new date
    }
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
      include: fullInclude,
    });
    return this.toDto(updated, { full: true });
  }

  async cancel(organizationId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId } });
    if (!e) throw new NotFoundException('Event not found');
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException(`Event is already ${e.status}`);
    const updated = await this.prisma.event.update({ where: { id }, data: { status: 'CANCELLED' }, include: fullInclude });
    if (['PUBLISHED', 'ONGOING'].includes(e.status)) void this.notify.eventCancelled({ id, title: e.title, titleMy: e.titleMy, startsAt: e.startsAt });
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

  // ───────────── Schedule, lineup, gallery, FAQ (replace-all lists) ─────────────

  /** Editing details of a published event from an unverified organizer sends it back to review. */
  private async editableForLists(organizationId: string, id: string, orgVerified: boolean) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId } });
    if (!e) throw new NotFoundException('Event not found');
    if (!EDITABLE.includes(e.status)) throw new ConflictException(`Cannot edit an event that is ${e.status}`);
    const needsReview = e.status === 'PUBLISHED' && !orgVerified;
    return { needsReview };
  }

  private async afterListEdit(id: string, needsReview: boolean) {
    if (needsReview) await this.prisma.event.update({ where: { id }, data: { status: 'SUBMITTED', submittedAt: new Date() } });
    const e = await this.prisma.event.findUniqueOrThrow({ where: { id }, include: fullInclude });
    return { ...this.toDto(e, { full: true }), reReviewRequired: needsReview };
  }

  private assertKeys(keys: (string | undefined)[]) {
    for (const k of keys) if (k && !this.media.isOwnKey(k)) throw new BadRequestException(`Invalid media key: ${k}`);
  }

  async replaceSessions(organizationId: string, id: string, items: SessionItemDto[], orgVerified: boolean) {
    const { needsReview } = await this.editableForLists(organizationId, id, orgVerified);
    for (const x of items) if (new Date(x.endsAt) <= new Date(x.startsAt)) throw new BadRequestException(`"${x.title}": end must be after start`);
    // Sessions are matched by id so their live channels (and stream keys) survive schedule edits.
    const existing = await this.prisma.eventSession.findMany({ where: { eventId: id }, include: { liveChannel: true } });
    const keep = new Set(items.map((x) => x.id).filter((x): x is string => !!x && existing.some((e) => e.id === x)));
    const removed = existing.filter((e) => !keep.has(e.id));
    if (removed.some((e) => e.liveChannel?.status === 'LIVE')) throw new ConflictException('A session that is streaming right now cannot be removed');
    await this.prisma.$transaction([
      this.prisma.eventSession.deleteMany({ where: { id: { in: removed.map((e) => e.id) } } }),
      ...items.map(({ id: sid, ...x }) => {
        const data = { ...x, startsAt: new Date(x.startsAt), endsAt: new Date(x.endsAt) };
        return sid && keep.has(sid)
          ? this.prisma.eventSession.update({ where: { id: sid }, data })
          : this.prisma.eventSession.create({ data: { ...data, eventId: id } });
      }),
    ]);
    return this.afterListEdit(id, needsReview);
  }

  async replacePerformers(organizationId: string, id: string, items: PerformerItemDto[], orgVerified: boolean) {
    const { needsReview } = await this.editableForLists(organizationId, id, orgVerified);
    this.assertKeys(items.map((x) => x.photoKey));
    await this.prisma.$transaction([
      this.prisma.eventPerformer.deleteMany({ where: { eventId: id } }),
      this.prisma.eventPerformer.createMany({ data: items.map((x, i) => ({ ...x, eventId: id, sortOrder: i })) }),
    ]);
    return this.afterListEdit(id, needsReview);
  }

  async replaceMedia(organizationId: string, id: string, items: MediaItemDto[], orgVerified: boolean) {
    const { needsReview } = await this.editableForLists(organizationId, id, orgVerified);
    this.assertKeys(items.map((x) => x.key));
    await this.prisma.$transaction([
      this.prisma.eventMedia.deleteMany({ where: { eventId: id } }),
      this.prisma.eventMedia.createMany({ data: items.map((x, i) => ({ ...x, eventId: id, sortOrder: i })) }),
    ]);
    return this.afterListEdit(id, needsReview);
  }

  async replaceFaqs(organizationId: string, id: string, items: FaqItemDto[], orgVerified: boolean) {
    const { needsReview } = await this.editableForLists(organizationId, id, orgVerified);
    await this.prisma.$transaction([
      this.prisma.eventFaq.deleteMany({ where: { eventId: id } }),
      this.prisma.eventFaq.createMany({ data: items.map((x, i) => ({ ...x, eventId: id, sortOrder: i })) }),
    ]);
    return this.afterListEdit(id, needsReview);
  }

  // ───────────── Organizer public profile ─────────────

  async updateOrgProfile(organizationId: string, dto: OrgProfileDto) {
    const { logoKey, ...rest } = dto;
    this.assertKeys([logoKey]);
    await this.prisma.organization.update({
      where: { id: organizationId },
      data: { ...rest, ...(logoKey !== undefined ? { logoUrl: logoKey } : {}) },
    });
    return this.orgProfileFor(organizationId);
  }

  private async orgProfileFor(id: string) {
    const o = await this.prisma.organization.findUniqueOrThrow({ where: { id } });
    return {
      ...pick(o, ['id', 'name', 'slug', 'description', 'descriptionMy', 'website', 'facebookUrl', 'contactEmail', 'contactPhone', 'showContact', 'kycStatus'] as const),
      logoKey: o.logoUrl,
      logoUrl: this.media.url(o.logoUrl),
    };
  }

  getOrgProfile(organizationId: string) {
    return this.orgProfileFor(organizationId);
  }

  /** Public organizer page: profile plus upcoming public events. Contact details only if the organizer allows it. */
  async publicOrganizer(slug: string) {
    const o = await this.prisma.organization.findUnique({ where: { slug } });
    if (!o) throw new NotFoundException('Organizer not found');
    const events = await this.prisma.event.findMany({
      where: { organizationId: o.id, status: 'PUBLISHED', visibility: 'PUBLIC', endsAt: { gte: new Date() } },
      include: cardInclude,
      orderBy: { startsAt: 'asc' },
      take: 50,
    });
    return {
      ...pick(o, ['id', 'name', 'slug', 'description', 'descriptionMy', 'website', 'facebookUrl'] as const),
      logoUrl: this.media.url(o.logoUrl),
      verified: o.kycStatus === 'APPROVED',
      contactEmail: o.showContact ? o.contactEmail : null,
      contactPhone: o.showContact ? o.contactPhone : null,
      events: events.map((e) => this.toDto(e)),
    };
  }

  // ───────────── Calendar (.ics) ─────────────

  async calendar(idOrSlug: string): Promise<{ filename: string; body: string }> {
    const e = await this.getPublic(idOrSlug);
    const esc = (v: string) => v.replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1');
    const ts = (d: Date | string) => new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    // RFC 5545: lines are at most 75 octets; Myanmar characters are 3 bytes in UTF-8, so fold by bytes.
    const fold = (line: string) => {
      const parts: string[] = [];
      let cur = '';
      for (const ch of line) {
        if (Buffer.byteLength(cur + ch) > (parts.length ? 74 : 75)) {
          parts.push(cur);
          cur = '';
        }
        cur += ch;
      }
      parts.push(cur);
      return parts.join('\r\n ');
    };
    const location = e.venue ? [e.venue.name, e.venue.address, e.venue.city].filter(Boolean).join(', ') : 'Online';
    const desc = [e.summary, e.titleMy, e.summaryMy].filter(Boolean).join('\n');
    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Event 360//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      `UID:${e.id}@event360.app`,
      `DTSTAMP:${ts(new Date())}`,
      `DTSTART:${ts(e.startsAt)}`,
      `DTEND:${ts(e.endsAt)}`,
      `SUMMARY:${esc(e.title)}`,
      `LOCATION:${esc(location)}`,
      `DESCRIPTION:${esc(desc)}`,
      `ORGANIZER;CN=${esc(e.organization.name)}:mailto:noreply@event360.app`,
      ...(e.status === 'CANCELLED' ? ['STATUS:CANCELLED'] : ['STATUS:CONFIRMED']),
      'END:VEVENT',
      'END:VCALENDAR',
    ].map(fold);
    return { filename: `${e.slug}.ics`, body: lines.join('\r\n') + '\r\n' };
  }

  // ───────────── Admin moderation ─────────────

  listForAdmin(status: EventStatus) {
    return this.prisma.event
      .findMany({ where: { status }, include: fullInclude, orderBy: { submittedAt: 'asc' } })
      .then((rows) => rows.map((e) => this.toDto(e, { full: true })));
  }

  async approve(id: string) {
    const e = await this.prisma.event.findUnique({ where: { id } });
    if (!e) throw new NotFoundException('Event not found');
    if (e.status !== 'SUBMITTED') throw new ConflictException(`Only SUBMITTED events can be approved (is ${e.status})`);
    const updated = await this.prisma.event.update({
      where: { id },
      data: { status: 'PUBLISHED', publishedAt: e.publishedAt ?? new Date(), rejectionReason: null },
      include: fullInclude,
    });
    void this.notify.eventReviewed(e, true);
    return this.toDto(updated, { full: true });
  }

  /** Reject a submission, or take down a published event. */
  async reject(id: string, reason: string) {
    const e = await this.prisma.event.findUnique({ where: { id } });
    if (!e) throw new NotFoundException('Event not found');
    if (!['SUBMITTED', 'PUBLISHED'].includes(e.status)) throw new ConflictException(`Cannot reject an event that is ${e.status}`);
    const updated = await this.prisma.event.update({ where: { id }, data: { status: 'REJECTED', rejectionReason: reason }, include: fullInclude });
    void this.notify.eventReviewed(e, false, reason);
    return this.toDto(updated, { full: true });
  }
}
