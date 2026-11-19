/**
 * Kubernetes Job specs for the video pipeline (pure functions, unit-tested). No shared volumes: each Job works in
 * its own scratch space and copies HLS to SeaweedFS (S3) with dist/streaming-uploader.js (API image, same AWS SDK
 * as the API); the API serves viewers from S3.
 *
 * Live:   ffmpeg pulls rtmp://srs/live/<ingestKey> and writes a 5-rung HLS ladder (2 s segments) to /work; the
 *         uploader sidecar copies new segments + playlists to <prefix> every second. When the stream ends ffmpeg exits,
 *         the uploader does a final pass (the recording is then complete in place), or — with recording off — removes
 *         the live files after 5 minutes.
 * Upload: ffmpeg reads the uploaded file (presigned URL) into the same ladder as VOD; the uploader copies it to S3
 *         and deletes the source.
 */

export interface Rung {
  name: string; // v0..v4
  height: number;
  videoKbps: number;
  audioKbps: number;
}

/** Full ladder (1080p → 240p for low-bandwidth mobile). */
export const LADDER: Rung[] = [
  { name: 'v0', height: 1080, videoKbps: 5000, audioKbps: 128 },
  { name: 'v1', height: 720, videoKbps: 2800, audioKbps: 128 },
  { name: 'v2', height: 480, videoKbps: 1400, audioKbps: 96 },
  { name: 'v3', height: 360, videoKbps: 800, audioKbps: 96 },
  { name: 'v4', height: 240, videoKbps: 400, audioKbps: 64 },
];

export interface PipelineConfig {
  ffmpegImage: string;
  apiImage: string; // runs dist/streaming-uploader.js
  secretName: string; // event360-secrets (S3 credentials, via envFrom)
  avoidNodes?: string[];
}

/** ffmpeg arguments for the whole ladder, writing <out>/v%v/index.m3u8 + master <out>/index.m3u8. */
export function ladderArgs(input: string, out: string, mode: 'live' | 'vod'): string {
  const n = LADDER.length;
  const split = `[0:v]split=${n}${LADDER.map((_, i) => `[s${i}]`).join('')};` + LADDER.map((r, i) => `[s${i}]scale=-2:${r.height}[o${i}]`).join(';');
  const maps = [...LADDER.map((_, i) => `-map "[o${i}]"`), ...LADDER.map(() => '-map 0:a:0')].join(' ');
  const rates = LADDER.map(
    (r, i) =>
      `-b:v:${i} ${r.videoKbps}k -maxrate:v:${i} ${Math.round(r.videoKbps * 1.07)}k -bufsize:v:${i} ${Math.round(r.videoKbps * 1.5)}k -b:a:${i} ${r.audioKbps}k`,
  ).join(' ');
  const streamMap = LADDER.map((_, i) => `v:${i},a:${i}`).join(' ');
  return [
    'ffmpeg -hide_banner -loglevel warning',
    mode === 'live' ? '-rw_timeout 15000000' : '',
    `-i "${input}"`,
    `-filter_complex "${split}"`,
    maps,
    '-c:v libx264 -preset veryfast -profile:v main -pix_fmt yuv420p -sc_threshold 0',
    '-force_key_frames "expr:gte(t,n_forced*2)"',
    rates,
    '-c:a aac -ar 48000 -ac 2',
    `-f hls -hls_time 2 -hls_list_size 0 -hls_playlist_type ${mode === 'live' ? 'event' : 'vod'} -hls_flags independent_segments`,
    `-master_pl_name index.m3u8 -hls_segment_filename "${out}/v%v/seg_%05d.ts"`,
    `-var_stream_map "${streamMap}" "${out}/v%v/index.m3u8"`,
  ]
    .filter(Boolean)
    .join(' ');
}

function affinity(avoid?: string[]) {
  return avoid?.length
    ? {
        nodeAffinity: {
          requiredDuringSchedulingIgnoredDuringExecution: {
            nodeSelectorTerms: [{ matchExpressions: [{ key: 'kubernetes.io/hostname', operator: 'NotIn', values: avoid }] }],
          },
        },
      }
    : undefined;
}

