import { Body, Controller, Delete, Get, HttpCode, Module, NotFoundException, Param, ParseUUIDPipe, Patch, Post, Query, Req, Res } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested } from 'class-validator';
import type { Request, Response } from 'express';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ORG_EDITORS, ORG_VIEWERS, OrgAccessService } from '../../common/org-access.service';
import { K8sJobsService } from './k8s-jobs.service';
import { StreamingService } from './streaming.service';

class RecordingDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() recordingEnabled?: boolean;
}

class UpdateRecordingDto {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() published?: boolean;
  @ApiPropertyOptional({ nullable: true }) @IsOptional() @IsISO8601() availableUntil?: string | null;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 200) title?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(0, 200) titleMy?: string;
}

class CreateUploadDto {
  @ApiProperty() @IsString() @Length(1, 200) title: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(0, 200) titleMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() sessionId?: string;
  @ApiProperty() @IsString() @Length(1, 200) fileName: string;
  @ApiProperty() @IsInt() @Min(1) @Max(4 * 1024 * 1024 * 1024) size: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(0, 100) contentType?: string;
}

class PartDto {
  @ApiProperty() @IsInt() @Min(1) @Max(10000) partNumber: number;
  @ApiProperty() @IsString() @Length(1, 200) etag: string;
}

class CompleteUploadDto {
  @ApiProperty({ type: [PartDto] }) @IsArray() @ArrayMaxSize(10000) @ValidateNested({ each: true }) @Type(() => PartDto) parts: PartDto[];
}

/** Organizer: live channels per session, recordings and uploads. */
@ApiTags('organizer')
@Controller('organizations/:orgId/events/:eventId/streaming')
@Auth()
export class OrgStreamingController {
  constructor(
    private readonly streaming: StreamingService,
    private readonly access: OrgAccessService,
  ) {}

  @Get()
  async overview(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_VIEWERS);
    return this.streaming.overview(orgId, eventId);
  }

  @Post('sessions/:sessionId/channel')
  async create(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('sessionId', ParseUUIDPipe) sessionId: string,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.createChannel(orgId, eventId, sessionId);
  }

  @Post('channels/:channelId/rotate-key')
  @HttpCode(200)
  async rotate(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @Param('channelId', ParseUUIDPipe) channelId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.rotateKey(orgId, eventId, channelId);
  }

  @Patch('channels/:channelId')
  async patch(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('channelId', ParseUUIDPipe) channelId: string,
    @Body() dto: RecordingDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.setRecording(orgId, eventId, channelId, dto.recordingEnabled ?? true);
  }

  @Post('channels/:channelId/stop')
  @HttpCode(200)
  async stop(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @Param('channelId', ParseUUIDPipe) channelId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.stopChannel(orgId, eventId, channelId);
  }

  @Delete('channels/:channelId')
  async remove(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @Param('channelId', ParseUUIDPipe) channelId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.deleteChannel(orgId, eventId, channelId);
  }

  @Patch('recordings/:assetId')
  async updateRecording(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('assetId', ParseUUIDPipe) assetId: string,
    @Body() dto: UpdateRecordingDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.updateRecording(orgId, eventId, assetId, dto);
  }

  @Delete('recordings/:assetId')
  async deleteRecording(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @Param('assetId', ParseUUIDPipe) assetId: string, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.deleteRecording(orgId, eventId, assetId);
  }

  @Post('uploads')
  async createUpload(@Param('orgId', ParseUUIDPipe) orgId: string, @Param('eventId', ParseUUIDPipe) eventId: string, @Body() dto: CreateUploadDto, @CurrentUser() u: AuthUser) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.createUpload(orgId, eventId, dto);
  }

  @Post('uploads/:assetId/complete')
  @HttpCode(200)
  async completeUpload(
    @Param('orgId', ParseUUIDPipe) orgId: string,
    @Param('eventId', ParseUUIDPipe) eventId: string,
    @Param('assetId', ParseUUIDPipe) assetId: string,
    @Body() dto: CompleteUploadDto,
    @CurrentUser() u: AuthUser,
  ) {
    await this.access.assert(u, orgId, ORG_EDITORS);
    return this.streaming.completeUpload(orgId, eventId, assetId, dto.parts);
  }
}

/** SRS HTTP callbacks (cluster-internal; protected by STREAM_HOOK_SECRET). SRS treats {code:0} as "allow". */
@ApiTags('internal')
@Controller('streaming/hooks')
export class StreamingHooksController {
  constructor(private readonly streaming: StreamingService) {}

  @Post(':action')
  @HttpCode(200)
  async hook(@Param('action') action: string, @Query('secret') secret: string, @Body() body: Record<string, string>, @Res() res: Response) {
    this.streaming.checkHookSecret(secret);
    if (action === 'on_publish') {
      const reason = await this.streaming.onPublish(body);
      if (reason) return res.status(403).json({ code: 403, reason });
    } else if (action === 'on_unpublish') {
      await this.streaming.onUnpublish(body);
    }
    return res.json({ code: 0 });
  }
}

/** Viewers: what can be watched, playback tokens, heartbeat. */
@ApiTags('watch')
@Controller()
export class WatchController {
  constructor(private readonly streaming: StreamingService) {}

  @Get('events/:idOrSlug/streams')
  streams(@Param('idOrSlug') idOrSlug: string) {
    return this.streaming.publicStreams(idOrSlug);
  }

  @Post('watch/:kind/:id/token')
  @Auth()
  token(@Param('kind') kind: string, @Param('id', ParseUUIDPipe) id: string, @CurrentUser() u: AuthUser) {
    if (kind !== 'live' && kind !== 'vod') throw new NotFoundException();
    return this.streaming.issueToken(u, kind, id);
  }

  @Post('watch/sessions/:sessionId/heartbeat')
  @HttpCode(200)
  @Auth()
  heartbeat(@Param('sessionId', ParseUUIDPipe) sessionId: string, @CurrentUser() u: AuthUser) {
    return this.streaming.heartbeat(u, sessionId);
  }

  /** HLS files. The token is in the path so relative URLs inside playlists keep it. */
  @Get('play/t/:token/:kind/:id/*')
  async play(@Param('token') token: string, @Param('kind') kind: string, @Param('id', ParseUUIDPipe) id: string, @Req() req: Request, @Res() res: Response) {
    const path = String((req.params as Record<string, string>)['0'] ?? '');
    const f = await this.streaming.file(token, kind, id, path);
    res.setHeader('content-type', f.contentType);
    res.setHeader('cache-control', f.cacheControl);
    if (f.length !== undefined) res.setHeader('content-length', String(f.length));
    f.body.on('error', () => res.destroy());
    f.body.pipe(res);
  }
}

@Module({
  controllers: [OrgStreamingController, StreamingHooksController, WatchController],
  providers: [StreamingService, K8sJobsService],
  exports: [StreamingService],
})
export class StreamingModule {}
