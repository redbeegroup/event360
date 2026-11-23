import { ConflictException, ForbiddenException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import type { CheckinMethod, Event, OrgRole, Prisma, TicketStatus } from '@prisma/client';
import { createHash, randomInt } from 'crypto';
import type { AuthUser } from '../../common/auth';
import { MediaService } from '../media/media.module';
import { PrismaService } from '../prisma/prisma.service';
import { TicketTokenService } from '../tickets/ticket-token.service';

/** Roles that may scan tickets for their organization's events. */
export const CREW_ROLES: OrgRole[] = ['ORG_OWNER', 'ORG_MANAGER', 'CREW'];

export type ScanResult = 'ACCEPTED' | 'ALREADY_CHECKED_IN' | 'WRONG_EVENT' | 'INVALID' | 'VOID' | 'REFUNDED' | 'TRANSFERRED';

/** Who performed a check-in: an invited user or a volunteer device session. */
export interface Actor {
  userId?: string;
  sessionId?: string;
}

export interface ScanInput {
  gate?: string;
  deviceId?: string;
  scannedAt?: string | Date;
  offline?: boolean;
  method?: CheckinMethod;
}

const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I/L
const CODE_GRACE_MS = 12 * 3600_000; // codes and crew sessions stay valid until 12 h after the event ends
const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
export const normalizeCode = (c: string) => c.toUpperCase().replace(/[^A-Z0-9]/g, '');

const ticketInclude = {
  holder: { select: { displayName: true, phone: true } },
  ticketType: { select: { id: true, name: true, nameMy: true, eventId: true } },
  checkins: {
    where: { isDuplicate: false, undoneAt: null },
    orderBy: { scannedAt: 'desc' },
    take: 1,
    include: { crewUser: { select: { displayName: true, email: true } }, crewSession: { select: { deviceName: true } } },
  },
} satisfies Prisma.TicketInclude;
type TicketRow = Prisma.TicketGetPayload<{ include: typeof ticketInclude }>;

@Injectable()
export class CheckinService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly tokens: TicketTokenService,
    private readonly jwt: JwtService,
    private readonly media: MediaService,
  ) {}

  // ───────────── access ─────────────

  /** The event the caller may scan for, and who they are for the check-in log. */
  async assertEvent(u: AuthUser, eventId: string): Promise<{ event: Event; actor: Actor }> {
    const event = await this.prisma.event.findUnique({ where: { id: eventId } });
    if (!event) throw new NotFoundException('Event not found');
    if (u.typ === 'crew') {
      if (u.eid !== eventId) throw new ForbiddenException('This code is for another event');
      const s = await this.prisma.crewSession.findUnique({ where: { id: u.sub }, include: { accessCode: true } });
      if (!s || s.revokedAt || s.accessCode.revokedAt || s.accessCode.expiresAt < new Date()) {
        throw new UnauthorizedException('This event code is no longer valid');
      }
      return { event, actor: { sessionId: s.id } };
    }
    if (!u.roles?.includes('PLATFORM_ADMIN')) {
      const m = await this.prisma.organizationMember.findUnique({
        where: { organizationId_userId: { organizationId: event.organizationId, userId: u.sub } },
      });
      if (!m || !CREW_ROLES.includes(m.role)) throw new ForbiddenException('You are not crew for this event');
    }
    return { event, actor: { userId: u.sub } };
  }

  private eventSummary(e: Event & { venue?: { name: string; city: string } | null }) {
    return {
      id: e.id,
      title: e.title,
      titleMy: e.titleMy,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      status: e.status,
      coverImageUrl: this.media.url(e.coverImageUrl),
      venue: e.venue ? { name: e.venue.name, city: e.venue.city } : null,
    };
  }

  /** Events the caller can scan: published, from a week before start until 12 h after the end. */
  async crewEvents(u: AuthUser) {
    const now = Date.now();
    const window = { status: 'PUBLISHED' as const, endsAt: { gte: new Date(now - CODE_GRACE_MS) }, startsAt: { lte: new Date(now + 7 * 864e5) } };
    let where: Prisma.EventWhereInput;
    if (u.typ === 'crew') where = { id: u.eid };
    else if (u.roles?.includes('PLATFORM_ADMIN')) where = window;
    else {
      const orgs = await this.prisma.organizationMember.findMany({ where: { userId: u.sub, role: { in: CREW_ROLES } }, select: { organizationId: true } });
      where = { ...window, organizationId: { in: orgs.map((o) => o.organizationId) } };
    }
    const events = await this.prisma.event.findMany({ where, include: { venue: true }, orderBy: { startsAt: 'asc' }, take: 50 });
    return events.map((e) => this.eventSummary(e));
  }

  // ───────────── event codes (organizer) ─────────────

  private async orgEvent(organizationId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId } });
    if (!e) throw new NotFoundException('Event not found');
    return e;
  }

  async createCode(organizationId: string, eventId: string, createdById: string, label: string, gate?: string) {
    const e = await this.orgEvent(organizationId, eventId);
    const raw = Array.from({ length: 8 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join('');
    const code = `${raw.slice(0, 4)}-${raw.slice(4)}`;
    const row = await this.prisma.eventAccessCode.create({
      data: { eventId, codeHash: sha256(raw), label, gate: gate || null, createdById, expiresAt: new Date(e.endsAt.getTime() + CODE_GRACE_MS) },
    });
    // The code is only ever shown once; the database keeps a hash.
    return { id: row.id, label: row.label, gate: row.gate, expiresAt: row.expiresAt, code, redeemUri: `event360crew://redeem?code=${code}` };
  }

  async listCodes(organizationId: string, eventId: string) {
    await this.orgEvent(organizationId, eventId);
    const rows = await this.prisma.eventAccessCode.findMany({
      where: { eventId },
      orderBy: { createdAt: 'desc' },
      include: { _count: { select: { sessions: true } } },
    });
    return rows.map((r) => ({
      id: r.id,
      label: r.label,
      gate: r.gate,
      expiresAt: r.expiresAt,
      revokedAt: r.revokedAt,
      createdAt: r.createdAt,
      devices: r._count.sessions,
      active: !r.revokedAt && r.expiresAt > new Date(),
    }));
  }

  async revokeCode(organizationId: string, eventId: string, codeId: string) {
    await this.orgEvent(organizationId, eventId);
    const now = new Date();
    const r = await this.prisma.eventAccessCode.updateMany({ where: { id: codeId, eventId, revokedAt: null }, data: { revokedAt: now } });
    if (!r.count) throw new NotFoundException('Code not found or already revoked');
    await this.prisma.crewSession.updateMany({ where: { accessCodeId: codeId, revokedAt: null }, data: { revokedAt: now } });
    return { revoked: true };
  }

  /** Volunteer device: event code → crew session token scoped to that one event. */
  async redeem(code: string, deviceName: string) {
    const ac = await this.prisma.eventAccessCode.findUnique({ where: { codeHash: sha256(normalizeCode(code)) }, include: { event: { include: { venue: true } } } });
    if (!ac || ac.revokedAt || ac.expiresAt < new Date()) throw new UnauthorizedException('Invalid or expired event code');
    if (ac.event.status !== 'PUBLISHED') throw new ConflictException('This event is not open for check-in');
    const s = await this.prisma.crewSession.create({ data: { accessCodeId: ac.id, eventId: ac.eventId, deviceName } });
    const expiresIn = Math.max(60, Math.floor((ac.expiresAt.getTime() - Date.now()) / 1000));
    const accessToken = await this.jwt.signAsync({ sub: s.id, roles: [], typ: 'crew', eid: ac.eventId }, { expiresIn });
    return { accessToken, expiresAt: ac.expiresAt, gate: ac.gate, label: ac.label, event: this.eventSummary(ac.event) };
  }

  // ───────────── scanning ─────────────

  private holderName(h: { displayName: string | null; phone: string | null }) {
    if (h.displayName) return h.displayName;
    if (h.phone) return `•••• ${h.phone.slice(-4)}`;
    return 'Guest';
  }

  /** Holder line shown to door staff; guest tickets read "<guest> · Complimentary · <label>". */
  private holderLine(t: TicketRow) {
    const name = t.isComplimentary && t.guestName ? t.guestName : this.holderName(t.holder);
    return t.isComplimentary ? [name, 'Complimentary', t.compLabel].filter(Boolean).join(' · ') : name;
  }

  private ticketView(t: TicketRow) {
    const last = t.checkins[0];
    return {
      id: t.id,
      code: t.id.slice(0, 8).toUpperCase(),
      status: t.status,
      holderName: this.holderLine(t),
      phoneLast4: t.holder.phone?.slice(-4) ?? null,
      seat: t.seatLabel,
      seatMy: t.seatLabelMy,
      isComplimentary: t.isComplimentary,
      ticketType: { id: t.ticketType.id, name: t.ticketType.name, nameMy: t.ticketType.nameMy },
      checkedIn:
        t.status === 'CHECKED_IN' && last
          ? { at: last.scannedAt, gate: last.gate, by: last.crewUser?.displayName ?? last.crewUser?.email ?? last.crewSession?.deviceName ?? null }
          : null,
    };
  }

  private async loadTicket(ticketId: string) {
    return this.prisma.ticket.findUnique({ where: { id: ticketId }, include: ticketInclude });
  }

  private clampTime(t?: string | Date) {
    const now = Date.now();
    const v = t ? new Date(t).getTime() : NaN;
    return Number.isFinite(v) && v <= now + 5 * 60_000 && v >= now - 7 * 864e5 ? new Date(v) : new Date(now);
  }

  /**
   * Checks a ticket in. The VALID → CHECKED_IN transition is a single conditional UPDATE, so two gates scanning
   * the same ticket at once can never both be accepted; the loser gets ALREADY_CHECKED_IN.
   */
  private async checkIn(actor: Actor, ticketId: string, input: ScanInput) {
    const at = this.clampTime(input.scannedAt);
    const base = {
      ticketId,
      crewUserId: actor.userId ?? null,
      crewSessionId: actor.sessionId ?? null,
      method: input.method ?? 'QR',
      gate: input.gate || null,
      deviceId: input.deviceId || null,
      scannedAt: at,
      offline: !!input.offline,
    } as const;
    const before = await this.loadTicket(ticketId);
    if (!before) return { result: 'INVALID' as ScanResult, ticket: null };
    const eventId = before.ticketType.eventId;
    const won = await this.prisma.$transaction(async (tx) => {
      const r = await tx.ticket.updateMany({ where: { id: ticketId, status: 'VALID' }, data: { status: 'CHECKED_IN' } });
      if (r.count === 1) await tx.checkin.create({ data: { ...base, eventId } });
      return r.count === 1;
    });
    if (won) return { result: 'ACCEPTED' as ScanResult, ticket: this.ticketView((await this.loadTicket(ticketId))!) };
    const now = await this.loadTicket(ticketId);
    if (now!.status === 'CHECKED_IN') {
      await this.prisma.checkin.create({ data: { ...base, eventId, isDuplicate: true } });
      return { result: 'ALREADY_CHECKED_IN' as ScanResult, ticket: this.ticketView(now!) };
    }
    return { result: now!.status as Exclude<TicketStatus, 'VALID' | 'CHECKED_IN'> as ScanResult, ticket: this.ticketView(now!) };
  }

  /** Online scan of a ticket QR. */
  async scan(actor: Actor, eventId: string, qr: string, input: ScanInput) {
    const claims = this.tokens.verify(qr.trim());
    if (!claims) return { result: 'INVALID' as ScanResult, reason: 'signature', ticket: null };
    if (claims.eid !== eventId) {
      const other = await this.prisma.event.findUnique({ where: { id: claims.eid }, select: { title: true, titleMy: true, startsAt: true } });
      return { result: 'WRONG_EVENT' as ScanResult, otherEvent: other, ticket: null };
    }
    const t = await this.loadTicket(claims.tid);
    if (!t || t.ticketType.eventId !== eventId) return { result: 'INVALID' as ScanResult, reason: 'unknown_ticket', ticket: null };
    if (t.qrVersion !== claims.v) return { result: 'INVALID' as ScanResult, reason: 'outdated_qr', ticket: this.ticketView(t) };
    return this.checkIn(actor, t.id, { ...input, method: 'QR' });
  }

  /** Scans recorded while the device was offline, applied in the order they happened. */
  async sync(actor: Actor, eventId: string, scans: { clientId: string; qr?: string; ticketId?: string; method?: CheckinMethod; gate?: string; deviceId?: string; scannedAt?: string }[]) {
    const ordered = [...scans].sort((a, b) => String(a.scannedAt ?? '').localeCompare(String(b.scannedAt ?? '')));
    const results = [];
    for (const s of ordered) {
      const input: ScanInput = { gate: s.gate, deviceId: s.deviceId, scannedAt: s.scannedAt, offline: true };
      let r;
      if (s.qr) r = await this.scan(actor, eventId, s.qr, input);
      else if (s.ticketId) {
        const t = await this.loadTicket(s.ticketId);
        r = !t || t.ticketType.eventId !== eventId ? { result: 'INVALID' as ScanResult, ticket: null } : await this.checkIn(actor, t.id, { ...input, method: s.method ?? 'MANUAL' });
      } else r = { result: 'INVALID' as ScanResult, ticket: null };
      results.push({ clientId: s.clientId, ...r });
    }
    return { results };
  }

  async manualCheckin(actor: Actor, eventId: string, ticketId: string, input: ScanInput) {
    const t = await this.loadTicket(ticketId);
    if (!t || t.ticketType.eventId !== eventId) throw new NotFoundException('Ticket not found for this event');
    return this.checkIn(actor, ticketId, { ...input, method: 'MANUAL' });
  }

  async undo(actor: Actor, eventId: string, ticketId: string) {
    const t = await this.loadTicket(ticketId);
    if (!t || t.ticketType.eventId !== eventId) throw new NotFoundException('Ticket not found for this event');
    const by = actor.userId ? `user:${actor.userId}` : `crew:${actor.sessionId}`;
    const ok = await this.prisma.$transaction(async (tx) => {
      const r = await tx.ticket.updateMany({ where: { id: ticketId, status: 'CHECKED_IN' }, data: { status: 'VALID' } });
      if (r.count) await tx.checkin.updateMany({ where: { ticketId, undoneAt: null }, data: { undoneAt: new Date(), undoneBy: by } });
      return r.count === 1;
    });
    if (!ok) throw new ConflictException({ message: 'This ticket is not checked in', reasonCode: 'NOT_CHECKED_IN' });
    return { ticket: this.ticketView((await this.loadTicket(ticketId))!) };
  }

  /** Manual lookup by holder name, phone digits or the 8-character ticket code. */
  async search(eventId: string, q: string) {
    const term = q.trim();
    if (term.length < 2) return [];
    let digits = term.replace(/\D/g, '');
    if (digits.startsWith('0')) digits = digits.slice(1);
    const code = /^[0-9a-f-]{4,}$/i.test(term) ? term.toLowerCase() : null;
    const rows = await this.prisma.$queryRaw<{ id: string }[]>`
      SELECT t.id FROM tickets t
      JOIN ticket_types tt ON tt.id = t.ticket_type_id
      JOIN users u ON u.id = t.holder_user_id
      WHERE tt.event_id = ${eventId}::uuid AND (
        u.display_name ILIKE ${'%' + term + '%'}
        OR t.guest_name ILIKE ${'%' + term + '%'}
        OR (${digits.length >= 3} AND u.phone LIKE ${'%' + digits + '%'})
        OR (${code !== null} AND t.id::text LIKE ${(code ?? '') + '%'})
      )
      ORDER BY t.created_at LIMIT 20`;
    const tickets = await this.prisma.ticket.findMany({ where: { id: { in: rows.map((r) => r.id) } }, include: ticketInclude });
    return tickets.map((t) => this.ticketView(t));
  }

  /** Everything a device needs to check tickets without the network. */
  async manifest(eventId: string) {
    const [types, tickets] = await Promise.all([
      this.prisma.ticketType.findMany({ where: { eventId }, select: { id: true, name: true, nameMy: true } }),
      this.prisma.ticket.findMany({ where: { ticketType: { eventId } }, include: ticketInclude }),
    ]);
    return {
      eventId,
      generatedAt: new Date(),
      publicKey: this.tokens.publicKeyRaw(),
      ticketTypes: types,
      tickets: tickets.map((t) => {
        const v = this.ticketView(t);
        return { id: t.id, code: v.code, tt: t.ticketTypeId, v: t.qrVersion, status: t.status, holderName: v.holderName, phoneLast4: v.phoneLast4, seat: v.seat, seatMy: v.seatMy, checkedInAt: v.checkedIn?.at ?? null };
      }),
    };
  }

  async stats(eventId: string) {
    const [types, byStatus, byGate, recent] = await Promise.all([
      this.prisma.ticketType.findMany({ where: { eventId }, select: { id: true, name: true, nameMy: true }, orderBy: { priceMmk: 'asc' } }),
      this.prisma.ticket.groupBy({ by: ['ticketTypeId', 'status', 'isComplimentary'], where: { ticketType: { eventId } }, _count: { _all: true } }),
      this.prisma.checkin.groupBy({ by: ['gate'], where: { eventId, isDuplicate: false, undoneAt: null }, _count: { _all: true } }),
      this.prisma.checkin.findMany({
        where: { eventId },
        orderBy: { scannedAt: 'desc' },
        take: 20,
        include: {
          ticket: { include: { holder: { select: { displayName: true, phone: true } }, ticketType: { select: { name: true, nameMy: true } } } },
          crewUser: { select: { displayName: true, email: true } },
          crewSession: { select: { deviceName: true } },
        },
      }),
    ]);
    const count = (tt: string | null, statuses: TicketStatus[], comp?: boolean) =>
      byStatus.filter((r) => (tt === null || r.ticketTypeId === tt) && statuses.includes(r.status) && (comp === undefined || r.isComplimentary === comp)).reduce((a, r) => a + r._count._all, 0);
    return {
      registered: count(null, ['VALID', 'CHECKED_IN']),
      checkedIn: count(null, ['CHECKED_IN']),
      byTicketType: types.map((t) => ({ ...t, registered: count(t.id, ['VALID', 'CHECKED_IN']), checkedIn: count(t.id, ['CHECKED_IN']), comp: count(t.id, ['VALID', 'CHECKED_IN'], true) })),
      byGate: byGate.map((g) => ({ gate: g.gate, checkedIn: g._count._all })).sort((a, b) => b.checkedIn - a.checkedIn),
      recent: recent.map((c) => ({
        id: c.id,
        at: c.scannedAt,
        gate: c.gate,
        method: c.method,
        offline: c.offline,
        duplicate: c.isDuplicate,
        undone: !!c.undoneAt,
        by: c.crewUser?.displayName ?? c.crewUser?.email ?? c.crewSession?.deviceName ?? null,
        ticket: {
          id: c.ticketId,
          code: c.ticketId.slice(0, 8).toUpperCase(),
          status: c.ticket.status,
          holderName: this.holderName(c.ticket.holder),
          ticketType: c.ticket.ticketType,
        },
      })),
    };
  }

  async attendanceForOrg(organizationId: string, eventId: string) {
    await this.orgEvent(organizationId, eventId);
    return this.stats(eventId);
  }
}
