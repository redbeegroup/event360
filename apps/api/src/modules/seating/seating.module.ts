import { Body, ConflictException, Controller, Delete, ForbiddenException, Get, Header, HttpCode, Injectable, Module, Param, ParseIntPipe, ParseUUIDPipe, Patch, Post, Put, Query, Res } from '@nestjs/common';
import type { Response } from 'express';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { SkipThrottle, Throttle } from '@nestjs/throttler';
import { Transform, Type } from 'class-transformer';
import { Allow, ArrayMaxSize, ArrayMinSize, IsArray, Matches, IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { PrismaService } from '../prisma/prisma.service';
import { TicketsModule } from '../tickets/tickets.module';
import { GuestsService } from './guests.service';
import { EventSeatsService } from './event-seats.service';
import { SeatMapsService } from './seat-maps.service';

class SeatMapDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(200) venueName: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) venueNameMy?: string;
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) city: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) address?: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-90) @Max(90) latitude?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-180) @Max(180) longitude?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) mapUrl?: string;
}

class SeatMapPatchDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(1) @MaxLength(200) venueName?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) venueNameMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(1) @MaxLength(100) city?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) address?: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-90) @Max(90) latitude?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-180) @Max(180) longitude?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) mapUrl?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
}

/** `layout` is validated by validateLayout (returns 400 with `problems`), not by class-validator. */
class LayoutDto {
  @ApiProperty({ type: 'object', additionalProperties: true }) @Allow() layout: unknown;
}

@ApiTags('admin')
@Controller('admin/seat-maps')
@Auth('PLATFORM_ADMIN')
export class AdminSeatMapsController {
  constructor(private readonly maps: SeatMapsService) {}

  @Get() list() {
    return this.maps.list();
  }

  @Post() create(@Body() dto: SeatMapDto) {
    return this.maps.create(dto);
  }

  @Get(':id') get(@Param('id', ParseUUIDPipe) id: string) {
    return this.maps.get(id);
  }

  @Patch(':id') update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: SeatMapPatchDto) {
    return this.maps.update(id, dto);
  }

  @Get(':id/versions/:version') version(@Param('id', ParseUUIDPipe) id: string, @Param('version', ParseIntPipe) version: number) {
    return this.maps.version(id, version);
  }

  @Put(':id/draft') draft(@Param('id', ParseUUIDPipe) id: string, @Body() dto: LayoutDto, @CurrentUser() u: AuthUser) {
    return this.maps.saveDraft(id, dto.layout, u.sub);
  }

  @Post(':id/import') @HttpCode(200) import(@Param('id', ParseUUIDPipe) id: string, @Body() dto: LayoutDto, @CurrentUser() u: AuthUser) {
    return this.maps.saveDraft(id, dto.layout, u.sub);
  }

  @Post(':id/publish') @HttpCode(200) publish(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.maps.publish(id, u.sub);
  }
}

@Injectable()
class OrgMemberCheck {
  constructor(private readonly prisma: PrismaService) {}
  async assert(u: AuthUser) {
    if (u.roles?.includes('PLATFORM_ADMIN')) return;
    if (!(await this.prisma.organizationMember.count({ where: { userId: u.sub } }))) throw new ForbiddenException('Organizer access required');
  }
}

@ApiTags('organizer')
@Controller('seat-maps')
@Auth()
export class OrganizerSeatMapsController {
  constructor(
    private readonly maps: SeatMapsService,
    private readonly member: OrgMemberCheck,
  ) {}

  @Get() async list(@CurrentUser() u: AuthUser) {
    await this.member.assert(u);
    return this.maps.listPublished();
  }
}

class PickMapDto {
  @ApiProperty() @IsUUID() seatMapVersionId: string;
}

class RuleDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(100) sectionKey: string;
  @ApiPropertyOptional({ description: 'Omit for the whole section' }) @IsOptional() @IsString() @MinLength(1) @MaxLength(100) rowLabel?: string;
  @ApiProperty() @IsUUID() ticketTypeId: string;
}

class AssignmentsDto {
  @ApiProperty({ type: [RuleDto] }) @IsArray() @ArrayMaxSize(2000) @ValidateNested({ each: true }) @Type(() => RuleDto) rules: RuleDto[];
}

