'use client';

import Hls from 'hls.js';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  completeUploadAction,
  createChannelAction,
  createUploadAction,
  deleteChannelAction,
  deleteRecordingAction,
  previewTokenAction,
  rotateKeyAction,
  setRecordingAction,
  stopChannelAction,
  streamingOverviewAction,
  updateRecordingAction,
  type StreamingOverview,
  type StreamKeys,
} from '../organizer/actions';

export interface LiveLabels {
  intro: string;
  noSessions: string;
  createChannel: string;
  server: string;
  streamKey: string;
  srt: string;
  keyOnce: string;
  copy: string;
  newKey: string;
  newKeyConfirm: string;
  recordOn: string;
  stop: string;
  stopConfirm: string;
  removeChannel: string;
  removeConfirm: string;
  preview: string;
  close: string;
  live: string;
  idle: string;
  viewers: string;
  peak: string;
  obsHelp: string;
  pipelineOff: string;
  recordings: string;
  noRecordings: string;
  published: string;
  availableUntil: string;
  duration: string;
  status: Record<string, string>;
  source: Record<string, string>;
  delete: string;
  deleteConfirm: string;
  upload: string;
  uploadTitle: string;
  uploadFile: string;
  uploadHint: string;
  uploading: string;
  save: string;
}

const fmtDur = (s: number | null) => (s == null ? '—' : `${Math.floor(s / 3600) ? `${Math.floor(s / 3600)}:` : ''}${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`);
const fmtTime = (d: string, lang: string) => new Date(d).toLocaleString(lang === 'my' ? 'my-MM' : 'en-GB', { timeZone: 'Asia/Yangon', dateStyle: 'medium', timeStyle: 'short' });
const toDateInput = (d: string | null) => (d ? new Date(new Date(d).getTime() + 6.5 * 3600e3).toISOString().slice(0, 10) : '');

function Copy({ value, label }: { value: string; label: string }) {
  return (
    <div className="row" style={{ gap: 6, alignItems: 'stretch' }}>
      <div className="code" style={{ flex: 1 }}>{value}</div>
      <button type="button" className="secondary" onClick={() => navigator.clipboard?.writeText(value)}>{label}</button>
    </div>
  );
}

/** HLS preview (hls.js; Safari plays HLS natively). */
function Player({ url, onClose, closeLabel, watermark }: { url: string; onClose: () => void; closeLabel: string; watermark: string }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const v = ref.current!;
    if (Hls.isSupported()) {
      const h = new Hls({ lowLatencyMode: false });
      h.loadSource(url);
      h.attachMedia(v);
      return () => h.destroy();
    }
    v.src = url;
  }, [url]);
  return (
    <div className="card" style={{ position: 'relative', marginTop: 8 }}>
      <video ref={ref} controls autoPlay muted playsInline style={{ width: '100%', maxHeight: 420, background: '#000', borderRadius: 8 }} />
      <span style={{ position: 'absolute', top: 18, right: 24, color: 'rgba(255,255,255,.6)', fontSize: 12, pointerEvents: 'none' }}>{watermark}</span>
      <button type="button" className="secondary" onClick={onClose} style={{ marginTop: 8 }}>{closeLabel}</button>
    </div>
  );
}

