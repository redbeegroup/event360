import { ArgumentsHost, BadRequestException, Body, Catch, Controller, Get, HttpCode, HttpException, Injectable, Module, Param, ParseUUIDPipe, Post, Put, Query, ServiceUnavailableException } from '@nestjs/common';
import { APP_FILTER, BaseExceptionFilter } from '@nestjs/core';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { ArrayMaxSize, IsArray, IsBoolean, IsEmail, IsIn, IsInt, IsObject, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import type { Request } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { PrismaService } from '../prisma/prisma.service';
import { EmailService } from './email.service';
import { ErrorsService } from './errors.service';
import { MonitorService } from './monitor.service';

export { EmailService } from './email.service';
export { ErrorsService } from './errors.service';
export { MonitorService } from './monitor.service';

const RELEASE = process.env.APP_VERSION ?? null;

/** Records unexpected server errors (5xx) in Admin → Operations, then responds as Nest normally does. */
@Catch()
@Injectable()
export class ErrorCaptureFilter extends BaseExceptionFilter {
  constructor(private readonly errors: ErrorsService) {
    super();
  }

  catch(exception: unknown, host: ArgumentsHost) {
    const status = exception instanceof HttpException ? exception.getStatus() : 500;
    if (status >= 500 && host.getType() === 'http') {
      const req = host.switchToHttp().getRequest<Request>();
      const e = exception instanceof Error ? exception : new Error(String(exception));
      void this.errors.capture({
        source: 'api',
        message: e.message || e.name,
        stack: e.stack,
        path: `${req.method} ${(req.route?.path as string | undefined) ?? req.path}`,
        release: RELEASE,
        context: { status, role: process.env.APP_ROLE ?? 'api' },
      });
    }
    super.catch(exception, host);
  }
}

const SOURCES = ['portal', 'site', 'user_app', 'crew_app', 'organizer_app'] as const;

class ClientErrorDto {
  @ApiProperty({ enum: SOURCES }) @IsIn(SOURCES as unknown as string[]) source: string;
  @ApiProperty() @IsString() @MaxLength(1000) message: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(8000) stack?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) path?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(64) release?: string;
  @ApiPropertyOptional() @IsOptional() @IsObject() context?: Record<string, unknown>;
}

class EmailSettingsDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) host?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(65535) port?: number;
  @ApiPropertyOptional({ description: 'Implicit TLS (port 465)' }) @IsOptional() @IsBoolean() secure?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) user?: string;
  @ApiPropertyOptional({ description: 'Leave empty to keep the current one' }) @IsOptional() @IsString() @MaxLength(500) pass?: string;
  @ApiPropertyOptional({ example: 'Event 360 <alerts@example.com>' }) @IsOptional() @IsString() @MaxLength(200) from?: string;
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(10) @IsEmail({}, { each: true }) alertTo?: string[];
  @ApiPropertyOptional() @IsOptional() @IsBoolean() enabled?: boolean;
}

/** Error reports from the apps and the web servers (no sign-in; small and rate-limited). */
@ApiTags('telemetry')
@Controller('telemetry')
export class TelemetryController {
  constructor(private readonly errors: ErrorsService) {}

  @Post('errors')
  @HttpCode(202)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  report(@Body() dto: ClientErrorDto) {
    const ctx = dto.context && JSON.stringify(dto.context).length <= 2000 ? dto.context : undefined;
    void this.errors.capture({ source: dto.source, message: dto.message, stack: dto.stack, path: dto.path, release: dto.release, context: ctx });
    return { ok: true };
  }
}

@ApiTags('admin')
@Controller('admin')
@Auth('PLATFORM_ADMIN')
export class AdminOpsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly monitor: MonitorService,
    private readonly email: EmailService,
  ) {}

  @Get('ops/status')
  async status() {
    const [checks, incidents, openErrors, backups] = await Promise.all([
      this.prisma.monitorCheck.findMany({ orderBy: { name: 'asc' } }),
      this.prisma.monitorIncident.findMany({ orderBy: { startedAt: 'desc' }, take: 20 }),
      this.prisma.errorGroup.count({ where: { resolvedAt: null } }),
      this.monitor.backups(),
    ]);
    return { checks, incidents, openErrors, backups, release: RELEASE };
  }

  @Get('ops/errors')
  errors(@Query('status') status?: string, @Query('source') source?: string) {
    return this.prisma.errorGroup.findMany({
      where: { ...(status === 'resolved' ? { resolvedAt: { not: null } } : { resolvedAt: null }), ...(source ? { source } : {}) },
      orderBy: { lastSeen: 'desc' },
      take: 100,
    });
  }

  @Post('ops/errors/:id/resolve')
  @HttpCode(200)
  resolve(@Param('id', ParseUUIDPipe) id: string) {
    return this.prisma.errorGroup.update({ where: { id }, data: { resolvedAt: new Date() } });
  }

  @Get('settings/email')
  emailView() {
    return this.email.view();
  }

  @Put('settings/email')
  async emailUpdate(@Body() dto: EmailSettingsDto, @CurrentUser() u: AuthUser) {
    try {
      return await this.email.update(dto, u.sub);
    } catch (e) {
      throw new ServiceUnavailableException((e as Error).message);
    }
  }

  @Post('settings/email/test')
  @HttpCode(200)
  async emailTest() {
    try {
      const sent = await this.email.sendAlert('Test alert', 'This is a test from Admin → Settings → Email. Operations alerts will arrive like this.', { force: true });
      if (!sent) throw new BadRequestException('Fill in the server, sender and alert recipients first');
      return { ok: true };
    } catch (e) {
      if (e instanceof HttpException) throw e;
      throw new BadRequestException(`Sending failed: ${(e as Error).message}`);
    }
  }
}

@Module({
  controllers: [TelemetryController, AdminOpsController],
  providers: [EmailService, ErrorsService, MonitorService, { provide: APP_FILTER, useClass: ErrorCaptureFilter }],
  exports: [EmailService, ErrorsService, MonitorService],
})
export class OpsModule {}
