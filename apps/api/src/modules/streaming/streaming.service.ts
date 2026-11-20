import {
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  S3Client,
  UploadPartCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  GoneException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { LiveChannel, VodAsset } from '@prisma/client';
import { createHash, createHmac, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'crypto';
import { Readable } from 'stream';
import type { AuthUser } from '../../common/auth';
import { NotifyService } from '../notifications/notify.service';
import { PrismaService } from '../prisma/prisma.service';
import { liveTranscoderJob, PipelineConfig, playlistDuration, uploadTranscoderJob } from './jobs';
import { K8sJobsService } from './k8s-jobs.service';

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
const ALNUM = 'abcdefghijkmnpqrstuvwxyz23456789';
const randomId = (n: number) => Array.from({ length: n }, () => ALNUM[randomInt(ALNUM.length)]).join('');

/** Files a player may request: master/variant playlists and segments only. */
export const PLAY_PATH_RE = /^(index\.m3u8|v[0-4]\/(index\.m3u8|seg_\d{5}\.ts))$/;
const TOKEN_TTL_S = 6 * 3600;
const ACTIVE_VIEWER_MS = 70_000;
const PART_SIZE = 16 * 1024 * 1024;
const MAX_UPLOAD = 4 * 1024 * 1024 * 1024;

export interface PlayClaims {
  k: 'live' | 'vod';
  id: string; // channel id or asset id
  u: string; // user id
  s: string; // playback session id
  e: number; // expiry (unix seconds)
}

export interface FileResponse {
  body: Readable;
  contentType: string;
  cacheControl: string;
  length?: number;
}

@Injectable()
export class StreamingService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(StreamingService.name);
  private readonly s3: S3Client;
  private readonly bucket: string;
  private readonly prefix: string;
  private readonly tokenKey: Buffer;
  private readonly sessionCache = new Map<string, { ok: boolean; at: number }>();
  private readonly channelCache = new Map<string, { prefix: string | null; at: number }>();
  private readonly playlistCache = new Map<string, { body: Buffer; at: number }>();
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly k8s: K8sJobsService,
    private readonly notify: NotifyService,
  ) {
    this.s3 = new S3Client({
      endpoint: config.get('S3_ENDPOINT'),
      region: config.get('S3_REGION') ?? 'us-east-1',
      forcePathStyle: true,
      credentials: { accessKeyId: config.get('S3_ACCESS_KEY_ID') ?? 'x', secretAccessKey: config.get('S3_SECRET_ACCESS_KEY') ?? 'x' },
    });
    this.bucket = config.get('S3_BUCKET') ?? 'event360';
    this.prefix = (config.get<string>('S3_PREFIX') ?? 'dev').replace(/\/+$/, '');
    this.tokenKey = createHash('sha256').update(`playback:${config.get('JWT_ACCESS_SECRET') ?? 'dev'}`).digest();
  }

  // ───────────── config ─────────────

  private get pipeline(): PipelineConfig {
    return {
      ffmpegImage: this.config.get('FFMPEG_IMAGE') ?? 'jrottenberg/ffmpeg:7.1-ubuntu',
      apiImage: this.config.get('API_IMAGE') ?? 'ghcr.io/redbeegroup/event360-api:latest',
      secretName: this.config.get('APP_SECRET_NAME') ?? 'event360-secrets',
      avoidNodes: (this.config.get<string>('MEDIA_AVOID_NODES') ?? '').split(',').filter(Boolean),
    };
  }
  private get maxLive() {
    return Number(this.config.get('MAX_LIVE_CHANNELS') ?? 1);
  }
  private get publicApi() {
    return this.config.get<string>('PUBLIC_API_URL') ?? 'http://localhost:3000';
  }
  ingestInfo(ingestKey: string, streamKey?: string) {
    const rtmp = this.config.get<string>('STREAM_RTMP_URL') ?? 'rtmp://localhost:1935/live';
    const srt = this.config.get<string>('STREAM_SRT_URL') ?? 'srt://localhost:8890';
    return {
      obsServer: rtmp,
      obsStreamKey: streamKey ? `${ingestKey}?key=${streamKey}` : `${ingestKey}?key=••••••`,
      srtUrl: streamKey ? `${srt}?streamid=#!::r=live/${ingestKey}?key=${streamKey},m=publish` : null,
    };
  }

  onModuleInit() {
    // Only the HTTP API pods follow job progress (idempotent if several replicas do).
    if ((process.env.APP_ROLE ?? 'api') === 'api' && this.k8s.enabled) {
      this.timer = setInterval(() => this.syncJobs().catch((e) => this.logger.warn(`job sync: ${e.message}`)), 20_000);
    }
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  // ───────────── organizer: channels ─────────────

  private async orgEvent(organizationId: string, eventId: string) {
    const e = await this.prisma.event.findFirst({ where: { id: eventId, organizationId }, include: { sessions: { orderBy: { startsAt: 'asc' } } } });
    if (!e) throw new NotFoundException('Event not found');
    return e;
  }

  private async viewers(targetId: string) {
    return this.prisma.playbackSession.count({ where: { targetId, revokedAt: null, lastSeenAt: { gt: new Date(Date.now() - ACTIVE_VIEWER_MS) } } });
  }

  private recordingView(a: VodAsset) {
    return {
      id: a.id,
      title: a.title,
      titleMy: a.titleMy,
      sessionId: a.sessionId,
      source: a.source,
      status: a.status,
      error: a.error,
      durationSec: a.durationSec,
      published: a.published,
      availableUntil: a.availableUntil,
      createdAt: a.createdAt,
    };
  }

  /** Everything the organizer's Live section needs for one event. */
  async overview(organizationId: string, eventId: string) {
    const e = await this.orgEvent(organizationId, eventId);
    const [channels, assets] = await Promise.all([
      this.prisma.liveChannel.findMany({ where: { eventId } }),
      this.prisma.vodAsset.findMany({ where: { eventId }, orderBy: { createdAt: 'desc' } }),
    ]);
    const bySession = new Map(channels.map((c) => [c.sessionId, c]));
    return {
      maxLiveChannels: this.maxLive,
      pipelineReady: this.k8s.enabled,
      sessions: await Promise.all(
        e.sessions.map(async (s) => {
          const c = bySession.get(s.id);
          return {
            id: s.id,
            title: s.title,
            titleMy: s.titleMy,
            startsAt: s.startsAt,
            endsAt: s.endsAt,
            channel: c
              ? {
                  id: c.id,
                  status: c.status,
                  recordingEnabled: c.recordingEnabled,
                  startedAt: c.startedAt,
                  endedAt: c.endedAt,
                  viewers: c.status === 'LIVE' ? await this.viewers(c.id) : 0,
                  peakViewers: c.peakViewers,
                  ...this.ingestInfo(c.ingestKey),
                }
              : null,
          };
        }),
      ),
      recordings: assets.map((a) => this.recordingView(a)),
    };
  }

  async createChannel(organizationId: string, eventId: string, sessionId: string) {
    const e = await this.orgEvent(organizationId, eventId);
    if (!e.sessions.some((s) => s.id === sessionId)) throw new NotFoundException('Session not found');
    if (await this.prisma.liveChannel.findUnique({ where: { sessionId } })) throw new ConflictException('This session already has a live channel');
    const streamKey = randomBytes(18).toString('base64url');
    const c = await this.prisma.liveChannel.create({
      data: { sessionId, eventId, ingestKey: randomId(10), streamKeyHash: sha256(streamKey) },
    });
    return { id: c.id, status: c.status, ...this.ingestInfo(c.ingestKey, streamKey) };
  }

  private async orgChannel(organizationId: string, eventId: string, channelId: string) {
    await this.orgEvent(organizationId, eventId);
    const c = await this.prisma.liveChannel.findFirst({ where: { id: channelId, eventId } });
    if (!c) throw new NotFoundException('Live channel not found');
    return c;
  }

  async rotateKey(organizationId: string, eventId: string, channelId: string) {
    const c = await this.orgChannel(organizationId, eventId, channelId);
    if (c.status === 'LIVE') throw new ConflictException('Stop the stream before changing the key');
    const streamKey = randomBytes(18).toString('base64url');
    await this.prisma.liveChannel.update({ where: { id: c.id }, data: { streamKeyHash: sha256(streamKey) } });
    return { id: c.id, ...this.ingestInfo(c.ingestKey, streamKey) };
  }

  async setRecording(organizationId: string, eventId: string, channelId: string, enabled: boolean) {
    const c = await this.orgChannel(organizationId, eventId, channelId);
    await this.prisma.liveChannel.update({ where: { id: c.id }, data: { recordingEnabled: enabled } });
    return { id: c.id, recordingEnabled: enabled };
  }

  /** Disconnects the encoder through the SRS API; on_unpublish then ends the stream cleanly. */
  async stopChannel(organizationId: string, eventId: string, channelId: string) {
    const c = await this.orgChannel(organizationId, eventId, channelId);
    if (c.status !== 'LIVE') return { id: c.id, status: c.status };
    if (c.srsClientId) {
      const api = this.config.get<string>('SRS_API_URL') ?? 'http://srs:1985';
      await fetch(`${api}/api/v1/clients/${encodeURIComponent(c.srsClientId)}`, { method: 'DELETE' }).catch((e) =>
        this.logger.warn(`SRS kick failed: ${e.message}`),
      );
    }
    return { id: c.id, status: 'STOPPING' };
  }

  async deleteChannel(organizationId: string, eventId: string, channelId: string) {
    const c = await this.orgChannel(organizationId, eventId, channelId);
    if (c.status === 'LIVE') throw new ConflictException('Stop the stream first');
    await this.prisma.liveChannel.delete({ where: { id: c.id } });
    return { deleted: true };
  }

  // ───────────── SRS hooks ─────────────

  checkHookSecret(secret: string | undefined) {
    const expected = this.config.get<string>('STREAM_HOOK_SECRET');
    if (!expected || !secret || secret.length !== expected.length || !timingSafeEqual(Buffer.from(secret), Buffer.from(expected))) {
      throw new ForbiddenException('Bad hook secret');
    }
  }

  /** Returns null when allowed, otherwise the reason. Starts the transcoder. */
  async onPublish(b: { app?: string; stream?: string; param?: string; client_id?: string }): Promise<string | null> {
    if (b.app !== 'live' || !b.stream) return 'unknown app';
    const c = await this.prisma.liveChannel.findUnique({ where: { ingestKey: b.stream }, include: { session: true } });
    if (!c) return 'unknown channel';
    const key = new URLSearchParams((b.param ?? '').replace(/^\?/, '')).get('key') ?? '';
    if (!key || sha256(key) !== c.streamKeyHash) return 'bad stream key';
    const now = Date.now();
    if (now < c.session.startsAt.getTime() - 3600e3 || now > c.session.endsAt.getTime() + 6 * 3600e3) return 'outside the session time window';
    if (c.status === 'LIVE') return 'already live';
    const live = await this.prisma.liveChannel.count({ where: { status: 'LIVE' } });
    if (live >= this.maxLive) return `limit of ${this.maxLive} live stream(s) reached`;

    const jobName = `live-${c.ingestKey}-${now.toString(36)}`;
    // With recording on, the live HLS is written straight into the recording's prefix.
    let asset: VodAsset | null = null;
    if (c.recordingEnabled) {
      const id = randomUUID();
      const e = await this.prisma.event.findUnique({ where: { id: c.eventId } });
      asset = await this.prisma.vodAsset.create({
        data: {
          id,
          eventId: c.eventId,
          sessionId: c.sessionId,
          liveChannelId: c.id,
          title: c.session.title,
          titleMy: c.session.titleMy,
          source: 'LIVE',
          status: 'PROCESSING',
          s3Prefix: `${this.prefix}/vod/${id}`,
          jobName,
          published: true,
          availableUntil: new Date((e?.endsAt ?? new Date()).getTime() + 30 * 864e5),
        },
      });
    }
    try {
      await this.k8s.createJob(
        liveTranscoderJob(this.pipeline, {
          name: jobName,
          ingestKey: c.ingestKey,
          srsRtmp: this.config.get('SRS_INTERNAL_RTMP') ?? 'rtmp://srs:1935',
          record: c.recordingEnabled,
          prefix: asset?.s3Prefix ?? `${this.prefix}/live/${jobName}`,
        }),
      );
    } catch (e) {
      this.logger.error(`transcoder start failed: ${(e as Error).message}`);
      if (asset) await this.prisma.vodAsset.delete({ where: { id: asset.id } });
      return 'transcoder could not start';
    }
    await this.prisma.liveChannel.update({
      where: { id: c.id },
      data: {
        status: 'LIVE',
        jobName,
        livePrefix: asset?.s3Prefix ?? `${this.prefix}/live/${jobName}`,
        srsClientId: b.client_id ?? null,
        startedAt: new Date(),
        endedAt: null,
        peakViewers: 0,
      },
    });
    this.channelCache.delete(c.id);
    // Tell ticket holders once per session window (encoder reconnects don't re-notify)
    const claim = await this.prisma.liveChannel.updateMany({
      where: { id: c.id, OR: [{ liveNotifiedAt: null }, { liveNotifiedAt: { lt: new Date(Date.now() - 6 * 3600e3) } }] },
      data: { liveNotifiedAt: new Date() },
    });
    if (claim.count === 1) {
      const ev = await this.prisma.event.findUnique({ where: { id: c.eventId }, select: { title: true, titleMy: true } });
      if (ev) void this.notify.liveNow({ eventId: c.eventId, eventTitle: ev.title, eventTitleMy: ev.titleMy, sessionTitle: c.session.title, channelId: c.id });
    }
    return null;
  }

  async onUnpublish(b: { app?: string; stream?: string }) {
    if (b.app !== 'live' || !b.stream) return;
    await this.prisma.liveChannel.updateMany({ where: { ingestKey: b.stream, status: 'LIVE' }, data: { status: 'IDLE', endedAt: new Date(), srsClientId: null } });
  }

  /** Follows transcoder/archiver Jobs: recordings become READY (with duration) or FAILED. */
  async syncJobs() {
    const pending = await this.prisma.vodAsset.findMany({ where: { status: 'PROCESSING', jobName: { not: null } } });
    for (const a of pending) {
      const j = await this.k8s.getJob(a.jobName!);
      if (j && j.succeeded > 0) {
        let durationSec: number | null = null;
        try {
          const o = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: `${a.s3Prefix}/v4/index.m3u8` }));
          durationSec = playlistDuration(await o.Body!.transformToString());
        } catch {
          /* duration unknown */
        }
        await this.prisma.vodAsset.update({
          where: { id: a.id },
          data: durationSec ? { status: 'READY', durationSec } : { status: 'FAILED', error: 'Recording is empty (stream too short?)' },
        });
      } else if (!j || j.failed > 0) {
        await this.prisma.vodAsset.update({ where: { id: a.id }, data: { status: 'FAILED', error: j ? 'Transcoding failed' : 'Job disappeared' } });
      }
    }
    // Safety net: a LIVE channel whose transcoder has finished is no longer live.
    for (const c of await this.prisma.liveChannel.findMany({ where: { status: 'LIVE', jobName: { not: null } } })) {
      const j = await this.k8s.getJob(c.jobName!);
      if (!j || j.failed > 0) await this.prisma.liveChannel.update({ where: { id: c.id }, data: { status: 'IDLE', endedAt: new Date() } });
    }
  }

  // ───────────── organizer: recordings ─────────────

  private async orgAsset(organizationId: string, eventId: string, assetId: string) {
    await this.orgEvent(organizationId, eventId);
    const a = await this.prisma.vodAsset.findFirst({ where: { id: assetId, eventId } });
    if (!a) throw new NotFoundException('Recording not found');
    return a;
  }

  async updateRecording(
    organizationId: string,
    eventId: string,
    assetId: string,
    dto: { published?: boolean; availableUntil?: string | null; title?: string; titleMy?: string },
  ) {
    const a = await this.orgAsset(organizationId, eventId, assetId);
    const u = await this.prisma.vodAsset.update({
      where: { id: a.id },
      data: {
        ...(dto.published !== undefined ? { published: dto.published } : {}),
        ...(dto.availableUntil !== undefined ? { availableUntil: dto.availableUntil ? new Date(dto.availableUntil) : null } : {}),
        ...(dto.title ? { title: dto.title } : {}),
        ...(dto.titleMy !== undefined ? { titleMy: dto.titleMy || null } : {}),
      },
    });
    return this.recordingView(u);
  }

  async deleteRecording(organizationId: string, eventId: string, assetId: string) {
    const a = await this.orgAsset(organizationId, eventId, assetId);
    if (a.status === 'PROCESSING' && a.jobName) await this.k8s.deleteJob(a.jobName).catch(() => undefined);
    let token: string | undefined;
    do {
      const l = await this.s3.send(new ListObjectsV2Command({ Bucket: this.bucket, Prefix: `${a.s3Prefix}/`, ContinuationToken: token }));
      const keys = (l.Contents ?? []).map((o) => ({ Key: o.Key! }));
      if (keys.length) await this.s3.send(new DeleteObjectsCommand({ Bucket: this.bucket, Delete: { Objects: keys } }));
      token = l.IsTruncated ? l.NextContinuationToken : undefined;
    } while (token);
    await this.prisma.vodAsset.delete({ where: { id: a.id } });
    return { deleted: true };
  }

  /** Starts a direct-to-storage multipart upload; the browser PUTs each part to the presigned URLs. */
  async createUpload(
    organizationId: string,
    eventId: string,
    dto: { title: string; titleMy?: string; sessionId?: string; fileName: string; size: number; contentType?: string },
  ) {
    const e = await this.orgEvent(organizationId, eventId);
    if (dto.size <= 0 || dto.size > MAX_UPLOAD) throw new BadRequestException('Video must be at most 4 GB');
    if (dto.sessionId && !e.sessions.some((s) => s.id === dto.sessionId)) throw new NotFoundException('Session not found');
    const ext = (dto.fileName.split('.').pop() ?? 'mp4').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 5) || 'mp4';
    const id = randomUUID();
    const sourceKey = `${this.prefix}/uploads/${id}/source.${ext}`;
    const mp = await this.s3.send(
      new CreateMultipartUploadCommand({ Bucket: this.bucket, Key: sourceKey, ContentType: dto.contentType || 'application/octet-stream' }),
    );
    await this.prisma.vodAsset.create({
      data: {
        id,
        eventId,
        sessionId: dto.sessionId ?? null,
        title: dto.title,
        titleMy: dto.titleMy || null,
        source: 'UPLOAD',
        status: 'UPLOADING',
        s3Prefix: `${this.prefix}/vod/${id}`,
        sizeBytes: BigInt(dto.size),
        published: false,
        availableUntil: new Date(e.endsAt.getTime() + 30 * 864e5),
        renditions: { sourceKey, uploadId: mp.UploadId },
      },
    });
    const parts = Math.ceil(dto.size / PART_SIZE);
    const urls = await Promise.all(
      Array.from({ length: parts }, (_, i) =>
        getSignedUrl(this.s3, new UploadPartCommand({ Bucket: this.bucket, Key: sourceKey, UploadId: mp.UploadId, PartNumber: i + 1 }), { expiresIn: 6 * 3600 }),
      ),
    );
    return { assetId: id, partSize: PART_SIZE, parts: urls.map((url, i) => ({ partNumber: i + 1, url })) };
  }

  async completeUpload(organizationId: string, eventId: string, assetId: string, parts: { partNumber: number; etag: string }[]) {
    const a = await this.orgAsset(organizationId, eventId, assetId);
    if (a.status !== 'UPLOADING') throw new ConflictException('Upload already completed');
    const meta = a.renditions as { sourceKey: string; uploadId: string };
    await this.s3.send(
      new CompleteMultipartUploadCommand({
        Bucket: this.bucket,
        Key: meta.sourceKey,
        UploadId: meta.uploadId,
        MultipartUpload: { Parts: [...parts].sort((x, y) => x.partNumber - y.partNumber).map((p) => ({ PartNumber: p.partNumber, ETag: p.etag })) },
      }),
    );
    const sourceUrl = await getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: meta.sourceKey }), { expiresIn: 6 * 3600 });
    const jobName = `vod-${a.id.slice(0, 8)}-${Date.now().toString(36)}`;
    await this.k8s.createJob(uploadTranscoderJob(this.pipeline, { name: jobName, assetId: a.id, sourceUrl, sourceKey: meta.sourceKey, vodPrefix: a.s3Prefix }));
    const u = await this.prisma.vodAsset.update({ where: { id: a.id }, data: { status: 'PROCESSING', jobName, renditions: undefined } });
    return this.recordingView(u);
  }

  // ───────────── viewers ─────────────

  private async eventByIdOrSlug(idOrSlug: string) {
    const isUuid = /^[0-9a-f-]{36}$/i.test(idOrSlug);
    const e = await this.prisma.event.findFirst({ where: isUuid ? { id: idOrSlug } : { slug: idOrSlug } });
    if (!e || !['PUBLISHED', 'COMPLETED'].includes(e.status)) throw new NotFoundException('Event not found');
    return e;
  }

  private watchable(a: VodAsset) {
    const now = new Date();
    return a.status === 'READY' && a.published && (!a.availableFrom || a.availableFrom <= now) && (!a.availableUntil || a.availableUntil > now);
  }

  /** Public: what is live now and which recordings exist (titles only — watching needs a ticket). */
  async publicStreams(idOrSlug: string) {
    const e = await this.eventByIdOrSlug(idOrSlug);
    const [channels, assets] = await Promise.all([
      this.prisma.liveChannel.findMany({ where: { eventId: e.id }, include: { session: true } }),
      this.prisma.vodAsset.findMany({ where: { eventId: e.id, status: 'READY', published: true }, orderBy: { createdAt: 'asc' } }),
    ]);
    return {
      eventId: e.id,
      live: channels
        .sort((x, y) => x.session.startsAt.getTime() - y.session.startsAt.getTime())
        .map((c) => ({ channelId: c.id, sessionId: c.sessionId, title: c.session.title, titleMy: c.session.titleMy, startsAt: c.session.startsAt, endsAt: c.session.endsAt, isLive: c.status === 'LIVE' })),
      recordings: assets.filter((a) => this.watchable(a)).map((a) => ({ id: a.id, sessionId: a.sessionId, title: a.title, titleMy: a.titleMy, durationSec: a.durationSec, availableUntil: a.availableUntil })),
    };
  }

  /** Ticket holders (VALID or CHECKED_IN), organizer staff and platform admins may watch. */
  private async assertEntitled(u: AuthUser, eventId: string, organizationId: string) {
    if (u.typ === 'crew') throw new ForbiddenException();
    if (u.roles?.includes('PLATFORM_ADMIN')) return;
    const [ticket, member] = await Promise.all([
      this.prisma.ticket.findFirst({ where: { holderUserId: u.sub, status: { in: ['VALID', 'CHECKED_IN'] }, ticketType: { eventId } } }),
      this.prisma.organizationMember.findUnique({ where: { organizationId_userId: { organizationId, userId: u.sub } } }),
    ]);
    if (!ticket && !member) throw new ForbiddenException('You need a ticket for this event to watch');
  }

  private sign(c: PlayClaims) {
    const body = Buffer.from(JSON.stringify(c)).toString('base64url');
    const mac = createHmac('sha256', this.tokenKey).update(body).digest('base64url').slice(0, 32);
    return `${body}.${mac}`;
  }

  verifyToken(token: string): PlayClaims {
    const [body, mac] = token.split('.');
    if (!body || !mac) throw new UnauthorizedException('Bad playback token');
    const expected = createHmac('sha256', this.tokenKey).update(body).digest('base64url').slice(0, 32);
    if (mac.length !== expected.length || !timingSafeEqual(Buffer.from(mac), Buffer.from(expected))) throw new UnauthorizedException('Bad playback token');
    const c = JSON.parse(Buffer.from(body, 'base64url').toString()) as PlayClaims;
    if (c.e < Date.now() / 1000) throw new UnauthorizedException('Playback token expired');
    return c;
  }

  /** Starts playback on this device (ending any other device's playback of the same stream/recording). */
  async issueToken(u: AuthUser, kind: 'live' | 'vod', id: string) {
    let eventId: string, organizationId: string;
    if (kind === 'live') {
      const c = await this.prisma.liveChannel.findUnique({ where: { id }, include: { event: true } });
      if (!c) throw new NotFoundException('Stream not found');
      if (c.status !== 'LIVE') throw new GoneException('This stream is not live right now');
      eventId = c.eventId;
      organizationId = c.event.organizationId;
    } else {
      const a = await this.prisma.vodAsset.findUnique({ where: { id }, include: { event: true } });
      if (!a || !this.watchable(a)) throw new NotFoundException('Recording not available');
      eventId = a.eventId;
      organizationId = a.event.organizationId;
    }
    await this.assertEntitled(u, eventId, organizationId);
    const targetType = kind === 'live' ? 'LIVE' : 'VOD';
    const [, session] = await this.prisma.$transaction([
      this.prisma.playbackSession.updateMany({ where: { userId: u.sub, targetId: id, revokedAt: null }, data: { revokedAt: new Date() } }),
      this.prisma.playbackSession.create({ data: { userId: u.sub, targetType, targetId: id } }),
    ]);
    this.sessionCache.clear();
    if (kind === 'live') {
      const n = await this.viewers(id);
      await this.prisma.liveChannel.updateMany({ where: { id, peakViewers: { lt: n } }, data: { peakViewers: n } });
    }
    const user = await this.prisma.user.findUnique({ where: { id: u.sub }, select: { phone: true, email: true } });
    const exp = Math.floor(Date.now() / 1000) + TOKEN_TTL_S;
    const token = this.sign({ k: kind, id, u: u.sub, s: session.id, e: exp });
    return {
      url: `${this.publicApi}/v1/play/t/${token}/${kind}/${id}/index.m3u8`,
      sessionId: session.id,
      expiresAt: new Date(exp * 1000),
      watermark: user?.phone ? `•••• ${user.phone.slice(-4)}` : (user?.email?.replace(/^(.).*(@.*)$/, '$1•••$2') ?? ''),
      heartbeatSeconds: 30,
    };
  }

  /** Keeps playback alive; tells the player when another device has taken over. */
  async heartbeat(u: AuthUser, sessionId: string) {
    const s = await this.prisma.playbackSession.findUnique({ where: { id: sessionId } });
    if (!s || s.userId !== u.sub) throw new NotFoundException('Playback session not found');
    if (s.revokedAt) throw new ConflictException('Playing on another device');
    await this.prisma.playbackSession.update({ where: { id: s.id }, data: { lastSeenAt: new Date() } });
    if (s.targetType === 'LIVE') {
      const n = await this.viewers(s.targetId);
      await this.prisma.liveChannel.updateMany({ where: { id: s.targetId, peakViewers: { lt: n } }, data: { peakViewers: n } });
      return { ok: true, viewers: n };
    }
    return { ok: true };
  }

  private async sessionValid(c: PlayClaims) {
    const hit = this.sessionCache.get(c.s);
    if (hit && Date.now() - hit.at < 15_000) return hit.ok;
    const s = await this.prisma.playbackSession.findUnique({ where: { id: c.s } });
    const ok = !!s && !s.revokedAt && s.userId === c.u && s.targetId === c.id;
    this.sessionCache.set(c.s, { ok, at: Date.now() });
    if (this.sessionCache.size > 10_000) this.sessionCache.clear();
    return ok;
  }

  private async livePrefix(channelId: string) {
    const hit = this.channelCache.get(channelId);
    if (hit && Date.now() - hit.at < 5_000) return hit.prefix;
    const c: LiveChannel | null = await this.prisma.liveChannel.findUnique({ where: { id: channelId } });
    const prefix = c?.livePrefix ?? null;
    this.channelCache.set(channelId, { prefix, at: Date.now() });
    return prefix;
  }

  private async getObject(key: string) {
    try {
      return await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    } catch {
      throw new NotFoundException();
    }
  }

  /** A playlist or segment for a valid playback token. */
  async file(token: string, kind: string, id: string, path: string): Promise<FileResponse> {
    const c = this.verifyToken(token);
    if (c.k !== kind || c.id !== id) throw new ForbiddenException('Token is for another stream');
    if (!PLAY_PATH_RE.test(path)) throw new NotFoundException();
    if (!(await this.sessionValid(c))) throw new ConflictException('Playing on another device');
    const isPlaylist = path.endsWith('.m3u8');
    const contentType = isPlaylist ? 'application/vnd.apple.mpegurl' : 'video/mp2t';
    let key: string;
    if (kind === 'live') {
      const prefix = await this.livePrefix(id);
      if (!prefix) throw new NotFoundException();
      key = `${prefix}/${path}`;
      if (isPlaylist) {
        // Live playlists change every 2 s and every viewer polls them: share one S3 read per second.
        const hit = this.playlistCache.get(key);
        let body = hit && Date.now() - hit.at < 1_000 ? hit.body : null;
        if (!body) {
          const o = await this.getObject(key);
          body = Buffer.from(await o.Body!.transformToByteArray());
          this.playlistCache.set(key, { body, at: Date.now() });
          if (this.playlistCache.size > 2_000) this.playlistCache.clear();
        }
        return { body: Readable.from([body]), contentType, length: body.length, cacheControl: 'no-cache' };
      }
    } else {
      const a = await this.prisma.vodAsset.findUnique({ where: { id } });
      if (!a || !this.watchable(a)) throw new NotFoundException();
      key = `${a.s3Prefix}/${path}`;
    }
    const o = await this.getObject(key);
    return {
      body: o.Body as Readable,
      contentType,
      length: o.ContentLength,
      cacheControl: isPlaylist ? 'private, max-age=60' : 'private, max-age=86400',
    };
  }
}
