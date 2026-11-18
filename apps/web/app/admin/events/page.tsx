import { ActionForm } from '../../components/ActionForm';
import { api } from '../../lib/api';
import { fmtDate, fmtMmk, pick, t } from '../../lib/i18n';
import type { EventDto } from '../../lib/types';
import { approveEventAction, rejectEventAction } from '../actions';

export default async function ModerationPage() {
  const tr = await t();
  const events = await api<EventDto[]>('/admin/events?status=SUBMITTED');
  return (
    <>
      <h1>{tr.moderation}</h1>
      {events.length === 0 && <p className="muted">{tr.noEventsToReview}</p>}
      {events.map((e) => (
        <div className="card" key={e.id}>
          {e.coverImageUrl && <img className="cover" src={e.coverImageUrl} alt="" />}
          <h2 style={{ marginTop: 8 }}>{pick(tr.lang, e.title, e.titleMy)}</h2>
          <p className="muted">
            {e.organization.name} · {pick(tr.lang, e.category.nameEn, e.category.nameMy)} · {tr.formats[e.format]} ·{' '}
            {fmtDate(e.startsAt, tr.lang)}
            {e.venue && <> · {e.venue.name}, {e.venue.city}</>}
          </p>
          {e.titleMy && tr.lang === 'en' && <p>{e.titleMy}</p>}
          <p>{pick(tr.lang, e.summary, e.summaryMy)}</p>
          {e.description && <details><summary>{tr.descriptionEn}</summary><p style={{ whiteSpace: 'pre-wrap' }}>{e.description}</p></details>}
          {e.descriptionMy && <details><summary>{tr.descriptionMy}</summary><p style={{ whiteSpace: 'pre-wrap' }}>{e.descriptionMy}</p></details>}
          <p>
            {e.ticketTypes.map((tt) => (
              <span key={tt.id} className="badge" style={{ marginRight: 6 }}>
                {pick(tr.lang, tt.name, tt.nameMy)} · {tt.priceMmk === 0 ? tr.free : fmtMmk(tt.priceMmk, tr.lang)} · {tt.quota}
              </span>
            ))}
          </p>
          <div className="row">
            <ActionForm action={approveEventAction} submitLabel={tr.approve}>
              <input type="hidden" name="id" value={e.id} />
            </ActionForm>
            <ActionForm action={rejectEventAction} submitLabel={tr.reject} variant="danger" className="row">
              <input type="hidden" name="id" value={e.id} />
              <input name="reason" placeholder={tr.reason} required minLength={3} style={{ width: 260 }} />
            </ActionForm>
          </div>
        </div>
      ))}
    </>
  );
}
