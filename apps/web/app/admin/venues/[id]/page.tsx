import Link from 'next/link';
import { ActionForm } from '../../../components/ActionForm';
import { SeatMapEditor } from '../../../components/SeatMapEditor';
import { api } from '../../../lib/api';
import { fmtDate, t } from '../../../lib/i18n';
import type { Layout } from '../../../lib/seat-layout';
import { importSeatLayoutAction, publishSeatMapAction, saveSeatDraftAction, updateSeatMapAction } from '../../actions';

interface SeatMapDetail {
  id: string;
  venueName: string;
  venueNameMy: string | null;
  city: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  mapUrl: string | null;
  isActive: boolean;
  versions: { id: string; version: number; seatCount: number; publishedAt: string | null; createdAt: string }[];
}

const EMPTY: Layout = { width: 1400, height: 1000, stage: { x: 420, y: 40, w: 560, h: 60, label: 'Stage' }, sections: [] };

export default async function VenuePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const tr = await t();
  const m = await api<SeatMapDetail>(`/admin/seat-maps/${id}`);
  // Start from the open draft, else the newest published version (saving then creates the next draft).
  const start = m.versions.find((v) => !v.publishedAt) ?? m.versions[0];
  const initial = start ? (await api<{ layout: Layout }>(`/admin/seat-maps/${id}/versions/${start.version}`)).layout : EMPTY;
  const labels = Object.fromEntries(Object.entries(tr).filter(([k, v]) => k.startsWith('sm') && typeof v === 'string')) as Record<string, string>;
  const save = saveSeatDraftAction.bind(null, id);
  const imp = importSeatLayoutAction.bind(null, id);
  const publish = publishSeatMapAction.bind(null, id);

  return (
    <>
      <p><Link href="/admin/venues">← {tr.smBack}</Link></p>
      <h1>{m.venueName}</h1>

      <details className="card">
        <summary>{tr.smEditVenue}</summary>
        <ActionForm action={updateSeatMapAction} submitLabel={tr.save}>
          <input type="hidden" name="id" value={m.id} />
          <div className="grid">
            <div className="field"><label>{tr.smVenueName}</label><input name="venueName" required defaultValue={m.venueName} /></div>
            <div className="field"><label>{tr.smVenueNameMy}</label><input name="venueNameMy" defaultValue={m.venueNameMy ?? ''} /></div>
            <div className="field"><label>{tr.city}</label><input name="city" required defaultValue={m.city} /></div>
            <div className="field"><label>{tr.address}</label><input name="address" defaultValue={m.address ?? ''} /></div>
            <div className="field"><label>{tr.smLatitude}</label><input name="latitude" type="number" step="any" defaultValue={m.latitude ?? ''} /></div>
            <div className="field"><label>{tr.smLongitude}</label><input name="longitude" type="number" step="any" defaultValue={m.longitude ?? ''} /></div>
            <div className="field"><label>{tr.smMapUrl}</label><input name="mapUrl" defaultValue={m.mapUrl ?? ''} /></div>
          </div>
          <div className="field"><label><input type="checkbox" name="isActive" defaultChecked={m.isActive} /> {tr.smActive}</label></div>
        </ActionForm>
      </details>

      <h2>{tr.smVersions}</h2>
      <div className="card table-wrap">
        <table>
          <thead><tr><th>{tr.smVersion}</th><th>{tr.status}</th><th>{tr.smSeats}</th></tr></thead>
          <tbody>
            {m.versions.map((v) => (
              <tr key={v.id}>
                <td>v{v.version}</td>
                <td>
                  {v.publishedAt ? <span className="badge PUBLISHED">{tr.smPublishedBadge} · {fmtDate(v.publishedAt, tr.lang)}</span> : <span className="badge PENDING">{tr.smDraft}</span>}
                </td>
                <td>{v.seatCount.toLocaleString('en')}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>{tr.smEditor}</h2>
      <SeatMapEditor initial={initial} onSave={save} onImport={imp} onPublish={publish} labels={labels} lang={tr.lang} />
    </>
  );
}
