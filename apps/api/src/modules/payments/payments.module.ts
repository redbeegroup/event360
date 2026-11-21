import { Throttle } from '@nestjs/throttler';
import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  HttpCode,
  Module,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  Res,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import type { PayoutMethod } from '@prisma/client';
import type { Response } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_PAYOUT_VIEWERS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { PAYMENT_PROVIDER_FIELDS, PaymentProviderKey, PaymentSettingsService } from '../notifications/settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { SeatingModule } from '../seating/seating.module';
import { WaitlistModule } from '../waitlist/waitlist.module';
import { mockPage, mockResultPage } from './mock-page';
import { PaymentsService } from './payments.service';
import { PAYOUT_METHODS, PayoutsService } from './payouts.service';

export { PaymentsService } from './payments.service';

class RecordPayoutDto {
  @ApiProperty({ minimum: 1 }) @IsInt() @Min(1) @Max(Number.MAX_SAFE_INTEGER) amountMmk: number;
  @ApiProperty() @IsDateString() paidAt: string;
  @ApiProperty({ enum: PAYOUT_METHODS }) @IsIn(PAYOUT_METHODS) method: PayoutMethod;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) reference?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) note?: string;
}

class VoidPayoutDto {
  @ApiProperty() @IsString() @Length(3, 500) reason: string;
}

class OrderItemDto {
  @ApiProperty() @IsUUID() ticketTypeId: string;
  @ApiProperty({ minimum: 1, maximum: 50 }) @IsInt() @Min(1) @Max(50) quantity: number;
}

