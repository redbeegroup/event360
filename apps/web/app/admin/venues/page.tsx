import Link from 'next/link';
import { ActionForm } from '../../components/ActionForm';
import { PageHeader } from '../../components/PageHeader';
import { api } from '../../lib/api';
import { t } from '../../lib/i18n';
import { createSeatMapAction } from '../actions';

interface SeatMapRow {
  id: string;
  venueName: string;
  venueNameMy: string | null;
  city: string;
  isActive: boolean;
  latestVersion: number | null;
  latestPublishedVersion: number | null;
  hasDraft: boolean;
}

export default async function VenuesPage() {
  const tr = await t();
  const maps = await api<SeatMapRow[]>('/admin/seat-maps');
  return (
    <>
      <PageHeader title={tr.smVenues} />
      <div className="table-card">
        {maps.length === 0 ? (
          <p className="muted">{tr.smNoVenues}</p>
        ) : (
          <table>
            <thead>
              <tr><th>{tr.name}</th><th>{tr.city}</th><th>{tr.smVersions}</th><th>{tr.status}</th></tr>
            </thead>
            <tbody>
              {maps.map((m) => (
                <tr key={m.id}>
                  <td><Link href={`/admin/venues/${m.id}`}>{tr.lang === 'my' && m.venueNameMy ? m.venueNameMy : m.venueName}</Link></td>
                  <td>{m.city}</td>
                  <td>{m.latestPublishedVersion ? `v${m.latestPublishedVersion}` : '—'}</td>
                  <td>
                    {m.latestPublishedVersion && <span className="badge PUBLISHED">{tr.smPublishedBadge}</span>}{' '}
                    {m.hasDraft && <span className="badge PENDING">{tr.smDraft}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <h2>{tr.smNewVenue}</h2>
      <div className="card">
        <ActionForm action={createSeatMapAction} submitLabel={tr.create} variant="gold">
          <div className="grid">
            <div className="field"><label>{tr.smVenueName}</label><input name="venueName" required maxLength={200} /></div>
            <div className="field"><label>{tr.smVenueNameMy}</label><input name="venueNameMy" maxLength={200} /></div>
            <div className="field"><label>{tr.city}</label><input name="city" required maxLength={100} /></div>
            <div className="field"><label>{tr.address}</label><input name="address" maxLength={300} /></div>
            <div className="field"><label>{tr.smLatitude}</label><input name="latitude" type="number" step="any" min={-90} max={90} /></div>
            <div className="field"><label>{tr.smLongitude}</label><input name="longitude" type="number" step="any" min={-180} max={180} /></div>
            <div className="field"><label>{tr.smMapUrl}</label><input name="mapUrl" maxLength={500} /></div>
          </div>
        </ActionForm>
      </div>
    </>
  );
}
