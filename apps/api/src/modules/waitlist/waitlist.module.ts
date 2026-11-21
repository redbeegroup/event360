import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsInt, Max, Min } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { SeatingModule } from '../seating/seating.module';
import { WaitlistService } from './waitlist.service';

export { WaitlistService } from './waitlist.service';

class JoinWaitlistDto {
  @ApiProperty({ minimum: 1, description: "1 to the ticket type's maxPerOrder" }) @IsInt() @Min(1) @Max(50) quantity: number;
}

@ApiTags('waitlist')
@Controller()
@Auth()
export class WaitlistController {
  constructor(private readonly waitlist: WaitlistService) {}

  /** Join the line of a sold-out ticket type (409 while tickets are on sale, and once sales close). */
  @Post('ticket-types/:id/waitlist')
  join(@Param('id', ParseUUIDPipe) id: string, @Body() dto: JoinWaitlistDto, @CurrentUser() u: AuthUser) {
    return this.waitlist.join(u.sub, id, dto.quantity);
  }

  @Delete('ticket-types/:id/waitlist')
  @HttpCode(200)
  leave(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.waitlist.leave(u.sub, id);
  }

  /** The buyer's entries with their place in line, or their live offer (quantity, expiry, seat keys). */
  @Get('me/waitlist')
  mine(@CurrentUser() u: AuthUser) {
    return this.waitlist.mine(u.sub);
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id/waitlist')
@Auth()
export class OrgWaitlistController {
  constructor(
    private readonly waitlist: WaitlistService,
    private readonly access: OrgAccessService,
  ) {}

  @Get()
  async counts(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.waitlist.eventCounts(orgId, id);
  }
}

@Module({
  imports: [SeatingModule],
  controllers: [WaitlistController, OrgWaitlistController],
  providers: [WaitlistService],
  exports: [WaitlistService],
})
export class WaitlistModule {}
