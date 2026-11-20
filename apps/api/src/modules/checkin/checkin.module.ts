import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsIn, IsISO8601, IsOptional, IsString, IsUUID, Length, MaxLength, ValidateNested } from 'class-validator';
import { Auth, AuthUser, CrewAuth, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { TicketsModule } from '../tickets/tickets.module';
import { CheckinService } from './checkin.service';

class ScanMetaDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(60) gate?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(100) deviceId?: string;
  @ApiPropertyOptional() @IsOptional() @IsISO8601() scannedAt?: string;
}

class ScanDto extends ScanMetaDto {
  @ApiProperty() @IsString() @Length(10, 2000) qr: string;
}

class SyncItemDto extends ScanMetaDto {
  @ApiProperty() @IsString() @MaxLength(100) clientId: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(10, 2000) qr?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() ticketId?: string;
  @ApiPropertyOptional({ enum: ['QR', 'MANUAL'] }) @IsOptional() @IsIn(['QR', 'MANUAL']) method?: 'QR' | 'MANUAL';
}

class SyncDto {
  @ApiProperty({ type: [SyncItemDto] }) @IsArray() @ArrayMaxSize(500) @ValidateNested({ each: true }) @Type(() => SyncItemDto) scans: SyncItemDto[];
}

class RedeemDto {
  @ApiProperty({ example: 'K7QM-4XRT' }) @IsString() @Length(8, 20) code: string;
  @ApiProperty({ example: 'Gate A phone' }) @IsString() @Length(1, 60) deviceName: string;
}

class CreateCodeDto {
  @ApiProperty({ example: 'Volunteers – main gate' }) @IsString() @Length(1, 80) label: string;
  @ApiPropertyOptional({ example: 'Main gate' }) @IsOptional() @IsString() @MaxLength(60) gate?: string;
}

/** Door staff: invited crew accounts (and organizer staff) or volunteer devices on an event code. */
@ApiTags('crew')
@Controller('crew')
export class CrewController {
  constructor(private readonly checkin: CheckinService) {}

  @Post('redeem')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  redeem(@Body() dto: RedeemDto) {
    return this.checkin.redeem(dto.code, dto.deviceName);
  }

  @Get('events')
  @CrewAuth()
  events(@CurrentUser() u: AuthUser) {
    return this.checkin.crewEvents(u);
  }

  @Get('events/:eventId/manifest')
  @CrewAuth()
  async manifest(@Param('eventId', ParseUUIDPipe) eventId: string, @CurrentUser() u: AuthUser) {
    await this.checkin.assertEvent(u, eventId);
    return this.checkin.manifest(eventId);
  }

  @Post('events/:eventId/scan')
  @HttpCode(200)
  @CrewAuth()
  async scan(@Param('eventId', ParseUUIDPipe) eventId: string, @Body() dto: ScanDto, @CurrentUser() u: AuthUser) {
    const { actor } = await this.checkin.assertEvent(u, eventId);
    return this.checkin.scan(actor, eventId, dto.qr, dto);
  }

  @Post('events/:eventId/sync')
  @HttpCode(200)
  @CrewAuth()
  async sync(@Param('eventId', ParseUUIDPipe) eventId: string, @Body() dto: SyncDto, @CurrentUser() u: AuthUser) {
    const { actor } = await this.checkin.assertEvent(u, eventId);
    return this.checkin.sync(actor, eventId, dto.scans);
  }

  @Get('events/:eventId/search')
  @CrewAuth()
  async search(@Param('eventId', ParseUUIDPipe) eventId: string, @Query('q') q: string, @CurrentUser() u: AuthUser) {
    await this.checkin.assertEvent(u, eventId);
    return this.checkin.search(eventId, String(q ?? '').slice(0, 60));
  }

  @Post('events/:eventId/tickets/:ticketId/checkin')
  @HttpCode(200)
  @CrewAuth()
  async manual(
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('ticketId', ParseUUIDPipe) ticketId: string,
    @Body() dto: ScanMetaDto,
    @CurrentUser() u: AuthUser,
  ) {
    const { actor } = await this.checkin.assertEvent(u, eventId);
    return this.checkin.manualCheckin(actor, eventId, ticketId, dto);
  }

  @Post('events/:eventId/tickets/:ticketId/undo')
  @HttpCode(200)
  @CrewAuth()
  async undo(@Param('eventId', ParseUUIDPipe) eventId: string, @Param('ticketId', ParseUUIDPipe) ticketId: string, @CurrentUser() u: AuthUser) {
    const { actor } = await this.checkin.assertEvent(u, eventId);
    return this.checkin.undo(actor, eventId, ticketId);
  }

  @Get('events/:eventId/stats')
  @CrewAuth()
  async stats(@Param('eventId', ParseUUIDPipe) eventId: string, @CurrentUser() u: AuthUser) {
    await this.checkin.assertEvent(u, eventId);
    return this.checkin.stats(eventId);
  }
}

/** Organizer side: event codes for volunteers and live attendance. */
@ApiTags('organizer')
@Controller('organizations/:orgId/events/:eventId')
@Auth()
export class OrgCheckinController {
  constructor(
    private readonly checkin: CheckinService,
    private readonly access: OrgAccessService,
  ) {}

  @Get('crew-codes')
  async list(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.checkin.listCodes(orgId, eventId);
  }

  @Post('crew-codes')
  async create(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Body() dto: CreateCodeDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.checkin.createCode(orgId, eventId, u.sub, dto.label, dto.gate);
  }

  @Delete('crew-codes/:codeId')
  async revoke(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('codeId', ParseUUIDPipe) codeId: string,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.checkin.revokeCode(orgId, eventId, codeId);
  }

  @Get('attendance')
  async attendance(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.checkin.attendanceForOrg(orgId, eventId);
  }
}

@Module({
  imports: [TicketsModule],
  controllers: [CrewController, OrgCheckinController],
  providers: [CheckinService],
})
export class CheckinModule {}
