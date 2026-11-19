/**
 * Copies HLS output from a transcoder Job's scratch folder to SeaweedFS (S3), using the same AWS SDK as the API.
 * Runs inside transcoder Jobs (API image):
 *
 *   node dist/streaming-uploader.js live <dir> <prefix> <record:1|0>   copy every second until <dir>/.done exists,
 *                                                                       then a final pass; with record=0 delete after 5 min
 *   node dist/streaming-uploader.js once <dir> <prefix> [deleteKey]    one complete copy (uploaded videos), then
 *                                                                       delete the uploaded source object
 *
 * Each pass snapshots the playlists first, uploads the segments they reference, then the playlists — so a playlist
 * never points at a segment that is not fully uploaded yet.
 */
import { DeleteObjectCommand, DeleteObjectsCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { existsSync, readdirSync, readFileSync } from 'fs';
import { join, relative } from 'path';

const [mode, dir, prefix, arg4] = process.argv.slice(2);
if (!['live', 'once'].includes(mode) || !dir || !prefix) {
  console.error('usage: streaming-uploader live|once <dir> <prefix> [record|deleteKey]');
  process.exit(2);
}
const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT,
  region: process.env.S3_REGION ?? 'us-east-1',
  forcePathStyle: true,
  credentials: { accessKeyId: process.env.S3_ACCESS_KEY_ID ?? '', secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? '' },
});
const bucket = process.env.S3_BUCKET ?? 'event360';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const uploaded = new Map<string, string>(); // relative path → content signature
const keys = new Set<string>();

function walk(d: string, out: string[] = []): string[] {
  if (!existsSync(d)) return out;
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (!e.name.startsWith('.')) out.push(p);
  }
  return out;
}

async function put(rel: string, body: Buffer, playlist: boolean) {
  const Key = `${prefix}/${rel}`;
  for (let attempt = 1; ; attempt++) {
    try {
      await s3.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key,
          Body: body,
          ContentType: playlist ? 'application/vnd.apple.mpegurl' : 'video/mp2t',
          CacheControl: playlist ? 'no-cache' : 'public, max-age=31536000, immutable',
        }),
      );
      keys.add(Key);
      return;
    } catch (e) {
      if (attempt >= 4) throw e;
      await sleep(500 * attempt);
    }
  }
}

async function pass(): Promise<number> {
  const files = walk(dir);
  const playlists = files.filter((f) => f.endsWith('.m3u8'));
  // 1. Snapshot playlists (what players will be told exists)
  const snap = playlists.map((f) => ({ rel: relative(dir, f), body: readFileSync(f) }));
  // 2. Segments referenced by those playlists (complete by the time ffmpeg lists them)
  const wanted = new Set<string>();
  for (const p of snap) {
    const base = p.rel.includes('/') ? p.rel.slice(0, p.rel.lastIndexOf('/') + 1) : '';
    for (const line of p.body.toString().split('\n')) {
      const l = line.trim();
      if (l && !l.startsWith('#') && l.endsWith('.ts')) wanted.add(base + l);
    }
  }
  let n = 0;
  const segs = [...wanted].filter((rel) => !uploaded.has(rel) && existsSync(join(dir, rel)));
  // A few at a time keeps latency low without flooding the gateway
  for (let i = 0; i < segs.length; i += 8) {
    await Promise.all(
      segs.slice(i, i + 8).map(async (rel) => {
        const buf = readFileSync(join(dir, rel));
        await put(rel, buf, false);
        uploaded.set(rel, String(buf.length));
        n++;
      }),
    );
  }
  // 3. Playlists that changed (variant playlists before the master)
  snap.sort((a, b) => (a.rel.includes('/') === b.rel.includes('/') ? 0 : a.rel.includes('/') ? -1 : 1));
  for (const p of snap) {
    const sig = `${p.body.length}:${p.body.subarray(-64).toString('base64')}`;
    if (uploaded.get(p.rel) === sig) continue;
    await put(p.rel, p.body, true);
    uploaded.set(p.rel, sig);
    n++;
  }
  return n;
}

async function removeAll() {
  const list = [...keys];
  for (let i = 0; i < list.length; i += 500) {
    await s3.send(new DeleteObjectsCommand({ Bucket: bucket, Delete: { Objects: list.slice(i, i + 500).map((Key) => ({ Key })) } }));
  }
}

(async () => {
  if (mode === 'once') {
    const n = await pass();
    console.log(`uploaded ${n} files to ${prefix}`);
    if (arg4) await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: arg4 })).catch(() => undefined);
    return;
  }
  const record = arg4 !== '0';
  let total = 0;
  while (!existsSync(join(dir, '.done'))) {
    total += await pass().catch((e) => (console.error(`pass failed: ${(e as Error).message}`), 0));
    await sleep(1000);
  }
  total += await pass(); // final: playlists now end with #EXT-X-ENDLIST
  console.log(`live ended; uploaded ${total} files to ${prefix}`);
  if (!record) {
    await sleep(300_000); // let viewers finish
    await removeAll();
    console.log('recording off: live files removed');
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
