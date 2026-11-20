import { Body, Controller, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { TicketTokenService } from './ticket-token.service';
import { TicketsService } from './tickets.service';

export { TicketsService } from './tickets.service';

class TransferDto {
  @ApiProperty({ example: '09xxxxxxxxx' }) @IsString() @Length(6, 20) phone: string;
}

@ApiTags('tickets')
@Controller('me/tickets')
@Auth()
export class MyTicketsController {
  constructor(private readonly tickets: TicketsService) {}

  @Get()
  list(@CurrentUser() u: AuthUser) {
    return this.tickets.myTickets(u.sub);
  }

  @Get(':id')
  get(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.tickets.myTicket(u.sub, id);
  }

  @Post(':id/transfer')
  @HttpCode(200)
  transfer(@Param('id', ParseUUIDPipe) id: string, @Body() dto: TransferDto, @CurrentUser() u: AuthUser) {
    return this.tickets.transfer(u.sub, id, dto.phone);
  }
}

@ApiTags('meta')
@Controller('meta')
export class MetaController {
  constructor(private readonly tokens: TicketTokenService) {}

  /** Public key crew apps use to verify ticket QR codes offline. */
  @Get('ticket-public-key')
  ticketPublicKey() {
    return { alg: 'Ed25519', publicKey: this.tokens.publicKeyRaw() };
  }

  /** What the API sees as the caller's IP (checks the NPMPlus → Traefik → API proxy chain). */
  @Get('client')
  client(@Req() req: Request) {
    return { ip: req.ip, forwardedFor: req.headers['x-forwarded-for'] ?? null, protocol: req.protocol };
  }
}

@Module({
  controllers: [MyTicketsController, MetaController],
  providers: [TicketsService, TicketTokenService],
  exports: [TicketsService, TicketTokenService],
})
export class TicketsModule {}
