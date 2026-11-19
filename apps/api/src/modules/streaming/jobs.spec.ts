import { ladderArgs, LADDER, liveTranscoderJob, playlistDuration, uploadTranscoderJob } from './jobs';

const cfg = { ffmpegImage: 'ff:1', rcloneImage: 'rc:1', secretName: 'event360-secrets', avoidNodes: ['wo4'] };

describe('video pipeline jobs', () => {
  it('builds the full 5-rung ladder with 2 s segments', () => {
    const a = ladderArgs('rtmp://srs:1935/live/abc', '/out', 'live');
    expect(LADDER.map((r) => r.height)).toEqual([1080, 720, 480, 360, 240]);
    for (const r of LADDER) expect(a).toContain(`scale=-2:${r.height}`);
    expect(a).toContain('-hls_time 2');
    expect(a).toContain('-hls_playlist_type event');
    expect(a).toContain('-var_stream_map "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3 v:4,a:4"');
    expect(a).toContain('-master_pl_name index.m3u8');
    expect(ladderArgs('$SRC', '/w', 'vod')).toContain('-hls_playlist_type vod');
  });

  it('live job: ffmpeg + rclone sidecar copying to the prefix; final copy; non-root; no credentials inline', () => {
    const j: any = liveTranscoderJob(cfg, { name: 'live-abc-1', ingestKey: 'abc', srsRtmp: 'rtmp://srs:1935', record: true, prefix: 'dev/vod/A1' });
    const spec = j.spec.template.spec;
    expect(j.spec.backoffLimit).toBe(0);
    expect(spec.securityContext).toMatchObject({ runAsNonRoot: true, runAsUser: 10001 });
    const [ff, rc] = spec.containers;
    expect(ff.image).toBe('ff:1');
    expect(ff.command[2]).toContain('rtmp://srs:1935/live/abc');
    expect(ff.command[2]).toContain("trap 'touch /work/.done' EXIT");
    expect(ff.resources.requests.cpu).toBe('3');
    expect(rc.image).toBe('rc:1');
    expect(rc.command[2]).toContain('rclone copy /work "s3:$S3_BUCKET/dev/vod/A1" --max-age 30s --no-traverse');
    expect(rc.command[2]).not.toContain('purge');
    expect(rc.env.find((e: any) => e.name === 'RCLONE_CONFIG_S3_SECRET_ACCESS_KEY').valueFrom.secretKeyRef.key).toBe('S3_SECRET_ACCESS_KEY');
    expect(spec.volumes).toEqual([{ name: 'work', emptyDir: { sizeLimit: '20Gi' } }]);
    expect(spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values).toEqual(['wo4']);
    const noRec: any = liveTranscoderJob(cfg, { name: 'live-abc-2', ingestKey: 'abc', srsRtmp: 'rtmp://srs:1935', record: false, prefix: 'dev/live/live-abc-2' });
    expect(noRec.spec.template.spec.containers[1].command[2]).toContain('rclone purge "s3:$S3_BUCKET/dev/live/live-abc-2"');
  });

  it('upload job reads the presigned source, stores HLS and deletes the source', () => {
    const j: any = uploadTranscoderJob(cfg, { name: 'vod-1', assetId: 'A2', sourceUrl: 'https://s3/x?sig', sourceKey: 'dev/uploads/A2/source.mp4', vodPrefix: 'dev/vod/A2' });
    const spec = j.spec.template.spec;
    expect(spec.initContainers[0].env).toEqual([{ name: 'SRC', value: 'https://s3/x?sig' }]);
    expect(spec.containers[0].command[2]).toContain('rclone copy /work "s3:$S3_BUCKET/dev/vod/A2"');
    expect(spec.containers[0].command[2]).toContain('rclone deletefile "s3:$S3_BUCKET/dev/uploads/A2/source.mp4"');
  });

  it('sums playlist durations', () => {
    expect(playlistDuration('#EXTM3U\n#EXTINF:2.000,\na.ts\n#EXTINF:2.0,\nb.ts\n#EXTINF:1.5,\nc.ts\n#EXT-X-ENDLIST')).toBe(6);
  });
});
