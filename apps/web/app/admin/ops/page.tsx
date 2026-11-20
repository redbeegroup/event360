import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { api } from '../../lib/api';
import { fmtDate, t } from '../../lib/i18n';
import { resolveErrorAction } from '../actions';

export const dynamic = 'force-dynamic';

interface Check {
  name: string;
  ok: boolean;
  consecutiveFailures: number;
  lastError: string | null;
  detail: string | null;
  lastCheckedAt: string | null;
  changedAt: string;
}
interface Incident {
  id: string;
  check: string;
  error: string;
  startedAt: string;
  endedAt: string | null;
}
interface BackupFile {
  key: string;
  size: number;
  at: string;
}
interface RestoreTest {
  ok: boolean;
  backup?: string;
  tables?: number;
  rows?: Record<string, number>;
  durationSec?: number;
  testedAt?: string;
  error?: string;
}
interface Status {
  checks: Check[];
  incidents: Incident[];
  openErrors: number;
  release: string | null;
  backups: { daily: BackupFile[]; weekly: BackupFile[]; restoreTests: BackupFile[]; lastRestoreTest: RestoreTest | null };
}
interface ErrorGroup {
  id: string;
  source: string;
  message: string;
  stack: string | null;
  path: string | null;
  count: number;
  firstSeen: string;
  lastSeen: string;
  lastRelease: string | null;
  resolvedAt: string | null;
}

const SOURCES = ['api', 'portal', 'site', 'user_app', 'crew_app', 'organizer_app'];

function size(bytes: number) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function duration(from: string, to: string | null) {
  const mins = Math.max(1, Math.round(((to ? new Date(to).getTime() : Date.now()) - new Date(from).getTime()) / 60000));
  return mins >= 120 ? `${Math.round(mins / 60)} h` : `${mins} min`;
}