/** Organizer: pick a venue map for an event and assign sections/rows to ticket types. */
@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id/seating')
@Auth()
export class EventSeatingController {
  constructor(
    private readonly seats: EventSeatsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get() async get(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.seats.overview(orgId, id);
  }

  @Put('map') async setMap(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PickMapDto, @CurrentUser() u: AuthUser) {
    const org = await this.access.assert(u, orgId, ORG_EDITORS);
    return this.seats.setMap(orgId, id, dto.seatMapVersionId, org.kycStatus === 'APPROVED');
  }

  @Delete('map') async clearMap(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    const org = await this.access.assert(u, orgId, ORG_EDITORS);
    return this.seats.clearMap(orgId, id, org.kycStatus === 'APPROVED');
  }

  @Put('assignments') async assign(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AssignmentsDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.seats.setAssignments(orgId, id, dto.rules);
  }
}

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

class SeatKeysDto {
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(200) @IsString({ each: true }) @MaxLength(300, { each: true }) seats: string[];
}

class HoldDto extends SeatKeysDto {
  @ApiProperty() @Transform(trim) @IsString() @Matches(/\S/, { message: 'label must not be blank' }) @MaxLength(100) label: string;
}

class CompsDto extends SeatKeysDto {
  @ApiProperty() @Transform(trim) @IsString() @Matches(/\S/, { message: 'guestName must not be blank' }) @MaxLength(200) guestName: string;
  @ApiProperty() @IsString() @MinLength(5) @MaxLength(30) phone: string;
  @ApiPropertyOptional() @Transform(trim) @IsOptional() @IsString() @MaxLength(100) label?: string;
}

/** Organizer: hold seats for guests, issue and revoke complimentary tickets, print them. */
@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id/seating')
@Auth()
export class EventGuestsController {
  constructor(
    private readonly guests: GuestsService,
    private readonly access: OrgAccessService,
  ) {}

  @Post('hold') async hold(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: HoldDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.guests.hold(orgId, id, dto.seats, dto.label);
  }

  @Post('release') @HttpCode(200) async release(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SeatKeysDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.guests.release(orgId, id, dto.seats);
  }

  @Post('comps') async issue(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CompsDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.guests.issue(orgId, id, dto);
  }

  @Get('guests') async list(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.guests.list(orgId, id);
  }

  @Post('comps/:ticketId/revoke') @HttpCode(200)
  async revoke(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Param('ticketId', ParseUUIDPipe) ticketId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.guests.revoke(orgId, id, ticketId);
  }

  /** Same tickets as comps.pdf, as JSON for the portal's print page. Editors only: the tokens are live QR codes. */
  @Get('comps/print') @Header('Cache-Control', 'no-store') async printData(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Query('ids') ids: string | undefined, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.guests.printData(orgId, id, ids);
  }

  /** Printable guest tickets (the QR codes are live tickets, so editors only). */
  @Get('comps.pdf') async pdf(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @Query('ids') ids: string | undefined, @CurrentUser() u: AuthUser, @Res() res: Response) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    const pdf = await this.guests.pdf(orgId, id, ids);
    res.set({ 'Content-Type': 'application/pdf', 'Content-Length': String(pdf.length), 'Content-Disposition': 'inline; filename="guest-tickets.pdf"', 'Cache-Control': 'no-store' });
    res.send(pdf);
  }
}

class BestSeatsDto {
  @ApiProperty() @IsUUID() ticketTypeId: string;
  @ApiProperty({ minimum: 1, maximum: 20 }) @IsInt() @Min(1) @Max(20) quantity: number;
}

/** Public seat availability. `events/:idOrSlug/seats` does not overlap the routes of PublicEventsController. */
@ApiTags('events')
@Controller('events')
export class PublicSeatsController {
  constructor(private readonly seats: EventSeatsService) {}

  /** Polled by every open seat picker and served from a short cache, so it skips the per-IP limit (a venue shares one IP). */
  @Get(':idOrSlug/seats') @SkipThrottle()
  get(@Param('idOrSlug') idOrSlug: string) {
    return this.seats.publicSeats(idOrSlug);
  }

  /** Suggests seats; holds nothing. The buyer then submits them to createOrder. */
  @Post(':idOrSlug/seats/best') @HttpCode(200) @Throttle({ default: { ttl: 60_000, limit: 20 } })
  async best(@Param('idOrSlug') idOrSlug: string, @Body() dto: BestSeatsDto) {
    const seats = await this.seats.bestSeats(idOrSlug, dto.ticketTypeId, dto.quantity);
    if (!seats) throw new ConflictException({ message: 'Not enough seats together', seats: [] });
    return { seats };
  }
}

@Module({
  imports: [TicketsModule],
  controllers: [AdminSeatMapsController, OrganizerSeatMapsController, EventSeatingController, EventGuestsController, PublicSeatsController],
  providers: [SeatMapsService, EventSeatsService, GuestsService, OrgMemberCheck],
  exports: [SeatMapsService, EventSeatsService],
})
export class SeatingModule {}
