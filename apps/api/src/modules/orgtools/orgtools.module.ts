import { BadRequestException, Body, ConflictException, Controller, Delete, Get, HttpCode, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Patch, Post, Res } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Prisma } from '@prisma/client';
import { ArrayMaxSize, IsArray, IsBoolean, IsDateString, IsIn, IsInt, IsOptional, IsString, IsUUID, Matches, Max, Min } from 'class-validator';
import type { Response } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { maskPhone, mmk } from '../../common/util';
import { priceView } from '../payments/pricing';
import { normalizeCode } from '../payments/promo';
import { PrismaService } from '../prisma/prisma.service';

class PromoDto {
  @ApiProperty({ example: 'EARLYBIRD' }) @IsString() @Matches(/^[A-Za-z0-9_-]{3,24}$/, { message: 'Code: 3–24 letters, digits, - or _' }) code: string;
  @ApiProperty({ enum: ['PERCENT', 'FIXED'] }) @IsIn(['PERCENT', 'FIXED']) kind: 'PERCENT' | 'FIXED';
  @ApiProperty({ description: 'PERCENT: whole percent 1–100; FIXED: MMK off the order' }) @IsInt() @Min(1) @Max(100_000_000) value: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(1_000_000) maxUses?: number;
  @ApiPropertyOptional() @IsOptional() @IsDateString() startsAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() endsAt?: string;
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(50) @IsUUID('all', { each: true }) ticketTypeIds?: string[];
}

class PromoPatchDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(1_000_000) maxUses?: number;
  @ApiPropertyOptional() @IsOptional() @IsDateString() endsAt?: string;
}

const TZ_OFFSET_MS = 6.5 * 3600e3; // Myanmar time (no DST)
const ymd = (d: Date) => new Date(d.getTime() + TZ_OFFSET_MS).toISOString().slice(0, 10);

@Injectable()
export class OrgToolsService {
  constructor(private readonly prisma: PrismaService) {}