function job(name: string, labels: Record<string, string>, deadline: number, spec: Record<string, unknown>) {
  return {
    apiVersion: 'batch/v1',
    kind: 'Job',
    metadata: { name, labels: { 'app.kubernetes.io/part-of': 'event360', ...labels } },
    spec: {
      backoffLimit: 0,
      ttlSecondsAfterFinished: 3600,
      activeDeadlineSeconds: deadline,
      template: {
        metadata: { labels: { 'app.kubernetes.io/part-of': 'event360', ...labels } },
        spec: {
          restartPolicy: 'Never',
          securityContext: { runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001, fsGroup: 10001 },
          ...spec,
        },
      },
    },
  };
}

const ffmpegResources = { requests: { cpu: '3', memory: '1Gi' }, limits: { cpu: '6', memory: '3Gi' } };
const uploaderResources = { requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } };
const scratch = (gi: number) => [{ name: 'work', emptyDir: { sizeLimit: `${gi}Gi` } }];
const workMount = [{ name: 'work', mountPath: '/work' }];
const noPriv = { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } };

/** Transcoder for one live stream (one Job per publish), writing to `s3:<bucket>/<prefix>`. */
export function liveTranscoderJob(
  cfg: PipelineConfig,
  p: { name: string; ingestKey: string; srsRtmp: string; record: boolean; prefix: string },
) {
  // Retry while the stream is still coming up; a run longer than 20 s means the stream really ended.
  const transcode = [
    'set -u',
    "trap 'touch /work/.done' EXIT",
    `mkdir -p ${LADDER.map((r) => `/work/${r.name}`).join(' ')}`,
    'n=0',
    'while :; do',
    '  t0=$(date +%s)',
    `  ${ladderArgs(`${p.srsRtmp}/live/${p.ingestKey}`, '/work', 'live')}`,
    '  dur=$(( $(date +%s) - t0 ))',
    '  [ "$dur" -gt 20 ] && exit 0',
    '  n=$((n+1)); [ "$n" -ge 15 ] && exit 1',
    '  sleep 2',
    'done',
  ].join('\n');
  return job(p.name, { 'event360/role': 'live-transcoder', 'event360/ingest': p.ingestKey }, 12 * 3600, {
    affinity: affinity(cfg.avoidNodes),
    volumes: scratch(20),
    containers: [
      { name: 'transcode', image: cfg.ffmpegImage, command: ['sh', '-c', transcode], volumeMounts: workMount, resources: ffmpegResources, securityContext: noPriv },
      {
        name: 'upload',
        image: cfg.apiImage,
        command: ['node', 'dist/streaming-uploader.js', 'live', '/work', p.prefix, p.record ? '1' : '0'],
        envFrom: [{ secretRef: { name: cfg.secretName } }],
        volumeMounts: workMount,
        resources: uploaderResources,
        securityContext: noPriv,
      },
    ],
  });
}

/** Transcoder for an uploaded video file (presigned GET URL) into the same ladder, stored as VOD. */
export function uploadTranscoderJob(cfg: PipelineConfig, p: { name: string; assetId: string; sourceUrl: string; sourceKey: string; vodPrefix: string }) {
  const transcode = ['set -eu', `mkdir -p ${LADDER.map((r) => `/work/${r.name}`).join(' ')}`, ladderArgs('$SRC', '/work', 'vod')].join('\n');
  return job(p.name, { 'event360/role': 'vod-transcoder', 'event360/asset': p.assetId }, 6 * 3600, {
    affinity: affinity(cfg.avoidNodes),
    volumes: scratch(30),
    initContainers: [
      {
        name: 'transcode',
        image: cfg.ffmpegImage,
        command: ['sh', '-c', transcode],
        env: [{ name: 'SRC', value: p.sourceUrl }],
        volumeMounts: workMount,
        resources: ffmpegResources,
        securityContext: noPriv,
      },
    ],
    containers: [
      {
        name: 'store',
        image: cfg.apiImage,
        command: ['node', 'dist/streaming-uploader.js', 'once', '/work', p.vodPrefix, p.sourceKey],
        envFrom: [{ secretRef: { name: cfg.secretName } }],
        volumeMounts: workMount,
        resources: uploaderResources,
        securityContext: noPriv,
      },
    ],
  });
}

/** Sum of EXTINF durations in a media playlist. */
export function playlistDuration(m3u8: string): number {
  let total = 0;
  for (const m of m3u8.matchAll(/#EXTINF:([\d.]+)/g)) total += Number(m[1]);
  return Math.round(total);
}