export function LiveStudio({ orgId, eventId, initial, labels, lang }: { orgId: string; eventId: string; initial: StreamingOverview; labels: LiveLabels; lang: string }) {
  const [ov, setOv] = useState(initial);
  const [keys, setKeys] = useState<Record<string, StreamKeys>>({});
  const [error, setError] = useState<string | null>(null);
  const [preview, setPreview] = useState<{ id: string; url: string; watermark: string } | null>(null);
  const [upload, setUpload] = useState<{ name: string; pct: number } | null>(null);

  const refresh = useCallback(async () => {
    const r = await streamingOverviewAction(orgId, eventId);
    if (r.ok) setOv(r.data);
  }, [orgId, eventId]);

  useEffect(() => {
    const busy = ov.sessions.some((s) => s.channel?.status === 'LIVE') || ov.recordings.some((r) => r.status === 'PROCESSING' || r.status === 'UPLOADING');
    const t = setInterval(() => !document.hidden && refresh(), busy ? 5000 : 20000);
    return () => clearInterval(t);
  }, [ov, refresh]);

  const run = async <T,>(p: Promise<{ ok: true; data: T } | { ok: false; error: string }>, then?: (d: T) => void) => {
    setError(null);
    const r = await p;
    if (!r.ok) setError(r.error);
    else then?.(r.data);
    await refresh();
  };

  const startPreview = async (kind: 'live' | 'vod', id: string) => {
    const r = await previewTokenAction(kind, id);
    if (r.ok) setPreview({ id, url: r.data.url, watermark: r.data.watermark });
    else setError(r.error);
  };

  async function doUpload(form: HTMLFormElement) {
    const fd = new FormData(form);
    const file = fd.get('file') as File | null;
    const title = String(fd.get('title') ?? '').trim();
    if (!file || !file.size || !title) return;
    setError(null);
    setUpload({ name: file.name, pct: 0 });
    const c = await createUploadAction(orgId, eventId, {
      title,
      sessionId: String(fd.get('sessionId') ?? '') || undefined,
      fileName: file.name,
      size: file.size,
      contentType: file.type || 'video/mp4',
    });
    if (!c.ok) {
      setUpload(null);
      setError(c.error);
      return;
    }
    const { assetId, partSize, parts } = c.data;
    const done: { partNumber: number; etag: string }[] = [];
    const sent = new Array(parts.length).fill(0);
    const put = (p: { partNumber: number; url: string }) =>
      new Promise<void>((resolve, reject) => {
        const blob = file.slice((p.partNumber - 1) * partSize, p.partNumber * partSize);
        const x = new XMLHttpRequest();
        x.open('PUT', p.url);
        x.upload.onprogress = (e) => {
          sent[p.partNumber - 1] = e.loaded;
          setUpload({ name: file.name, pct: Math.round((sent.reduce((a, b) => a + b, 0) / file.size) * 100) });
        };
        x.onload = () => {
          const etag = x.getResponseHeader('ETag');
          if (x.status >= 200 && x.status < 300 && etag) {
            done.push({ partNumber: p.partNumber, etag });
            resolve();
          } else reject(new Error(`Upload failed (HTTP ${x.status})`));
        };
        x.onerror = () => reject(new Error('Upload failed (network)'));
        x.send(blob);
      });
    try {
      const queue = [...parts];
      await Promise.all(Array.from({ length: 3 }, async () => {
        while (queue.length) await put(queue.shift()!);
      }));
      await run(completeUploadAction(orgId, eventId, assetId, done));
      form.reset();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setUpload(null);
    }
  }

  return (
    <div>
      <p className="muted">{labels.intro}</p>
      {!ov.pipelineReady && <div className="error">{labels.pipelineOff}</div>}
      {error && <div className="error">{error}</div>}
      {ov.sessions.length === 0 && <p className="muted">{labels.noSessions}</p>}
      {ov.sessions.map((s) => {
        const c = s.channel;
        const k = c ? keys[c.id] : undefined;
        const title = lang === 'my' && s.titleMy ? s.titleMy : s.title;
        return (
          <div key={s.id} className="card" style={{ marginBottom: 10 }}>
            <div className="row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <strong>{title}</strong>{' '}
                <span className="muted">{fmtTime(s.startsAt, lang)}</span>
              </div>
              {c && (
                <span className={`badge ${c.status === 'LIVE' ? 'REJECTED' : 'DRAFT'}`}>
                  {c.status === 'LIVE' ? `● ${labels.live} · ${labels.viewers}: ${c.viewers}` : labels.idle}
                </span>
              )}
            </div>
            {!c && (
              <button type="button" style={{ marginTop: 8 }} onClick={() => run(createChannelAction(orgId, eventId, s.id), (d) => setKeys({ ...keys, [s.id]: d }))}>
                {labels.createChannel}
              </button>
            )}
            {c && (
              <div style={{ marginTop: 8 }}>
                <label className="muted">{labels.server}</label>
                <Copy value={c.obsServer} label={labels.copy} />
                <label className="muted">{labels.streamKey}</label>
                <Copy value={(k ?? keys[s.id])?.obsStreamKey ?? c.obsStreamKey} label={labels.copy} />
                {(k ?? keys[s.id])?.srtUrl && (
                  <>
                    <label className="muted">{labels.srt}</label>
                    <Copy value={(k ?? keys[s.id])!.srtUrl!} label={labels.copy} />
                  </>
                )}
                {(k ?? keys[s.id]) ? <p className="ok" style={{ margin: '6px 0' }}>{labels.keyOnce}</p> : <p className="muted" style={{ margin: '6px 0' }}>{labels.obsHelp}</p>}
                <label className="check">
                  <input type="checkbox" checked={c.recordingEnabled} onChange={(e) => run(setRecordingAction(orgId, eventId, c.id, e.target.checked))} /> {labels.recordOn}
                </label>
                <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
                  {c.status === 'LIVE' && (
                    <>
                      <button type="button" onClick={() => startPreview('live', c.id)}>{labels.preview}</button>
                      <button type="button" className="danger" onClick={() => confirm(labels.stopConfirm) && run(stopChannelAction(orgId, eventId, c.id))}>{labels.stop}</button>
                    </>
                  )}
                  {c.status !== 'LIVE' && (
                    <>
                      <button type="button" className="secondary" onClick={() => confirm(labels.newKeyConfirm) && run(rotateKeyAction(orgId, eventId, c.id), (d) => setKeys({ ...keys, [c.id]: d }))}>{labels.newKey}</button>
                      <button type="button" className="secondary" onClick={() => confirm(labels.removeConfirm) && run(deleteChannelAction(orgId, eventId, c.id))}>{labels.removeChannel}</button>
                    </>
                  )}
                  {c.peakViewers > 0 && <span className="muted">{labels.peak}: {c.peakViewers}</span>}
                </div>
                {preview?.id === c.id && <Player url={preview.url} watermark={preview.watermark} closeLabel={labels.close} onClose={() => setPreview(null)} />}
              </div>
            )}
          </div>
        );
      })}

      <h3>{labels.recordings}</h3>
      <div className="card table-wrap">
        {ov.recordings.length === 0 ? (
          <p className="muted">{labels.noRecordings}</p>
        ) : (
          <table>
            <thead>
              <tr><th>{labels.uploadTitle}</th><th>{labels.duration}</th><th /><th>{labels.published}</th><th>{labels.availableUntil}</th><th /></tr>
            </thead>
            <tbody>
              {ov.recordings.map((r) => (
                <tr key={r.id}>
                  <td>{lang === 'my' && r.titleMy ? r.titleMy : r.title}<br /><span className="muted">{labels.source[r.source]} · {fmtTime(r.createdAt, lang)}</span></td>
                  <td>{fmtDur(r.durationSec)}</td>
                  <td><span className={`badge ${r.status === 'READY' ? 'PUBLISHED' : r.status === 'FAILED' ? 'REJECTED' : 'SUBMITTED'}`}>{labels.status[r.status]}</span>{r.error && <><br /><span className="muted">{r.error}</span></>}</td>
                  <td><input type="checkbox" checked={r.published} disabled={r.status !== 'READY'} onChange={(e) => run(updateRecordingAction(orgId, eventId, r.id, { published: e.target.checked }))} /></td>
                  <td>
                    <input
                      type="date"
                      defaultValue={toDateInput(r.availableUntil)}
                      onBlur={(e) => run(updateRecordingAction(orgId, eventId, r.id, { availableUntil: e.target.value ? new Date(`${e.target.value}T23:59:00+06:30`).toISOString() : null }))}
                    />
                  </td>
                  <td className="row" style={{ gap: 6 }}>
                    {r.status === 'READY' && <button type="button" className="secondary" onClick={() => startPreview('vod', r.id)}>{labels.preview}</button>}
                    <button type="button" className="danger" onClick={() => confirm(labels.deleteConfirm) && run(deleteRecordingAction(orgId, eventId, r.id))}>{labels.delete}</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {preview && ov.recordings.some((r) => r.id === preview.id) && <Player url={preview.url} watermark={preview.watermark} closeLabel={labels.close} onClose={() => setPreview(null)} />}
      </div>

      <h3>{labels.upload}</h3>
      <form
        className="card"
        onSubmit={(e) => {
          e.preventDefault();
          doUpload(e.currentTarget);
        }}
      >
        <p className="muted">{labels.uploadHint}</p>
        <div className="grid">
          <div className="field"><label>{labels.uploadTitle}</label><input name="title" required maxLength={200} /></div>
          <div className="field">
            <label>{labels.uploadFile}</label>
            <input name="file" type="file" accept="video/*" required />
          </div>
          {ov.sessions.length > 0 && (
            <div className="field">
              <label>—</label>
              <select name="sessionId" defaultValue="">
                <option value="">—</option>
                {ov.sessions.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
              </select>
            </div>
          )}
        </div>
        {upload ? (
          <div>
            <p>{labels.uploading} {upload.name}: {upload.pct}%</p>
            <div className="progress"><div style={{ width: `${upload.pct}%` }} /></div>
          </div>
        ) : (
          <button type="submit">{labels.upload}</button>
        )}
      </form>
    </div>
  );
}