export default async function OpsPage({ searchParams }: { searchParams: Promise<{ status?: string; source?: string }> }) {
  const sp = await searchParams;
  const resolved = sp.status === 'resolved';
  const source = SOURCES.includes(sp.source ?? '') ? sp.source! : '';
  const qs = new URLSearchParams({ ...(resolved ? { status: 'resolved' } : {}), ...(source ? { source } : {}) }).toString();
  const [tr, st, errors] = await Promise.all([t(), api<Status>('/admin/ops/status'), api<ErrorGroup[]>(`/admin/ops/errors${qs ? `?${qs}` : ''}`)]);
  const down = st.checks.filter((c) => !c.ok);
  const lastDaily = st.backups.daily[0];
  const rt = st.backups.lastRestoreTest;
  const link = (p: { status?: string; source?: string }) => {
    const q = new URLSearchParams({ ...(p.status ? { status: p.status } : {}), ...(p.source ? { source: p.source } : {}) }).toString();
    return `/admin/ops${q ? `?${q}` : ''}#errors`;
  };

  return (
    <>
      <h1>{tr.opsTitle}</h1>
      <p className="muted">
        {tr.opsHint} {st.release && <>· {tr.opsRelease}: <code>{st.release.slice(0, 7)}</code></>}
      </p>

      <div className="grid" style={{ marginBottom: 20 }}>
        <div className="card">
          <div className="muted">{tr.opsSystems}</div>
          <h2 style={{ margin: '4px 0' }}>
            {st.checks.length === 0 ? tr.opsNoChecks : down.length === 0 ? tr.opsAllOk : `${down.length} ${tr.opsDown}`}
          </h2>
        </div>
        <div className="card">
          <div className="muted">{tr.opsLastBackup}</div>
          <h2 style={{ margin: '4px 0' }}>{lastDaily ? fmtDate(lastDaily.at, tr.lang) : tr.opsNoBackups}</h2>
          {lastDaily && <small className="muted">{size(lastDaily.size)}</small>}
        </div>
        <div className="card">
          <div className="muted">{tr.opsRestoreTest}</div>
          <h2 style={{ margin: '4px 0' }}>{!rt ? tr.opsNotYet : rt.ok ? tr.opsPassed : tr.opsFailed}</h2>
          {rt?.testedAt && <small className="muted">{fmtDate(rt.testedAt, tr.lang)}</small>}
        </div>
        <div className="card">
          <div className="muted">{tr.opsOpenErrors}</div>
          <h2 style={{ margin: '4px 0' }}>{st.openErrors}</h2>
        </div>
      </div>

      <h2>{tr.opsChecks}</h2>
      <div className="card table-wrap">
        {st.checks.length === 0 ? (
          <p className="muted">{tr.opsNoChecks}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.opsCheck}</th><th>{tr.status}</th><th>{tr.opsDetail}</th><th>{tr.opsSince}</th><th>{tr.opsLastChecked}</th></tr></thead>
            <tbody>
              {st.checks.map((c) => (
                <tr key={c.name}>
                  <td><strong>{c.name}</strong></td>
                  <td><span className={`badge ${c.ok ? 'PUBLISHED' : 'REJECTED'}`}>{c.ok ? tr.opsOk : tr.opsDownOne}</span></td>
                  <td className="muted">{c.ok ? c.detail ?? '' : c.lastError ?? ''}</td>
                  <td>{duration(c.changedAt, null)}</td>
                  <td className="muted">{c.lastCheckedAt ? fmtDate(c.lastCheckedAt, tr.lang) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <h2>{tr.opsIncidents}</h2>
      <div className="card table-wrap">
        {st.incidents.length === 0 ? (
          <p className="muted">{tr.opsNoIncidents}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.opsCheck}</th><th>{tr.opsStarted}</th><th>{tr.opsDuration}</th><th>{tr.opsError}</th></tr></thead>
            <tbody>
              {st.incidents.map((i) => (
                <tr key={i.id}>
                  <td><strong>{i.check}</strong></td>
                  <td>{fmtDate(i.startedAt, tr.lang)}</td>
                  <td>{i.endedAt ? duration(i.startedAt, i.endedAt) : <span className="badge REJECTED">{tr.opsOngoing}</span>}</td>
                  <td className="muted">{i.error}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <h2>{tr.opsBackups}</h2>
      <div className="card">
        <p className="muted">{tr.opsBackupsHint}</p>
        {rt && (
          <p>
            <span className={`badge ${rt.ok ? 'PUBLISHED' : 'REJECTED'}`}>{rt.ok ? tr.opsPassed : tr.opsFailed}</span>{' '}
            {tr.opsRestoreTest}: <code>{rt.backup}</code>
            {rt.ok ? ` · ${rt.tables} ${tr.opsTables}, ${Object.values(rt.rows ?? {}).reduce((a, b) => a + b, 0).toLocaleString()} ${tr.opsRows}, ${rt.durationSec}s` : ` · ${rt.error}`}
          </p>
        )}
        <div className="table-wrap">
          <table>
            <thead><tr><th>{tr.opsBackupFile}</th><th>{tr.opsSize}</th><th>{tr.time}</th></tr></thead>
            <tbody>
              {[...st.backups.daily.slice(0, 7), ...st.backups.weekly.slice(0, 4)].map((b) => (
                <tr key={b.key}>
                  <td><code>{b.key}</code></td>
                  <td>{size(b.size)}</td>
                  <td>{fmtDate(b.at, tr.lang)}</td>
                </tr>
              ))}
              {st.backups.daily.length === 0 && <tr><td colSpan={3} className="muted">{tr.opsNoBackups}</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      <h2 id="errors">{tr.opsErrors}</h2>
      <nav className="row" style={{ marginBottom: 12, flexWrap: 'wrap' }}>
        <Link href={link({ source })} className={`btn ${resolved ? 'secondary' : ''}`}>{tr.opsOpen}</Link>
        <Link href={link({ status: 'resolved', source })} className={`btn ${resolved ? '' : 'secondary'}`}>{tr.opsResolved}</Link>
        <span className="muted" style={{ alignSelf: 'center' }}>·</span>
        <Link href={link({ status: resolved ? 'resolved' : undefined })} className={`btn ${source ? 'secondary' : ''}`}>{tr.opsAllSources}</Link>
        {SOURCES.map((s) => (
          <Link key={s} href={link({ status: resolved ? 'resolved' : undefined, source: s })} className={`btn ${source === s ? '' : 'secondary'}`}>{s}</Link>
        ))}
      </nav>
      <div className="card table-wrap">
        {errors.length === 0 ? (
          <p className="muted">{resolved ? tr.nothingYet : tr.opsNoErrors}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.opsSource}</th><th>{tr.opsError}</th><th>{tr.opsCount}</th><th>{tr.opsLastSeen}</th><th /></tr></thead>
            <tbody>
              {errors.map((e) => (
                <tr key={e.id}>
                  <td><span className="badge">{e.source}</span></td>
                  <td>
                    <details>
                      <summary><strong>{e.message.slice(0, 160)}</strong></summary>
                      {e.path && <div className="muted"><code>{e.path}</code></div>}
                      <div className="muted">{tr.opsFirstSeen}: {fmtDate(e.firstSeen, tr.lang)}{e.lastRelease ? ` · ${tr.opsRelease} ${e.lastRelease.slice(0, 7)}` : ''}</div>
                      {e.stack && <pre style={{ whiteSpace: 'pre-wrap', fontSize: 12, maxHeight: 300, overflow: 'auto' }}>{e.stack}</pre>}
                    </details>
                  </td>
                  <td>{e.count.toLocaleString()}</td>
                  <td>{fmtDate(e.lastSeen, tr.lang)}</td>
                  <td>
                    {!e.resolvedAt && (
                      <ActionForm action={resolveErrorAction} submitLabel={tr.opsMarkFixed} variant="secondary" okText={{ saved: tr.saved }}>
                        <input type="hidden" name="id" value={e.id} />
                      </ActionForm>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}