  async event(orgId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId: orgId }, include: { ticketTypes: { orderBy: { priceMmk: 'asc' }, include: { priceSteps: true } } } });
    if (!e) throw new NotFoundException('Event not found');
    return e;
  }

  // ───────────── promo codes ─────────────

  async promos(orgId: string, eventId: string) {
    await this.event(orgId, eventId);
    const rows = await this.prisma.promoCode.findMany({ where: { eventId }, orderBy: { createdAt: 'desc' } });
    const stats = await this.prisma.order.groupBy({
      by: ['promoCodeId'],
      where: { eventId, promoCodeId: { in: rows.map((r) => r.id) }, status: { in: ['PAID', 'CONFIRMED'] } },
      _sum: { discountMmk: true, totalMmk: true },
      _count: true,
    });
    return rows.map((r) => {
      const st = stats.find((x) => x.promoCodeId === r.id);
      return {
        id: r.id,
        code: r.code,
        kind: r.kind,
        value: r.kind === 'PERCENT' ? r.value / 100 : r.value, // percent shown as whole number
        maxUses: r.maxUses,
        used: r.used,
        startsAt: r.startsAt,
        endsAt: r.endsAt,
        ticketTypeIds: r.ticketTypeIds,
        isActive: r.isActive,
        createdAt: r.createdAt,
        orders: st?._count ?? 0,
        discountGivenMmk: mmk(st?._sum.discountMmk),
        revenueMmk: mmk(st?._sum.totalMmk),
      };
    });
  }

  async createPromo(orgId: string, eventId: string, dto: PromoDto, actorId: string) {
    const e = await this.event(orgId, eventId);
    if (['CANCELLED', 'COMPLETED'].includes(e.status)) throw new ConflictException(`Event is ${e.status}`);
    if (dto.kind === 'PERCENT' && dto.value > 100) throw new BadRequestException('Percent must be 1–100');
    const types = dto.ticketTypeIds ?? [];
    if (types.some((t) => !e.ticketTypes.find((x) => x.id === t))) throw new BadRequestException('Unknown ticket type');
    if (dto.startsAt && dto.endsAt && new Date(dto.endsAt) <= new Date(dto.startsAt)) throw new BadRequestException('End must be after start');
    try {
      await this.prisma.promoCode.create({
        data: {
          eventId,
          code: normalizeCode(dto.code),
          kind: dto.kind,
          value: dto.kind === 'PERCENT' ? dto.value * 100 : dto.value,
          maxUses: dto.maxUses ?? null,
          startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
          endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
          ticketTypeIds: types,
          createdById: actorId,
        },
      });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') throw new ConflictException('This code already exists for the event');
      throw err;
    }
    return this.promos(orgId, eventId);
  }

  async patchPromo(orgId: string, eventId: string, promoId: string, dto: PromoPatchDto) {
    await this.event(orgId, eventId);
    const p = await this.prisma.promoCode.findFirst({ where: { id: promoId, eventId } });
    if (!p) throw new NotFoundException('Code not found');
    if (dto.maxUses !== undefined && dto.maxUses < p.used) throw new BadRequestException(`Already used ${p.used} times`);
    await this.prisma.promoCode.update({
      where: { id: promoId },
      data: { ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}), ...(dto.maxUses !== undefined ? { maxUses: dto.maxUses } : {}), ...(dto.endsAt ? { endsAt: new Date(dto.endsAt) } : {}) },
    });
    return this.promos(orgId, eventId);
  }

  /** Unused codes are deleted; used ones are switched off (orders keep their reference). */
  async deletePromo(orgId: string, eventId: string, promoId: string) {
    await this.event(orgId, eventId);
    const p = await this.prisma.promoCode.findFirst({ where: { id: promoId, eventId } });
    if (!p) throw new NotFoundException('Code not found');
    const orders = await this.prisma.order.count({ where: { promoCodeId: promoId } });
    if (orders) await this.prisma.promoCode.update({ where: { id: promoId }, data: { isActive: false } });
    else await this.prisma.promoCode.delete({ where: { id: promoId } });
    return this.promos(orgId, eventId);
  }

  // ───────────── attendees CSV ─────────────

  async attendeesCsv(orgId: string, eventId: string) {
    const e = await this.event(orgId, eventId);
    const tickets = await this.prisma.ticket.findMany({
      where: { ticketType: { eventId } },
      orderBy: { createdAt: 'asc' },
      include: {
        ticketType: { select: { name: true } },
        holder: { select: { displayName: true, phone: true } },
        order: { select: { id: true, status: true, createdAt: true, discountMmk: true, promoCode: { select: { code: true } }, items: { select: { ticketTypeId: true, unitPriceMmk: true } } } },
        checkins: { where: { undoneAt: null, isDuplicate: false }, orderBy: { scannedAt: 'asc' }, take: 1 },
      },
    });
    const esc = (v: unknown) => {
      const s = v == null ? '' : String(v);
      // Neutralise spreadsheet formulas, quote everything
      return `"${(/^[=+\-@\t\r]/.test(s) ? `'${s}` : s).replace(/"/g, '""')}"`;
    };
    const fmt = (d?: Date | null) => (d ? new Date(d.getTime() + TZ_OFFSET_MS).toISOString().slice(0, 16).replace('T', ' ') : '');
    const header = ['ticket', 'holder', 'phone', 'ticket_type', 'price_mmk', 'status', 'order', 'order_status', 'promo_code', 'purchased_at_mmt', 'checked_in_at_mmt', 'gate', 'transfers', 'complimentary', 'seat'];
    const lines = tickets.map((t) =>
      [
        t.id.slice(0, 8).toUpperCase(),
        t.holder.displayName ?? '',
        maskPhone(t.holder.phone) ?? '',
        t.ticketType.name,
        t.isComplimentary ? 0 : mmk(t.order.items.find((i) => i.ticketTypeId === t.ticketTypeId)?.unitPriceMmk ?? 0n), // the price charged, frozen on the order
        t.status,
        t.order.id.slice(0, 8),
        t.order.status,
        t.order.promoCode?.code ?? '',
        fmt(t.order.createdAt),
        fmt(t.checkins[0]?.scannedAt),
        t.checkins[0]?.gate ?? '',
        t.transferCount,
        t.isComplimentary ? 'yes' : '',
        t.seatLabel ?? '',
      ]
        .map(esc)
        .join(','),
    );
    return { filename: `${e.slug}-attendees.csv`, csv: '﻿' + [header.join(','), ...lines].join('\r\n') };
  }

  // ───────────── dashboard ─────────────

  async dashboard(orgId: string, eventId: string) {
    const e = await this.event(orgId, eventId);
    const orders = await this.prisma.order.findMany({
      where: { eventId, channel: { not: 'COMP' }, status: { in: ['PAID', 'CONFIRMED', 'REFUNDED'] } },
      select: { createdAt: true, paidAt: true, status: true, totalMmk: true, discountMmk: true, items: { select: { quantity: true } } },
    });
    const views = await this.prisma.eventDailyStat.findMany({ where: { eventId }, orderBy: { day: 'asc' } });
    const checkins = await this.prisma.checkin.findMany({ where: { eventId, undoneAt: null, isDuplicate: false }, select: { scannedAt: true, gate: true } });

    // Daily series from the first activity (or 14 days ago) to today/event end, Myanmar dates
    const days = new Map<string, { day: string; orders: number; tickets: number; revenueMmk: number; views: number }>();
    const touch = (d: string) => days.get(d) ?? days.set(d, { day: d, orders: 0, tickets: 0, revenueMmk: 0, views: 0 }).get(d)!;
    for (const o of orders) {
      if (o.status === 'REFUNDED') continue;
      const r = touch(ymd(o.paidAt ?? o.createdAt));
      r.orders++;
      r.tickets += o.items.reduce((s, i) => s + i.quantity, 0);
      r.revenueMmk += mmk(o.totalMmk);
    }
    for (const v of views) touch(v.day.toISOString().slice(0, 10)).views += v.views;
    const end = ymd(new Date(Math.min(Date.now(), e.endsAt.getTime())));
    const keys = [...days.keys()].sort();
    let start = keys[0] ?? ymd(new Date(Date.now() - 13 * 86400e3));
    const minStart = ymd(new Date(new Date(`${end}T00:00:00Z`).getTime() - 89 * 86400e3)); // at most 90 days
    if (start < minStart) start = minStart;
    const series: { day: string; orders: number; tickets: number; revenueMmk: number; views: number }[] = [];
    for (let d = new Date(`${start}T00:00:00Z`); d.toISOString().slice(0, 10) <= end; d = new Date(d.getTime() + 86400e3)) {
      const k = d.toISOString().slice(0, 10);
      series.push(days.get(k) ?? { day: k, orders: 0, tickets: 0, revenueMmk: 0, views: 0 });
    }

    // Check-ins per 15 minutes (Myanmar time) and per gate
    const buckets = new Map<string, number>();
    const gates = new Map<string, number>();
    for (const c of checkins) {
      const t = new Date(c.scannedAt.getTime() + TZ_OFFSET_MS);
      t.setUTCMinutes(Math.floor(t.getUTCMinutes() / 15) * 15, 0, 0);
      const k = t.toISOString().slice(0, 16).replace('T', ' ');
      buckets.set(k, (buckets.get(k) ?? 0) + 1);
      const g = c.gate || '—';
      gates.set(g, (gates.get(g) ?? 0) + 1);
    }

    const live = orders.filter((o) => o.status !== 'REFUNDED');
    const totalViews = views.reduce((s, v) => s + v.views, 0);
    const sold = e.ticketTypes.reduce((s, t) => s + t.sold, 0);
    const quota = e.ticketTypes.reduce((s, t) => s + t.quota, 0);
    const seatRows = await this.prisma.$queryRaw<{ ticket_type_id: string; available: number; held: number; guest: number; sold: number; comp: number }[]>`
      SELECT s.ticket_type_id,
        count(*) FILTER (WHERE s.status = 'AVAILABLE')::int AS available,
        count(*) FILTER (WHERE s.status = 'CHECKOUT_HOLD')::int AS held,
        count(*) FILTER (WHERE s.status = 'GUEST_HOLD')::int AS guest,
        count(*) FILTER (WHERE s.status = 'SOLD' AND NOT COALESCE(t.is_complimentary, false))::int AS sold,
        count(*) FILTER (WHERE s.status = 'SOLD' AND COALESCE(t.is_complimentary, false))::int AS comp
      FROM event_seats s LEFT JOIN tickets t ON t.id = s.ticket_id
      WHERE s.event_id = ${eventId}::uuid AND s.ticket_type_id IS NOT NULL
      GROUP BY s.ticket_type_id`;
    const seatsByType = new Map(seatRows.map((r) => [r.ticket_type_id, { available: r.available, held: r.held, guest: r.guest, sold: r.sold, comp: r.comp }]));
    return {
      totals: {
        views: totalViews,
        orders: live.length,
        ticketsSold: sold,
        capacity: quota,
        revenueMmk: live.reduce((s, o) => s + mmk(o.totalMmk), 0),
        discountMmk: live.reduce((s, o) => s + mmk(o.discountMmk), 0),
        refundedOrders: orders.length - live.length,
        checkedIn: checkins.length,
        conversion: totalViews ? Math.round((live.length / totalViews) * 1000) / 10 : null, // % of page views that became orders
      },
      daily: series,
      checkinsByQuarterHour: [...buckets.entries()].sort().map(([at, count]) => ({ at, count })),
      checkinsByGate: [...gates.entries()].sort((a, b) => b[1] - a[1]).map(([gate, count]) => ({ gate, count })),
      ticketTypes: e.ticketTypes.map((t) => ({ id: t.id, name: t.name, sold: t.sold, quota: t.quota, ...priceView(t, new Date()), ...(seatsByType.has(t.id) ? { seats: seatsByType.get(t.id) } : {}) })),
    };
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id')
@Auth()
export class OrgToolsController {
  constructor(
    private readonly tools: OrgToolsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get('promo-codes')
  async list(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.tools.promos(orgId, id);
  }

  @Post('promo-codes')
  async create(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PromoDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.tools.createPromo(orgId, id, dto, u.sub);
  }

  @Patch('promo-codes/:promoId')
  async patch(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('promoId', ParseUUIDPipe) promoId: string,
    @Body() dto: PromoPatchDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.tools.patchPromo(orgId, id, promoId, dto);
  }

  @Delete('promo-codes/:promoId')
  @HttpCode(200)
  async remove(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Param('promoId', ParseUUIDPipe) promoId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.tools.deletePromo(orgId, id, promoId);
  }

  @Get('attendees.csv')
  async csv(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser, @Res() res: Response) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    const r = await this.tools.attendeesCsv(orgId, id);
    res.type('text/csv; charset=utf-8').setHeader('Content-Disposition', `attachment; filename="${r.filename}"`);
    res.send(r.csv);
  }

  @Get('dashboard')
  async dashboard(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.tools.dashboard(orgId, id);
  }
}

@Module({ controllers: [OrgToolsController], providers: [OrgToolsService] })
export class OrgToolsModule {}
