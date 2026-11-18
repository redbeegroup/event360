import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { EventStatus } from '@prisma/client';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { TicketsModule, TicketsService } from '../tickets/tickets.module';
import {
  AdminEventsQuery,
  CreateEventDto,
  ListEventsQuery,
  ReasonDto,
  RegisterDto,
  TicketTypeDto,
  UpdateEventDto,
  UpdateTicketTypeDto,
} from './events.dto';
import { EventsService } from './events.service';

@ApiTags('events')
@Controller('events')
export class PublicEventsController {
  constructor(
    private readonly events: EventsService,
    private readonly tickets: TicketsService,
  ) {}

  @Get()
  list(@Query() q: ListEventsQuery) {
    return this.events.listPublic(q);
  }

  @Get(':idOrSlug')
  get(@Param('idOrSlug') idOrSlug: string) {
    return this.events.getPublic(idOrSlug);
  }

  @Post(':id/registrations')
  @Auth()
  register(@Param('id', ParseUUIDPipe) id: string, @Body() dto: RegisterDto, @CurrentUser() user: AuthUser) {
    return this.tickets.registerFree(user.sub, id, dto.ticketTypeId, dto.quantity);
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/events')
@Auth()
export class OrganizerEventsController {
  constructor(
    private readonly events: EventsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get()
  async list(@Param('orgId', ParseUUIDPipe) orgId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.events.listForOrg(orgId);
  }

  @Post()
  async create(@Param('orgId', ParseUUIDPipe) orgId: string, @Body() dto: CreateEventDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.create(orgId, dto);
  }

  @Get(':id')
  async get(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.events.getForOrg(orgId, id);
  }

  @Patch(':id')
  async update(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateEventDto,
    @CurrentUser() u: AuthUser,
  ) {
    const org = await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.update(orgId, id, dto, org.kycStatus === 'APPROVED');
  }

  @Post(':id/submit')
  @HttpCode(200)
  async submit(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    const org = await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.submit(orgId, id, org.kycStatus === 'APPROVED');
  }

  @Post(':id/cancel')
  @HttpCode(200)
  async cancel(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.cancel(orgId, id);
  }

  @Get(':id/attendees')
  async attendees(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.events.attendees(orgId, id);
  }

  @Post(':id/ticket-types')
  async addTicketType(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: TicketTypeDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.addTicketType(orgId, id, dto);
  }

  @Patch(':id/ticket-types/:ttId')
  async updateTicketType(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('ttId', ParseUUIDPipe) ttId: string,
    @Body() dto: UpdateTicketTypeDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.updateTicketType(orgId, id, ttId, dto);
  }

  @Delete(':id/ticket-types/:ttId')
  async deleteTicketType(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('ttId', ParseUUIDPipe) ttId: string,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.events.deleteTicketType(orgId, id, ttId);
  }
}

@ApiTags('admin')
@Controller('admin/events')
@Auth('PLATFORM_ADMIN')
export class AdminEventsController {
  constructor(private readonly events: EventsService) {}

  @Get()
  list(@Query() q: AdminEventsQuery) {
    return this.events.listForAdmin((q.status ?? 'SUBMITTED') as EventStatus);
  }

  @Post(':id/approve')
  @HttpCode(200)
  approve(@Param('id', ParseUUIDPipe) id: string) {
    return this.events.approve(id);
  }

  @Post(':id/reject')
  @HttpCode(200)
  reject(@Param('id', ParseUUIDPipe) id: string, @Body() dto: ReasonDto) {
    return this.events.reject(id, dto.reason);
  }
}

@Module({
  imports: [TicketsModule],
  controllers: [PublicEventsController, OrganizerEventsController, AdminEventsController],
  providers: [EventsService],
})
export class EventsModule {}
