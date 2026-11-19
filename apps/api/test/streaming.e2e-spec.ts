/**
 * Live & recorded sessions over HTTP against a real PostgreSQL; Kubernetes Jobs and S3 are stubbed.
 * Skipped when DATABASE_URL is not set.
 */
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { randomBytes, randomInt } from 'crypto';
import { Readable } from 'stream';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AuthService } from '../src/modules/auth/auth.service';
import { PrismaService } from '../src/modules/prisma/prisma.service';
import { K8sJobsService } from '../src/modules/streaming/k8s-jobs.service';
import { StreamingService } from '../src/modules/streaming/streaming.service';

const run = process.env.DATABASE_URL ? describe : describe.skip;
jest.setTimeout(90_000);

class FakeK8s {
  enabled = true;
  namespace = 'test';
  jobs = new Map<string, any>();
  status = new Map<string, { active: number; succeeded: number; failed: number }>();
  async createJob(j: any) {
    this.jobs.set(j.metadata.name, j);
    this.status.set(j.metadata.name, { active: 1, succeeded: 0, failed: 0 });
  }
  async getJob(name: string) {
    const s = this.status.get(name);
    return s ? { name, ...s } : null;
  }
  async deleteJob(name: string) {
    this.jobs.delete(name);
  }
}

run('Live & recorded sessions', () => {
  let app: INestApplication;
  let http: ReturnType<typeof request>;
  const k8s = new FakeK8s();
  const tag = randomBytes(4).toString('hex');
  const bearer = (t: string) => ({ Authorization: `Bearer ${t}` });

  async function consumerLogin() {
    const p = `09${randomInt(700_000_000, 799_999_999)}`;
    const r1 = await http.post('/v1/auth/otp/request').send({ phone: p }).expect(200);
    const r2 = await http.post('/v1/auth/otp/verify').send({ phone: p, code: r1.body.devCode }).expect(200);
    return r2.body.accessToken as string;
  }
  async function acceptInvite(url: string) {
    const r = await http.post(`/v1/auth/invitations/${url.split('/invite/')[1]}/accept`).send({ password: 'password-12345', displayName: 'T' }).expect(200);
    return r.body.accessToken as string;
  }

  beforeAll(async () => {
    process.env.JWT_ACCESS_SECRET ??= 'e2e-secret';
    process.env.OTP_DEV_ECHO = 'true';
    process.env.STREAM_HOOK_SECRET = 'hook-secret-123';
    process.env.MAX_LIVE_CHANNELS = '1';
    process.env.STREAM_RTMP_URL = 'rtmp://live.event360.app:1936/live';
    process.env.PUBLIC_API_URL = 'https://api.example';
    const mod = await Test.createTestingModule({ imports: [AppModule] }).overrideProvider(K8sJobsService).useValue(k8s).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
    http = new Proxy({} as ReturnType<typeof request>, { get: (_t, m: string) => (request(app.getHttpServer()) as any)[m] });
    // The live-stream limit is global per environment: clear leftovers from earlier runs
    await app.get(PrismaService).liveChannel.updateMany({ where: { status: 'LIVE' }, data: { status: 'IDLE' } });
  });
  afterAll(() => app?.close());

  it('organizer streams; ticket holders watch live and the recording', async () => {
    // Org, owner, online event with one session, published
    const adm = await app.get(AuthService).createInvitation({ email: `adm-s-${tag}@e2e.test`, platformRole: 'PLATFORM_ADMIN' });
    const A = bearer(await acceptInvite(adm.url));
    const org = await http.post('/v1/admin/organizations').set(A).send({ name: `Stream Org ${tag}`, slug: `str-${tag}`, ownerEmail: `own-s-${tag}@e2e.test` }).expect(201);
    const orgId = org.body.organization.id;
    const O = bearer(await acceptInvite(org.body.inviteUrl));
    const cats = await http.get('/v1/categories').expect(200);
    const start = new Date(Date.now() + 1800e3);
    const ev = await http
      .post(`/v1/organizations/${orgId}/events`)
      .set(O)
      .send({ categoryId: cats.body[0].children[0].id, title: `Online Talk ${tag}`, format: 'ONLINE', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 2 * 3600e3).toISOString() })
      .expect(201);
    const eventId = ev.body.id;
    await http
      .put(`/v1/organizations/${orgId}/events/${eventId}/sessions`)
      .set(O)
      .send({ items: [{ title: 'Keynote', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3600e3).toISOString() }] })
      .expect(200);
    const tt = await http.post(`/v1/organizations/${orgId}/events/${eventId}/ticket-types`).set(O).send({ name: 'Online', priceMmk: 0, quota: 100, maxPerOrder: 2 }).expect(201);
    await http.post(`/v1/organizations/${orgId}/events/${eventId}/submit`).set(O).expect(200);
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);

    // Channel for the session; key shown once
    const ov = await http.get(`/v1/organizations/${orgId}/events/${eventId}/streaming`).set(O).expect(200);
    const sessionId = ov.body.sessions[0].id;
    const ch = await http.post(`/v1/organizations/${orgId}/events/${eventId}/streaming/sessions/${sessionId}/channel`).set(O).expect(201);
    expect(ch.body.obsServer).toBe('rtmp://live.event360.app:1936/live');
    const [ingestKey, query] = ch.body.obsStreamKey.split('?');
    const streamKey = new URLSearchParams(query).get('key');
    const ov2 = await http.get(`/v1/organizations/${orgId}/events/${eventId}/streaming`).set(O).expect(200);
    expect(JSON.stringify(ov2.body)).not.toContain(streamKey);

    // Hooks: secret, wrong key, then allowed → transcoder job started, channel LIVE
    const hook = (action: string, body: object, secret = 'hook-secret-123') => http.post(`/v1/streaming/hooks/${action}?secret=${secret}`).send(body);
    await hook('on_publish', { app: 'live', stream: ingestKey, param: `?key=${streamKey}` }, 'nope').expect(403);
    const bad = await hook('on_publish', { app: 'live', stream: ingestKey, param: '?key=wrong' }).expect(403);
    expect(bad.body.reason).toBe('bad stream key');
    const ok = await hook('on_publish', { app: 'live', stream: ingestKey, param: `?key=${streamKey}`, client_id: 'c1' }).expect(200);
    expect(ok.body).toEqual({ code: 0 });
    const jobName = [...k8s.jobs.keys()].find((n) => n.startsWith(`live-${ingestKey}`))!;
    expect(k8s.jobs.get(jobName).spec.template.spec.containers[0].command[2]).toContain(`/live/${ingestKey}`);

    // Public: live now
    const pub = await http.get(`/v1/events/${ev.body.slug}/streams`).expect(200);
    expect(pub.body.live[0]).toMatchObject({ channelId: ch.body.id, isLive: true, title: 'Keynote' });

    // Only ticket holders can watch
    const C = bearer(await consumerLogin());
    await http.post(`/v1/watch/live/${ch.body.id}/token`).set(C).expect(403);
    await http.post(`/v1/events/${eventId}/registrations`).set(C).send({ ticketTypeId: tt.body.id, quantity: 1 }).expect(201);
    const tok = await http.post(`/v1/watch/live/${ch.body.id}/token`).set(C).expect(201);
    expect(tok.body.url).toMatch(new RegExp(`^https://api.example/v1/play/t/[^/]+/live/${ch.body.id}/index.m3u8$`));
    expect(tok.body.watermark).toMatch(/^•••• \d{4}$/);
    const path = tok.body.url.replace('https://api.example', '');

    // Files come from S3 (the transcoder's rclone sidecar writes them there) — stub the bucket
    const svc = app.get(StreamingService);
    const objects = new Map<string, string>();
    jest.spyOn((svc as any).s3, 'send').mockImplementation(async (cmd: any) => {
      if (cmd instanceof GetObjectCommand) {
        const text = objects.get(String(cmd.input.Key));
        if (text === undefined) throw new Error('NoSuchKey');
        return { Body: Object.assign(Readable.from([Buffer.from(text)]), { transformToString: async () => text, transformToByteArray: async () => Buffer.from(text) }), ContentLength: Buffer.byteLength(text) } as any;
      }
      return {} as any;
    });
    const livePrefix = (await app.get(PrismaService).liveChannel.findUnique({ where: { id: ch.body.id } }))!.livePrefix!;
    expect(livePrefix).toMatch(/\/vod\//); // recording on: live HLS is written straight into the recording
    objects.set(`${livePrefix}/index.m3u8`, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nv4/index.m3u8\n');
    objects.set(`${livePrefix}/v4/seg_00001.ts`, 'G'.repeat(188));
    const m = await http.get(path).expect(200);
    expect(m.headers['content-type']).toContain('mpegurl');
    expect(m.headers['cache-control']).toBe('no-cache');
    const seg = await http.get(path.replace('index.m3u8', 'v4/seg_00001.ts')).expect(200);
    expect(seg.headers['content-type']).toBe('video/mp2t');
    await http.get(path.replace('index.m3u8', '../../etc/passwd')).expect(404);
    await http.get(path.replace('/live/', '/vod/')).expect(403); // token is for this stream only
    const forged = path.replace(/\/t\/([^.]+)\.([^/]+)\//, (_: string, b: string) => `/t/${b}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/`);
    await http.get(forged).expect(401);

    // Heartbeat counts viewers; a second device takes over the first
    const hb = await http.post(`/v1/watch/sessions/${tok.body.sessionId}/heartbeat`).set(C).expect(200);
    expect(hb.body.viewers).toBe(1);
    const tok2 = await http.post(`/v1/watch/live/${ch.body.id}/token`).set(C).expect(201);
    await http.post(`/v1/watch/sessions/${tok.body.sessionId}/heartbeat`).set(C).expect(409);
    await http.get(tok2.body.url.replace('https://api.example', '')).expect(200);

    // Editing the schedule keeps the session (by id), so the live channel survives; adding a 2nd session works
    await http
      .put(`/v1/organizations/${orgId}/events/${eventId}/sessions`)
      .set(O)
      .send({
        items: [
          { id: sessionId, title: 'Keynote (updated)', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3600e3).toISOString() },
          { title: 'Panel', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 7200e3).toISOString() }, // parallel track
        ],
      })
      .expect(200);
    // Removing the session that is live right now is refused
    await http
      .put(`/v1/organizations/${orgId}/events/${eventId}/sessions`)
      .set(O)
      .send({ items: [{ title: 'Other', startsAt: start.toISOString(), endsAt: new Date(start.getTime() + 3600e3).toISOString() }] })
      .expect(409);
    // (an unverified organizer's edit sends the event back to review)
    await http.post(`/v1/admin/events/${eventId}/approve`).set(A).expect(200);
    // Limit: only 1 live stream at a time here
    const ovP = await http.get(`/v1/organizations/${orgId}/events/${eventId}/streaming`).set(O).expect(200);
    const panel = ovP.body.sessions.find((x: any) => x.title === 'Panel');
    const ch2 = await http.post(`/v1/organizations/${orgId}/events/${eventId}/streaming/sessions/${panel.id}/channel`).set(O).expect(201);
    const [ik2, q2] = ch2.body.obsStreamKey.split('?');
    const lim = await hook('on_publish', { app: 'live', stream: ik2, param: `?${q2}` }).expect(403);
    expect(lim.body.reason).toMatch(/limit of 1/);

    // Stream ends → recording is processed → READY with duration (S3 stubbed)
    await hook('on_unpublish', { app: 'live', stream: ingestKey }).expect(200);
    k8s.status.set(jobName, { active: 0, succeeded: 1, failed: 0 });
    objects.set(`${livePrefix}/v4/index.m3u8`, '#EXTM3U\n#EXTINF:2.0,\na.ts\n#EXTINF:2.0,\nb.ts\n#EXT-X-ENDLIST\n');
    objects.set(`${livePrefix}/index.m3u8`, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500000\nv4/index.m3u8\n#EXT-X-ENDLIST\n');
    await svc.syncJobs();
    const ov3 = await http.get(`/v1/organizations/${orgId}/events/${eventId}/streaming`).set(O).expect(200);
    expect(ov3.body.sessions[0].channel.status).toBe('IDLE');
    const rec = ov3.body.recordings[0];
    expect(rec).toMatchObject({ status: 'READY', durationSec: 4, published: true, source: 'LIVE' });

    // Viewers see it; organizer can unpublish
    const pub2 = await http.get(`/v1/events/${eventId}/streams`).expect(200);
    expect(pub2.body.recordings.map((r: any) => r.id)).toEqual([rec.id]);
    const vt = await http.post(`/v1/watch/vod/${rec.id}/token`).set(C).expect(201);
    const vod = await http.get(vt.body.url.replace('https://api.example', '')).expect(200);
    expect(vod.text).toContain('#EXT-X-ENDLIST');
    await http.patch(`/v1/organizations/${orgId}/events/${eventId}/streaming/recordings/${rec.id}`).set(O).send({ published: false }).expect(200);
    expect((await http.get(`/v1/events/${eventId}/streams`).expect(200)).body.recordings).toEqual([]);
    await http.post(`/v1/watch/vod/${rec.id}/token`).set(C).expect(404);

    // Upload flow: presigned parts, then complete → transcode job
    const up = await http
      .post(`/v1/organizations/${orgId}/events/${eventId}/streaming/uploads`)
      .set(O)
      .send({ title: 'Highlights', fileName: 'hl.mp4', size: 40 * 1024 * 1024, contentType: 'video/mp4' })
      .expect(201);
    expect(up.body.parts).toHaveLength(3);
    expect(up.body.parts[0].url).toContain('partNumber=1');
    const done = await http
      .post(`/v1/organizations/${orgId}/events/${eventId}/streaming/uploads/${up.body.assetId}/complete`)
      .set(O)
      .send({ parts: [1, 2, 3].map((n) => ({ partNumber: n, etag: `"e${n}"` })) })
      .expect(200);
    expect(done.body.status).toBe('PROCESSING');
    expect([...k8s.jobs.keys()].some((n) => n.startsWith('vod-'))).toBe(true);

    // Crew / consumers cannot manage streaming
    await http.get(`/v1/organizations/${orgId}/events/${eventId}/streaming`).set(C).expect(403);
  });
});
