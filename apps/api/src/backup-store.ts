/**
 * Backup storage helper, run inside the backup CronJobs (API image, S3 settings from event360-secrets):
 *
 *   node dist/backup-store.js put <file>              store a pg_dump as backups/daily/<YYYY-MM-DD>.dump (Myanmar date);
 *                                                     on Sundays also backups/weekly/; prune to 14 daily + 8 weekly
 *   node dist/backup-store.js fetch-latest <file>     download the newest daily dump (for the restore test)
 *   node dist/backup-store.js report <file.json>      store a restore-test report as backups/restore-tests/<date>.json
 */
import { CopyObjectCommand, DeleteObjectsCommand, GetObjectCommand, ListObjectsV2Command, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createReadStream, createWriteStream, readFileSync, statSync, writeFileSync } from 'fs';
import { pipeline } from 'stream/promises';
import type { Readable } from 'stream';

export const KEEP_DAILY = 14;
export const KEEP_WEEKLY = 8;

/** Myanmar date (UTC+06:30) as YYYY-MM-DD, and whether it is a Sunday. */
export function mmtDate(now = new Date()) {
  const d = new Date(now.getTime() + 6.5 * 3600e3);
  return { day: d.toISOString().slice(0, 10), sunday: d.getUTCDay() === 0 };
}

/** Keys to delete so that only the newest `keep` remain (keys sort by date). */
export function toPrune(keys: string[], keep: number) {
  return [...keys].sort().reverse().slice(keep);
}

function client() {
  return new S3Client({
    endpoint: process.env.S3_ENDPOINT,
    region: process.env.S3_REGION ?? 'us-east-1',
    forcePathStyle: true,
    credentials: { accessKeyId: process.env.S3_ACCESS_KEY_ID ?? '', secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? '' },
  });
}

async function listKeys(s3: S3Client, bucket: string, prefix: string) {
  const keys: string[] = [];
  let token: string | undefined;
  do {
    const r = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, ContinuationToken: token }));
    for (const o of r.Contents ?? []) if (o.Key) keys.push(o.Key);
    token = r.NextContinuationToken;
  } while (token);
  return keys;
}

async function main() {
  const [cmd, file] = process.argv.slice(2);
  const bucket = process.env.S3_BUCKET ?? 'event360';
  const base = `${(process.env.S3_PREFIX ?? 'dev').replace(/\/+$/, '')}/backups`;
  const s3 = client();
  const { day, sunday } = mmtDate();

  if (cmd === 'put') {
    const size = statSync(file).size;
    if (size < 1024) throw new Error(`dump looks empty (${size} bytes)`);
    const key = `${base}/daily/${day}.dump`;
    await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: createReadStream(file), ContentLength: size, ContentType: 'application/octet-stream' }));
    console.log(`stored ${key} (${Math.round(size / 1024)} KB)`);
    if (sunday) {
      await s3.send(new CopyObjectCommand({ Bucket: bucket, Key: `${base}/weekly/${day}.dump`, CopySource: `${bucket}/${key}` }));
      console.log(`weekly copy ${base}/weekly/${day}.dump`);
    }
    for (const [kind, keep] of [['daily', KEEP_DAILY], ['weekly', KEEP_WEEKLY]] as const) {
      const old = toPrune((await listKeys(s3, bucket, `${base}/${kind}/`)).filter((k) => k.endsWith('.dump')), keep);
      if (old.length) {
        await s3.send(new DeleteObjectsCommand({ Bucket: bucket, Delete: { Objects: old.map((Key) => ({ Key })) } }));
        console.log(`pruned ${old.length} old ${kind} backup(s)`);
      }
    }
    return;
  }

  if (cmd === 'fetch-latest') {
    const latest = (await listKeys(s3, bucket, `${base}/daily/`)).filter((k) => k.endsWith('.dump')).sort().pop();
    if (!latest) throw new Error('no backups to test');
    const o = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: latest }));
    await pipeline(o.Body as Readable, createWriteStream(file));
    // Tell the restore step which backup it is testing
    writeFileSync(`${file}.name`, latest.slice(base.length + 1));
    console.log(`fetched ${latest} (${Math.round(statSync(file).size / 1024)} KB)`);
    return;
  }

  if (cmd === 'report') {
    const body = readFileSync(file);
    JSON.parse(body.toString()); // must be valid JSON
    const key = `${base}/restore-tests/${day}.json`;
    await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: 'application/json' }));
    console.log(`stored ${key}: ${body.toString()}`);
    return;
  }

  console.error('usage: backup-store put|fetch-latest|report <file>');
  process.exit(2);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(`backup-store: ${(e as Error).message}`);
    process.exit(1);
  });
}
