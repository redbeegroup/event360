import { BadRequestException, Body, Controller, Get, Global, HttpCode, Module, Post, Put, Query, ServiceUnavailableException } from '@nestjs/common';
import { ApiPropertyOptional, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { normalizeMyanmarPhone } from '../auth/phone';
import { AdminPushController, AnnouncementsController, InboxController } from './inbox.controller';
import { NotifyService } from './notify.service';
import { PaymentSettingsService, PushSettingsService, SettingsService } from './settings.service';
import { SmsError, SmsService } from './sms.service';

export { SmsService } from './sms.service';
export { SettingsService, PaymentSettingsService, PushSettingsService } from './settings.service';
export { NotifyService } from './notify.service';

class SmsSettingsDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) apiKey?: string;
  @ApiPropertyOptional({ description: 'Leave empty to keep the current secret' }) @IsOptional() @IsString() @MaxLength(500) apiSecret?: string;
  @ApiPropertyOptional({ example: 'Event360' }) @IsOptional() @IsString() @MaxLength(20) senderId?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() enabled?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() testMode?: boolean;
  @ApiPropertyOptional({ example: 'Your Event 360 code is {code}. Valid {minutes} minutes.' })
  @IsOptional()
  @IsString()
  @Length(10, 300)
  @Matches(/\{code\}/, { message: 'otpTemplate must contain {code}' })
  otpTemplate?: string;
}

class TestSmsDto {
  @ApiProperty({ example: '09xxxxxxxxx' }) @IsString() @Length(6, 20) phone: string;
}

@ApiTags('admin')
@Controller('admin')
@Auth('PLATFORM_ADMIN')
export class AdminSettingsController {
  constructor(
    private readonly settings: SettingsService,
    private readonly sms: SmsService,
  ) {}

  @Get('settings/sms')
  async getSms() {
    const view = await this.settings.smsView();
    let balance: { balance: number; currency: string } | null = null;
    let balanceError: string | null = null;
    try {
      balance = await this.sms.balance();
    } catch (e) {
      balanceError = (e as Error).message;
    }
    return { ...view, balance, balanceError };
  }

  @Put('settings/sms')
  async putSms(@Body() dto: SmsSettingsDto, @CurrentUser() u: AuthUser) {
    try {
      return await this.settings.updateSms(dto, u.sub);
    } catch (e) {
      throw new ServiceUnavailableException((e as Error).message);
    }
  }

  @Post('settings/sms/test')
  @HttpCode(200)
  async testSms(@Body() dto: TestSmsDto) {
    const phone = normalizeMyanmarPhone(dto.phone);
    if (!phone) throw new BadRequestException('Invalid Myanmar mobile number');
    try {
      const r = await this.sms.send(phone, 'Event 360 test message: SMS is working.', 'test');
      return { ok: true, ...r };
    } catch (e) {
      if (e instanceof SmsError) throw new BadRequestException(e.message);
      throw e;
    }
  }

  @Get('sms-log')
  log(@Query('limit') limit?: string) {
    return this.sms.recentLog(Number(limit) || 50);
  }
}

@Global()
@Module({
  controllers: [AdminSettingsController, InboxController, AdminPushController, AnnouncementsController],
  providers: [SettingsService, SmsService, PaymentSettingsService, PushSettingsService, NotifyService],
  exports: [SettingsService, SmsService, PaymentSettingsService, PushSettingsService, NotifyService],
})
export class NotificationsModule {}
