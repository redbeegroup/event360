import { BadRequestException, Body, ConflictException, Controller, Get, HttpCode, NotFoundException, Param, ParseUUIDPipe, Post, Put, Query, ServiceUnavailableException } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { PrismaService } from '../prisma/prisma.service';
import { NotifyService } from './notify.service';
import { PushSettingsService } from './settings.service';

class ReadDto {
  @ApiPropertyOptional({ description: 'Notification ids; omit to mark all read' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsUUID('all', { each: true })
  ids?: string[];
}

class DeviceDto {
  @ApiProperty() @IsString() @Length(20, 4096) pushToken: string;
  @ApiProperty({ enum: ['android', 'ios', 'web'] }) @IsIn(['android', 'ios', 'web']) platform: string;
  @ApiPropertyOptional({ enum: ['user_app', 'crew_app', 'organizer_app'] }) @IsOptional() @IsIn(['user_app', 'crew_app', 'organizer_app']) appId?: string;
}

class RemoveDeviceDto {
  @ApiProperty() @IsString() @Length(20, 4096) pushToken: string;
}

class PushSettingsDto {
  @ApiPropertyOptional({ description: 'Contents of the Firebase service account JSON key; empty = keep' }) @IsOptional() @IsString() @MaxLength(20_000) serviceAccountJson?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() enabled?: boolean;
}

class AnnouncementDto {
  @ApiProperty() @IsString() @Length(3, 80) title: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) titleMy?: string;
  @ApiProperty() @IsString() @Length(3, 500) body: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) bodyMy?: string;
}

export const ANNOUNCEMENTS_PER_DAY = 3;

@ApiTags('notifications')
@Controller('me')
@Auth()
export class InboxController {
  constructor(private readonly prisma: PrismaService) {}

  @Get('notifications')
  async list(@CurrentUser() u: AuthUser, @Query('before') before?: string, @Query('limit') limit?: string) {
    const take = Math.min(Number(limit) || 30, 100);
    const cursor = before && !Number.isNaN(Date.parse(before)) ? new Date(before) : undefined;
    const [items, unread] = await Promise.all([
      this.prisma.notification.findMany({
        where: { userId: u.sub, ...(cursor ? { createdAt: { lt: cursor } } : {}) },
        orderBy: { createdAt: 'desc' },
        take,
        select: { id: true, kind: true, title: true, titleMy: true, body: true, bodyMy: true, link: true, eventId: true, readAt: true, createdAt: true },
      }),
      this.prisma.notification.count({ where: { userId: u.sub, readAt: null } }),
    ]);
    return { items, unread };
  }

  @Post('notifications/read')
  @HttpCode(200)
  async read(@CurrentUser() u: AuthUser, @Body() dto: ReadDto) {
    const r = await this.prisma.notification.updateMany({
      where: { userId: u.sub, readAt: null, ...(dto.ids?.length ? { id: { in: dto.ids } } : {}) },
      data: { readAt: new Date() },
    });
    return { updated: r.count };
  }

  /** Registers this device's push token for the signed-in user (moves it if another account used this phone). */
  @Post('devices')
  @HttpCode(200)
  async device(@CurrentUser() u: AuthUser, @Body() dto: DeviceDto) {
    if (u.typ === 'crew') throw new BadRequestException('Not for crew sessions');
    await this.prisma.device.upsert({
      where: { pushToken: dto.pushToken },
      create: { userId: u.sub, pushToken: dto.pushToken, platform: dto.platform, appId: dto.appId ?? 'user_app' },
      update: { userId: u.sub, platform: dto.platform, appId: dto.appId ?? 'user_app', lastSeen: new Date() },
    });
    return { ok: true };
  }

  /** Called on sign-out so the phone stops getting this user's notifications. */
  @Post('devices/remove')
  @HttpCode(200)
  async removeDevice(@CurrentUser() u: AuthUser, @Body() dto: RemoveDeviceDto) {
    const r = await this.prisma.device.deleteMany({ where: { userId: u.sub, pushToken: dto.pushToken } });
    return { removed: r.count };
  }
}

