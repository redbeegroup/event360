import Link from 'next/link';
import { ActionForm } from '../../../../components/ActionForm';
import { api } from '../../../../lib/api';
import { fmtDate, fmtMmk, pick, t } from '../../../../lib/i18n';
import type { CategoryDto, EventDto } from '../../../../lib/types';
import {
  addTicketTypeAction,
  cancelEventAction,
  deleteTicketTypeAction,
  submitEventAction,
  updateEventAction,
} from '../../../actions';
import { EventFields } from '../../../EventFields';

export const dynamic = 'force-dynamic';

interface Attendee {
  id: string;
  status: string;
  createdAt: string;
  ticketType: { name: string };
  holder: { displayName: string | null; phone: string | null };
}

export default async function EventEditPage({ params }: { params: Promise<{ orgId: string; id: string }> }) {
  const { orgId, id } = await params;
  const [tr, e, categories, attendees] = await Promise.all([
    t(),
    api<EventDto>(`/organizations/${orgId}/events/${id}`),
    api<CategoryDto[]>('/categories', { auth: false }),
    api<Attendee[]>(`/organizations/${orgId}/events/${id}/attendees`),
  ]);
  const hidden = (
    <>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="eventId" value={id} />
    </>
  );
  const closed = ['CANCELLED', 'COMPLETED'].includes(e.status);
  const okText = { saved: tr.saved, rereview: tr.reReview };
  return (
    <>
      <p><Link href={`/organizer/${orgId}`}>← {tr.events}</Link></p>
      <h1>{pick(tr.lang, e.title, e.titleMy)} <span className={`badge ${e.status}`}>{tr.statuses[e.status]}</span></h1>
      {e.status === 'REJECTED' && e.rejectionReason && <div className="error">{tr.rejectionReason}: {e.rejectionReason}</div>}

      {['DRAFT', 'REJECTED'].includes(e.status) && (
        <div className="card">
          <p className="muted">{tr.submitHint}</p>
          <ActionForm action={submitEventAction} submitLabel={tr.submit} okText={okText}>{hidden}</ActionForm>
        </div>
      )}

      <h2>{tr.ticketTypes}</h2>
      <div className="card table-wrap">
        <table>
          <thead>
            <tr><th>{tr.name}</th><th>{tr.price}</th><th>{tr.sold}</th><th>{tr.quota}</th><th>{tr.maxPerOrder}</th><th /></tr>
          </thead>
          <tbody>
            {e.ticketTypes.map((tt) => (
              <tr key={tt.id}>
                <td>{pick(tr.lang, tt.name, tt.nameMy)}</td>
                <td>{tt.priceMmk === 0 ? tr.free : fmtMmk(tt.priceMmk, tr.lang)}</td>
                <td>{tt.sold ?? 0}</td>
                <td>{tt.quota}</td>
                <td>{tt.maxPerOrder}</td>
                <td>
                  {!closed && (tt.sold ?? 0) === 0 && (
                    <ActionForm action={deleteTicketTypeAction} submitLabel={tr.delete} variant="secondary">
                      {hidden}
                      <input type="hidden" name="ticketTypeId" value={tt.id} />
                    </ActionForm>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!closed && (
          <>
            <h2>{tr.addTicketType}</h2>
            <p className="muted">{tr.paidLater}</p>
            <ActionForm action={addTicketTypeAction} submitLabel={tr.addTicketType} okText={okText}>
              {hidden}
              <div className="grid">
                <div className="field"><label>{tr.name} (EN)</label><input name="name" required /></div>
                <div className="field"><label>{tr.name} (MY)</label><input name="nameMy" lang="my" /></div>
                <div className="field"><label>{tr.price}</label><input name="priceMmk" type="number" min={0} step={100} defaultValue={0} required /></div>
                <div className="field"><label>{tr.quota}</label><input name="quota" type="number" min={1} defaultValue={100} required /></div>
                <div className="field"><label>{tr.maxPerOrder}</label><input name="maxPerOrder" type="number" min={1} max={50} defaultValue={4} required /></div>
              </div>
            </ActionForm>
          </>
        )}
      </div>

      {!closed && (
        <>
          <h2>{tr.save}</h2>
          <div className="card">
            <ActionForm action={updateEventAction} submitLabel={tr.save} okText={okText}>
              {hidden}
              <EventFields tr={tr} categories={categories} event={e} />
            </ActionForm>
          </div>
        </>
      )}

      <h2>{tr.attendees} ({attendees.length})</h2>
      <div className="card table-wrap">
        {attendees.length === 0 ? (
          <p className="muted">{tr.noAttendees}</p>
        ) : (
          <table>
            <thead><tr><th>{tr.name}</th><th>{tr.phone}</th><th>{tr.ticketTypes}</th><th>{tr.registeredAt}</th><th>{tr.status}</th></tr></thead>
            <tbody>
              {attendees.map((a) => (
                <tr key={a.id}>
                  <td>{a.holder.displayName ?? '—'}</td>
                  <td>{a.holder.phone ?? '—'}</td>
                  <td>{a.ticketType.name}</td>
                  <td>{fmtDate(a.createdAt, tr.lang)}</td>
                  <td>{a.status}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {!closed && (
        <div className="card">
          <ActionForm action={cancelEventAction} submitLabel={tr.cancelEvent} variant="danger" confirm={tr.confirmCancel} okText={okText}>{hidden}</ActionForm>
        </div>
      )}
    </>
  );
}
