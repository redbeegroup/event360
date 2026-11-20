import { Body, Controller, Delete, ForbiddenException, Get, HttpCode, Injectable, Module, Param, ParseIntPipe, ParseUUIDPipe, Patch, Post, Put } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { Allow, ArrayMaxSize, IsArray, IsBoolean, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { PrismaService } from '../prisma/prisma.service';
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

/** Public seat availability. `events/:idOrSlug/seats` does not overlap the routes of PublicEventsController. */
@ApiTags('events')
@Controller('events')
export class PublicSeatsController {
  constructor(private readonly seats: EventSeatsService) {}

  @Get(':idOrSlug/seats') get(@Param('idOrSlug') idOrSlug: string) {
    return this.seats.publicSeats(idOrSlug);
  }
}

@Module({
  controllers: [AdminSeatMapsController, OrganizerSeatMapsController, EventSeatingController, PublicSeatsController],
  providers: [SeatMapsService, EventSeatsService, OrgMemberCheck],
  exports: [SeatMapsService, EventSeatsService],
})
export class SeatingModule {}