class CreateOrderDto {
  @ApiPropertyOptional({ type: [OrderItemDto], description: 'Quantity lines (unseated and standing ticket types). Required unless `seats` is given.' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items?: OrderItemDto[];
  @ApiPropertyOptional({ type: [String], description: 'Seated events: seat keys ("<section>:<row>:<seat>"); each seat is one ticket of its assigned type' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @MaxLength(100, { each: true })
  seats?: string[];
  @ApiPropertyOptional({ description: 'Client-generated; repeating the request returns the same order' })
  @IsOptional()
  @IsString()
  @Length(8, 80)
  idempotencyKey?: string;
  @ApiPropertyOptional({ enum: ['APP', 'WEB'] }) @IsOptional() @IsIn(['APP', 'WEB']) channel?: 'APP' | 'WEB';
  @ApiPropertyOptional({ description: 'Promo code' }) @IsOptional() @IsString() @MaxLength(24) promoCode?: string;
  @ApiPropertyOptional({ description: "The buyer's live waitlist offer (GET /me/waitlist): its type is bought from the stock reserved for it" })
  @IsOptional()
  @IsUUID()
  waitlistEntryId?: string;
}

class PromoCheckDto {
  @ApiProperty() @IsString() @Length(3, 24) code: string;
  @ApiPropertyOptional({ type: [OrderItemDto], description: 'Required unless `seats` is given' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items?: OrderItemDto[];
  @ApiPropertyOptional({ type: [String], description: 'Seated events: the chosen seat keys, priced by their ticket type' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @MaxLength(100, { each: true })
  seats?: string[];
}

class PayDto {
  @ApiProperty({ enum: ['KBZPAY', 'WAVEPAY', 'MOCK'] }) @IsIn(['KBZPAY', 'WAVEPAY', 'MOCK', 'kbzpay', 'wavepay', 'mock']) provider: string;
  @ApiPropertyOptional({ description: 'Web only: where to send the buyer back (must be one of our sites)' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  returnUrl?: string;
}

class RefundDto {
  @ApiProperty() @IsString() @Length(3, 500) reason: string;
}

class CompleteRefundDto {
  @ApiProperty({ description: 'Transfer reference of the manual refund' }) @IsString() @Length(2, 200) reference: string;
}

class FeeDto {
  @ApiProperty({ description: 'Basis points: 500 = 5%' }) @IsInt() @Min(0) @Max(5000) percentBp: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(1_000_000) fixedMmk?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(10_000_000) minMmk?: number | null;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) @Max(100_000_000) maxMmk?: number | null;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
}

class PaymentSettingsDto {
  @ApiPropertyOptional({ description: 'Field values; empty secret = keep the current one' }) @IsOptional() @IsObject() values?: Record<string, string>;
  @ApiPropertyOptional({ enum: ['sandbox', 'production'] }) @IsOptional() @IsIn(['sandbox', 'production']) mode?: 'sandbox' | 'production';
  @ApiPropertyOptional() @IsOptional() @IsBoolean() enabled?: boolean;
}

const providerKey = (p: string): PaymentProviderKey => {
  const k = p.toLowerCase();
  if (!(k in PAYMENT_PROVIDER_FIELDS)) throw new NotFoundException('Unknown payment provider');
  return k as PaymentProviderKey;
};

@ApiTags('checkout')
@Controller()
export class CheckoutController {
  constructor(private readonly payments: PaymentsService) {}

  @Post('events/:id/orders')
  @Auth()
  create(@Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateOrderDto, @CurrentUser() u: AuthUser) {
    return this.payments.createOrder(u.sub, id, dto.items ?? [], dto.idempotencyKey, dto.channel, dto.promoCode, dto.seats, dto.waitlistEntryId);
  }

  @Throttle({ default: { ttl: 60_000, limit: 10 } }) // codes can't be guessed by brute force
  @Post('events/:id/promo-check')
  @Auth()
  @HttpCode(200)
  promoCheck(@Param('id', ParseUUIDPipe) id: string, @Body() dto: PromoCheckDto) {
    return this.payments.previewPromo(id, dto.code, dto.items ?? [], dto.seats);
  }

  @Get('me/orders')
  @Auth()
  mine(@CurrentUser() u: AuthUser, @Query('pending') pending?: string) {
    return this.payments.myOrders(u.sub, pending === '1' || pending === 'true');
  }

  @Get('orders/:id')
  @Auth()
  get(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.payments.orderView(u.sub, id);
  }

  @Post('orders/:id/pay')
  @Auth()
  @HttpCode(200)
  pay(@Param('id', ParseUUIDPipe) id: string, @Body() dto: PayDto, @CurrentUser() u: AuthUser) {
    return this.payments.pay(u.sub, id, dto.provider, dto.returnUrl);
  }

  @Post('orders/:id/cancel')
  @Auth()
  @HttpCode(200)
  cancel(@Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    return this.payments.cancel(u.sub, id);
  }
}

@ApiTags('payments')
@Controller('payments')
export class PaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly prisma: PrismaService,
  ) {}

  @Get('methods')
  methods() {
    return this.payments.methods();
  }

  /** Provider callbacks (signature-checked; raw payload always stored). */
  @Throttle({ default: { ttl: 60_000, limit: 300 } })
  @Post('webhook/:provider')
  @HttpCode(200)
  async webhook(@Param('provider') provider: string, @Headers() headers: Record<string, string>, @Body() body: unknown, @Res() res: Response) {
    const ack = await this.payments.webhook(provider, headers, body);
    res.status(200).type(ack.contentType).send(ack.body);
  }

  /** Where a wallet's web checkout sends the buyer when no app URL was given. */
  @Get('done')
  done(@Res() res: Response) {
    res.type('html').send(mockResultPage({ outcome: 'done' }));
  }

  // ───────────── dev-only test wallet ─────────────

  private async mockPayment(id: string, t: string) {
    if (!(await this.payments.mock.available())) throw new NotFoundException();
    if (!t || t !== this.payments.mock.pageToken(id)) throw new ForbiddenException('Invalid link');
    const p = await this.prisma.payment.findUnique({ where: { id }, include: { order: { include: { event: { select: { title: true } } } } } });
    if (!p || p.provider !== 'MOCK' || !p.order) throw new NotFoundException();
    return p;
  }

  @Get('mock/:id')
  async mockCheckout(@Param('id', ParseUUIDPipe) id: string, @Query('t') t: string, @Res() res: Response) {
    const p = await this.mockPayment(id, t);
    res.type('html').send(mockPage({ id, t, amount: p.amountMmk, title: p.order!.event.title, status: p.status }));
  }

  @Post('mock/:id/:outcome')
  async mockOutcome(@Param('id', ParseUUIDPipe) id: string, @Param('outcome') outcome: string, @Body('t') t: string, @Res() res: Response) {
    const p = await this.mockPayment(id, t);
    if (!['pay', 'fail', 'silent'].includes(outcome)) throw new BadRequestException();
    const status = outcome === 'fail' ? 'FAILED' : 'SUCCEEDED';
    await this.payments.mock.recordState(id, status);
    if (outcome !== 'silent') {
      const cb = this.payments.mock.callbackFor(id, status, p.amountMmk);
      await this.payments.webhook('mock', { 'x-mock-signature': cb.signature }, cb.body);
    }
    const returnUrl = (p.action as { returnUrl?: string } | null)?.returnUrl;
    res.type('html').send(mockResultPage({ outcome, returnUrl }));
  }
}

@ApiTags('admin')
@Controller('admin')
@Auth('PLATFORM_ADMIN')
export class AdminFinanceController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly settings: PaymentSettingsService,
    private readonly payouts: PayoutsService,
  ) {}

  @Post('finance/organizations/:orgId/payouts')
  recordPayout(@Param('orgId', ParseUUIDPipe) orgId: string, @Body() dto: RecordPayoutDto, @CurrentUser() u: AuthUser) {
    return this.payouts.record(orgId, dto, u.sub);
  }

  @Get('finance/organizations/:orgId/payouts')
  listPayouts(@Param('orgId', ParseUUIDPipe) orgId: string) {
    return this.payouts.list(orgId);
  }

  @Post('finance/payouts/:id/void')
  @HttpCode(200)
  voidPayout(@Param('id', ParseUUIDPipe) id: string, @Body() dto: VoidPayoutDto, @CurrentUser() u: AuthUser) {
    return this.payouts.void(id, dto.reason, u.sub);
  }

  @Get('finance/orders')
  orders(@Query('status') status?: string, @Query('review') review?: string, @Query('q') q?: string, @Query('limit') limit?: string) {
    return this.payments.adminOrders({ status: status || undefined, review: review === '1' || review === 'true', search: q, limit: Number(limit) || 50 });
  }

  @Get('finance/orders/:id')
  order(@Param('id', ParseUUIDPipe) id: string) {
    return this.payments.adminOrder(id);
  }

  @Post('finance/orders/:id/refund')
  @HttpCode(200)
  refund(@Param('id', ParseUUIDPipe) id: string, @Body() dto: RefundDto, @CurrentUser() u: AuthUser) {
    return this.payments.refundOrder(id, dto.reason, u.sub);
  }

  @Post('finance/refunds/:id/retry')
  @HttpCode(200)
  retry(@Param('id', ParseUUIDPipe) id: string) {
    return this.payments.sendRefund(id);
  }

  @Post('finance/refunds/:id/complete')
  @HttpCode(200)
  complete(@Param('id', ParseUUIDPipe) id: string, @Body() dto: CompleteRefundDto, @CurrentUser() u: AuthUser) {
    return this.payments.completeRefund(id, { reference: dto.reference, actorId: u.sub });
  }

  @Get('finance/balances')
  balances() {
    return this.payments.balances();
  }

  @Get('finance/balances.csv')
  async balancesCsv(@Res() res: Response) {
    const rows = await this.payments.balances();
    const esc = (v: unknown) => `"${String(v).replace(/"/g, '""')}"`;
    const csv = [
      'organization,organization_id,orders,gross_mmk,refunded_mmk,commission_mmk,paid_out_mmk,owed_mmk',
      ...rows.map((r) => [r.organization, r.organizationId, r.orders, r.grossMmk, r.refundedMmk, r.commissionMmk, r.paidOutMmk, r.owedMmk].map(esc).join(',')),
    ].join('\n');
    res.type('text/csv').setHeader('Content-Disposition', 'attachment; filename="event360-balances.csv"');
    res.send(csv);
  }

  @Get('finance/fee')
  fee() {
    return this.payments.globalFee();
  }

  @Put('finance/fee')
  setFee(@Body() dto: FeeDto, @CurrentUser() u: AuthUser) {
    return this.payments.setGlobalFee(dto, u.sub);
  }

  @Get('settings/payments')
  async allSettings() {
    return Promise.all(
      (Object.keys(PAYMENT_PROVIDER_FIELDS) as PaymentProviderKey[]).map(async (k) => ({
        ...(await this.settings.view(k)),
        callbackUrl: `${this.payments.apiBase}/v1/payments/webhook/${k}`,
      })),
    );
  }

  @Get('settings/payments/:provider')
  getSettings(@Param('provider') p: string) {
    return this.settings.view(providerKey(p));
  }

  @Put('settings/payments/:provider')
  async putSettings(@Param('provider') p: string, @Body() dto: PaymentSettingsDto, @CurrentUser() u: AuthUser) {
    try {
      return await this.settings.update(providerKey(p), dto, u.sub);
    } catch (e) {
      throw new ServiceUnavailableException((e as Error).message);
    }
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/events/:id/sales')
@Auth()
export class OrgSalesController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get()
  async sales(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.payments.eventSales(orgId, id);
  }
}

@ApiTags('organizer')
@Controller('organizations/:orgId/payouts')
@Auth()
export class OrgPayoutsController {
  constructor(
    private readonly payouts: PayoutsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get('summary')
  async summary(@Param('orgId', ParseUUIDPipe) orgId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_PAYOUT_VIEWERS);
    return this.payouts.summary(orgId);
  }

  @Get('summary.csv')
  async summaryCsv(@Param('orgId', ParseUUIDPipe) orgId: string, @CurrentUser() u: AuthUser, @Res() res: Response) {
    await this.access.assert(u, orgId, ORG_PAYOUT_VIEWERS);
    const s = await this.payouts.summary(orgId);
    const esc = (v: unknown) => {
      let t = String(v ?? '');
      if (/^[=+\-@\t\r]/.test(t)) t = `'${t}`; // spreadsheet formula injection
      return `"${t.replace(/"/g, '""')}"`;
    };
    const csv = [
      'event,gross_mmk,discount_mmk,commission_mmk,refunds_mmk,net_mmk',
      ...s.events.map((e) => [e.title, e.grossMmk, e.discountMmk, e.commissionMmk, e.refundsMmk, e.netMmk].map(esc).join(',')),
      '',
      'earned_mmk,paid_out_mmk,owed_mmk',
      [s.earnedMmk, s.paidOutMmk, s.owedMmk].map(esc).join(','),
      '',
      'paid_at,amount_mmk,method,reference,note,voided',
      ...s.payouts.map((p) => [p.paidAt.toISOString(), p.amountMmk, p.method, p.reference, p.note, p.voidedAt ? 'yes' : 'no'].map(esc).join(',')),
    ].join('\n');
    res.type('text/csv').setHeader('Content-Disposition', 'attachment; filename="event360-payouts.csv"');
    res.send(csv);
  }
}

@Module({
  imports: [SeatingModule, WaitlistModule],
  controllers: [CheckoutController, PaymentsController, AdminFinanceController, OrgSalesController, OrgPayoutsController],
  providers: [PaymentsService, PayoutsService],
  exports: [PaymentsService],
})
export class PaymentsModule {}