@ApiTags('admin')
@Controller('admin/settings/push')
@Auth('PLATFORM_ADMIN')
export class AdminPushController {
  constructor(
    private readonly settings: PushSettingsService,
    private readonly notify: NotifyService,
    private readonly prisma: PrismaService,
  ) {}

  @Get()
  async get(@CurrentUser() u: AuthUser) {
    const devices = await this.prisma.device.count({ where: { pushToken: { not: null } } });
    const mine = await this.prisma.device.count({ where: { userId: u.sub, pushToken: { not: null } } });
    return { ...(await this.settings.view()), devices, myDevices: mine };
  }

  @Put()
  async put(@Body() dto: PushSettingsDto, @CurrentUser() u: AuthUser) {
    try {
      return await this.settings.update(dto, u.sub);
    } catch (e) {
      throw new ServiceUnavailableException((e as Error).message);
    }
  }

  /** Sends a test notification to the admin's own inbox and devices. */
  @Post('test')
  @HttpCode(200)
  async test(@CurrentUser() u: AuthUser) {
    await this.notify.deliver([u.sub], { kind: 'test', title: 'Event 360 test', titleMy: 'Event 360 စမ်းသပ်', body: 'Push notifications are working.', bodyMy: 'Push အသိပေးချက်များ အလုပ်လုပ်ပါသည်။' });
    return { ok: true, devices: await this.prisma.device.count({ where: { userId: u.sub, pushToken: { not: null } } }) };
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id/announcements')
@Auth()
export class AnnouncementsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly access: OrgAccessService,
    private readonly notify: NotifyService,
  ) {}

  private async event(orgId: string, id: string) {
    const e = await this.prisma.event.findFirst({ where: { id, organizationId: orgId }, select: { id: true, status: true, title: true, publishedAt: true } });
    if (!e) throw new NotFoundException('Event not found');
    return e;
  }

  @Get()
  async list(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    await this.event(orgId, id);
    const [items, holders, today] = await Promise.all([
      this.prisma.announcement.findMany({ where: { eventId: id }, orderBy: { createdAt: 'desc' }, take: 50 }),
      this.notify.holders(id),
      this.prisma.announcement.count({ where: { eventId: id, createdAt: { gt: new Date(Date.now() - 24 * 3600e3) } } }),
    ]);
    return { items, ticketHolders: holders.length, remainingToday: Math.max(0, ANNOUNCEMENTS_PER_DAY - today) };
  }

  @Post()
  async create(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AnnouncementDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    const e = await this.event(orgId, id);
    if (!e.publishedAt || ['CANCELLED', 'COMPLETED', 'DRAFT'].includes(e.status)) throw new ConflictException('Announcements can only be sent for published events');
    const today = await this.prisma.announcement.count({ where: { eventId: id, createdAt: { gt: new Date(Date.now() - 24 * 3600e3) } } });
    if (today >= ANNOUNCEMENTS_PER_DAY) throw new ConflictException(`At most ${ANNOUNCEMENTS_PER_DAY} announcements per event per day`);
    const holders = await this.notify.holders(id);
    const a = await this.prisma.$transaction(async (tx) => {
      const row = await tx.announcement.create({
        data: { eventId: id, createdById: u.sub, title: dto.title.trim(), titleMy: dto.titleMy?.trim() || null, body: dto.body.trim(), bodyMy: dto.bodyMy?.trim() || null, recipients: holders.length },
      });
      await tx.auditLog.create({ data: { actorId: u.sub, action: 'event.announcement', entityType: 'event', entityId: id, data: { announcementId: row.id, recipients: holders.length } } });
      return row;
    });
    void this.notify.toUsers(holders, {
      kind: 'announcement',
      title: `${e.title}: ${a.title}`.slice(0, 120),
      titleMy: a.titleMy ? `${e.title}: ${a.titleMy}`.slice(0, 120) : null,
      body: a.body,
      bodyMy: a.bodyMy,
      link: `/event/${id}`,
      eventId: id,
    });
    return a;
  }
}
