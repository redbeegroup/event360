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
  ArrayMinSize,
  IsArray,
  IsBoolean,
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
import type { Response } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { PAYMENT_PROVIDER_FIELDS, PaymentProviderKey, PaymentSettingsService } from '../notifications/settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { mockPage, mockResultPage } from './mock-page';
import { PaymentsService } from './payments.service';

export { PaymentsService } from './payments.service';

class OrderItemDto {
  @ApiProperty() @IsUUID() ticketTypeId: string;
  @ApiProperty({ minimum: 1, maximum: 50 }) @IsInt() @Min(1) @Max(50) quantity: number;
}

class CreateOrderDto {
  @ApiProperty({ type: [OrderItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[];
  @ApiPropertyOptional({ description: 'Client-generated; repeating the request returns the same order' })
  @IsOptional()
  @IsString()
  @Length(8, 80)
  idempotencyKey?: string;
  @ApiPropertyOptional({ enum: ['APP', 'WEB'] }) @IsOptional() @IsIn(['APP', 'WEB']) channel?: 'APP' | 'WEB';
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
    return this.payments.createOrder(u.sub, id, dto.items, dto.idempotencyKey, dto.channel);
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
  ) {}

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
      'organization,organization_id,orders,gross_mmk,refunded_mmk,commission_mmk,owed_mmk',
      ...rows.map((r) => [r.organization, r.organizationId, r.orders, r.grossMmk, r.refundedMmk, r.commissionMmk, r.owedMmk].map(esc).join(',')),
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

@Module({
  controllers: [CheckoutController, PaymentsController, AdminFinanceController, OrgSalesController],
  providers: [PaymentsService],
  exports: [PaymentsService],
})
export class PaymentsModule {}
