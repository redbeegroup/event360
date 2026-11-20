import Link from 'next/link';
import { ActionForm } from '../../../../components/ActionForm';
import { api } from '../../../../lib/api';
import { ListEditor } from '../../../../components/ListEditor';
import { AttendanceLive, CrewCodeForm, type CrewLabels } from '../../../../components/CrewCheckin';
import { LiveStudio } from '../../../../components/LiveStudio';
import { fmtDate, fmtMmk, pick, t, toLocalInput } from '../../../../lib/i18n';
import type { CategoryDto, EventDto } from '../../../../lib/types';
import {
  attendanceAction,
  createCrewCodeAction,
  revokeCrewCodeAction,
  type AttendanceStats,
  type StreamingOverview,
  addTicketTypeAction,
  cancelEventAction,
  deleteTicketTypeAction,
  saveListAction,
  createPromoAction,
  togglePromoAction,
  sendAnnouncementAction,
  submitEventAction,
  updateEventAction,
} from '../../../actions';
import { EventFields } from '../../../EventFields';

export const dynamic = 'force-dynamic';

interface CrewCode {
  id: string;
  label: string;
  gate: string | null;
  expiresAt: string;
  devices: number;
  active: boolean;
}

interface Attendee {
  id: string;
  status: string;
  createdAt: string;
  ticketType: { name: string };
  holder: { displayName: string | null; phone: string | null };
}

interface Promo {
  id: string;
  code: string;
  kind: 'PERCENT' | 'FIXED';
  value: number;
  maxUses: number | null;
  used: number;
  startsAt: string | null;
  endsAt: string | null;
  ticketTypeIds: string[];
  isActive: boolean;
  orders: number;
  discountGivenMmk: number;
}

interface Announcements {
  items: { id: string; title: string; titleMy: string | null; body: string; recipients: number; createdAt: string }[];
  ticketHolders: number;
  remainingToday: number;
}

interface Sales {
  ticketTypes: { id: string; name: string; priceMmk: number; quota: number; sold: number; held: number; revenueMmk: number }[];
  paidOrders: number;
  grossMmk: number;
  commissionMmk: number;
  netMmk: number;
  refundedOrders: number;
  refundedMmk: number;
  recent: { id: string; status: string; createdAt: string; totalMmk: number; quantity: number; buyer: string | null }[];
}

export default async function EventEditPage({ params }: { params: Promise<{ orgId: string; id: string }> }) {
  const { orgId, id } = await params;
  const [tr, e, categories, attendees, attendance, codes, streaming, sales, ann, promos] = await Promise.all([
    t(),
    api<EventDto>(`/organizations/${orgId}/events/${id}`),
    api<CategoryDto[]>('/categories', { auth: false }),
    api<Attendee[]>(`/organizations/${orgId}/events/${id}/attendees`),
    api<AttendanceStats>(`/organizations/${orgId}/events/${id}/attendance`).catch(() => null),
    api<CrewCode[]>(`/organizations/${orgId}/events/${id}/crew-codes`).catch(() => null), // null = not an editor
    api<StreamingOverview>(`/organizations/${orgId}/events/${id}/streaming`).catch(() => null),
    api<Sales>(`/organizations/${orgId}/events/${id}/sales`).catch(() => null),
    api<Announcements>(`/organizations/${orgId}/events/${id}/announcements`).catch(() => null),
    api<Promo[]>(`/organizations/${orgId}/events/${id}/promo-codes`).catch(() => null),
  ]);
  const paidTypes = e.ticketTypes.filter((tt) => tt.priceMmk > 0);
  const hasPaid = e.ticketTypes.some((tt) => tt.priceMmk > 0);
  const crewAppUrl = process.env.CREW_APP_URL ?? '';
  const crewLabels: CrewLabels = {
    label: tr.crewCodeLabel, labelHint: tr.crewCodeLabelHint, gate: tr.crewGate, create: tr.crewCreate,
    codeTitle: tr.crewCodeTitle, codeHint: tr.crewCodeHint, openCrewApp: tr.openCrewApp, copy: tr.copy, expires: tr.expires,
    registered: tr.registeredLabel, checkedIn: tr.checkedIn, byGate: tr.byGate, noGate: tr.noGate, recent: tr.recentScans,
    noScans: tr.noScans, duplicate: tr.duplicateScan, undone: tr.undone, manual: tr.manualCheckin, offline: tr.offlineScan, updated: tr.updatedAt,
  };
  const loadAttendance = attendanceAction.bind(null, orgId, id);
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
            <p className="muted">{tr.paidFeeNote}</p>
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

      {ann && e.publishedAt && !['CANCELLED', 'COMPLETED'].includes(e.status) && (
        <>
          <h2>{tr.announceTitle}</h2>
          <div className="card">
            <p className="muted">{tr.announceHint}</p>
            <p>{tr.announceRecipients}: <strong>{ann.ticketHolders}</strong> · {tr.announceRemaining}: <strong>{ann.remainingToday}</strong></p>
            {ann.remainingToday > 0 && ann.ticketHolders > 0 && codes !== null && (
              <ActionForm action={sendAnnouncementAction} submitLabel={tr.announceSend} confirm={tr.announceConfirm} okText={{ announced: tr.announceSent }}>
                <input type="hidden" name="orgId" value={orgId} />
                <input type="hidden" name="eventId" value={id} />
                <div className="grid">
                  <div className="field"><label>{tr.announceHeading} ({tr.en})</label><input name="title" required minLength={3} maxLength={80} /></div>
                  <div className="field"><label>{tr.announceHeading} ({tr.myLabel})</label><input name="titleMy" lang="my" maxLength={80} /></div>
                </div>
                <div className="field"><label>{tr.announceBody} ({tr.en})</label><textarea name="body" required minLength={3} maxLength={500} rows={3} /></div>
                <div className="field"><label>{tr.announceBody} ({tr.myLabel})</label><textarea name="bodyMy" lang="my" maxLength={500} rows={3} /></div>
              </ActionForm>
            )}
            {ann.items.length > 0 && (
              <table style={{ marginTop: 12 }}>
                <thead><tr><th>{tr.sentAt}</th><th>{tr.announceHeading}</th><th>{tr.announceRecipients}</th></tr></thead>
                <tbody>
                  {ann.items.map((a) => (
                    <tr key={a.id}>
                      <td>{fmtDate(a.createdAt, tr.lang)}</td>
                      <td><strong>{pick(tr.lang, a.title, a.titleMy)}</strong><div className="muted" style={{ fontSize: 13 }}>{a.body}</div></td>
                      <td>{a.recipients}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      {promos && hasPaid && (
        <>
          <h2>{tr.promoTitle}</h2>
          <div className="card table-wrap">
            <p className="muted">{tr.promoHint}</p>
            {promos.length > 0 && (
              <table>
                <thead><tr><th>{tr.promoCode}</th><th>{tr.promoKind}</th><th>{tr.promoUsed}</th><th>{tr.promoDiscountGiven}</th><th>{tr.promoEnds}</th><th /></tr></thead>
                <tbody>
                  {promos.map((p) => (
                    <tr key={p.id} style={{ opacity: p.isActive ? 1 : 0.55 }}>
                      <td><code>{p.code}</code> {!p.isActive && <span className="badge DRAFT">{tr.promoInactive}</span>}</td>
                      <td>
                        {p.kind === 'PERCENT' ? `${p.value}%` : fmtMmk(p.value, tr.lang)}
                        {p.ticketTypeIds.length > 0 && (
                          <div className="muted" style={{ fontSize: 12 }}>{e.ticketTypes.filter((tt) => p.ticketTypeIds.includes(tt.id)).map((tt) => tt.name).join(', ')}</div>
                        )}
                      </td>
                      <td>{p.used}{p.maxUses ? ` / ${p.maxUses}` : ''}</td>
                      <td>{fmtMmk(p.discountGivenMmk, tr.lang)}</td>
                      <td>{p.endsAt ? fmtDate(p.endsAt, tr.lang) : '—'}</td>
                      <td style={{ minWidth: 200 }}>
                        {codes !== null && (
                          <div className="row" style={{ gap: 6 }}>
                            <ActionForm action={togglePromoAction} submitLabel={p.isActive ? tr.promoOff : tr.promoOn} variant="secondary">
                              <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="eventId" value={id} />
                              <input type="hidden" name="promoId" value={p.id} /><input type="hidden" name="op" value={p.isActive ? 'off' : 'on'} />
                            </ActionForm>
                            <ActionForm action={togglePromoAction} submitLabel={tr.promoDelete} variant="secondary" confirm={tr.promoDeleteConfirm}>
                              <input type="hidden" name="orgId" value={orgId} /><input type="hidden" name="eventId" value={id} />
                              <input type="hidden" name="promoId" value={p.id} /><input type="hidden" name="op" value="delete" />
                            </ActionForm>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            {codes !== null && !closed && (
              <ActionForm action={createPromoAction} submitLabel={tr.promoCreate} okText={okText}>
                <input type="hidden" name="orgId" value={orgId} />
                <input type="hidden" name="eventId" value={id} />
                <div className="grid">
                  <div className="field"><label>{tr.promoCode}</label><input name="code" required pattern="[A-Za-z0-9_\-]{3,24}" placeholder="EARLYBIRD" style={{ textTransform: 'uppercase' }} /></div>
                  <div className="field">
                    <label>{tr.promoKind}</label>
                    <select name="kind" defaultValue="PERCENT"><option value="PERCENT">{tr.percentOff}</option><option value="FIXED">{tr.fixedOff}</option></select>
                  </div>
                  <div className="field"><label>{tr.promoValue}</label><input name="value" type="number" min={1} required placeholder="10" /></div>
                  <div className="field"><label>{tr.promoMaxUses}</label><input name="maxUses" type="number" min={1} /></div>
                  <div className="field"><label>{tr.promoStarts}</label><input name="startsAt" type="datetime-local" /></div>
                  <div className="field"><label>{tr.promoEnds}</label><input name="endsAt" type="datetime-local" /></div>
                </div>
                {paidTypes.length > 1 && (
                  <div className="field">
                    <label>{tr.promoTypes}</label>
                    <div className="row" style={{ gap: 12 }}>
                      {paidTypes.map((tt) => (
                        <label key={tt.id} className="check"><input type="checkbox" name="ticketTypeIds" value={tt.id} /> {pick(tr.lang, tt.name, tt.nameMy)}</label>
                      ))}
                    </div>
                  </div>
                )}
              </ActionForm>
            )}
          </div>
        </>
      )}

      {sales && hasPaid && (
        <>
          <h2>{tr.salesTitle}</h2>
          <div className="card table-wrap">
            <div className="grid">
              <div><div className="muted">{tr.paidOrders}</div><strong>{sales.paidOrders}</strong></div>
              <div><div className="muted">{tr.gross}</div><strong>{fmtMmk(sales.grossMmk, tr.lang)}</strong></div>
              <div><div className="muted">{tr.commission}</div><strong>{fmtMmk(sales.commissionMmk, tr.lang)}</strong></div>
              <div><div className="muted">{tr.net}</div><strong>{fmtMmk(sales.netMmk, tr.lang)}</strong></div>
              <div><div className="muted">{tr.refunded}</div><strong>{sales.refundedOrders} · {fmtMmk(sales.refundedMmk, tr.lang)}</strong></div>
            </div>
            <table style={{ marginTop: 12 }}>
              <thead><tr><th>{tr.name}</th><th>{tr.price}</th><th>{tr.sold}</th><th>{tr.held}</th><th>{tr.quota}</th><th>{tr.revenue}</th></tr></thead>
              <tbody>
                {sales.ticketTypes.filter((x) => x.priceMmk > 0).map((x) => (
                  <tr key={x.id}><td>{x.name}</td><td>{fmtMmk(x.priceMmk, tr.lang)}</td><td>{x.sold}</td><td>{x.held}</td><td>{x.quota}</td><td>{fmtMmk(x.revenueMmk, tr.lang)}</td></tr>
                ))}
              </tbody>
            </table>
            <h3>{tr.recentOrders}</h3>
            {sales.recent.length === 0 ? (
              <p className="muted">{tr.nothingYet}</p>
            ) : (
              <table>
                <thead><tr><th>{tr.time}</th><th>{tr.buyer}</th><th>{tr.qty}</th><th>{tr.total}</th><th>{tr.status}</th></tr></thead>
                <tbody>
                  {sales.recent.map((o) => (
                    <tr key={o.id}>
                      <td>{fmtDate(o.createdAt, tr.lang)}</td>
                      <td>{o.buyer ?? ''}</td>
                      <td>{o.quantity}</td>
                      <td>{fmtMmk(o.totalMmk, tr.lang)}</td>
                      <td><span className={`badge ${o.status === 'PAID' ? 'PUBLISHED' : o.status === 'REFUNDED' ? 'DRAFT' : 'SUBMITTED'}`}>{o.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      {!closed && (
        <>
          {(
            [
              {
                kind: 'sessions',
                title: tr.schedule,
                fields: [
                  { name: 'title', label: `${tr.sessionTitle} (${tr.en})`, required: true },
                  { name: 'titleMy', label: `${tr.sessionTitle} (${tr.myLabel})`, lang: 'my' as const },
                  { name: 'startsAt', label: tr.startsAt, type: 'datetime' as const, required: true },
                  { name: 'endsAt', label: tr.endsAt, type: 'datetime' as const, required: true },
                  { name: 'location', label: tr.location },
                ],
                initial: (e.sessions ?? []).map((x) => ({
                  id: x.id,
                  title: x.title, titleMy: x.titleMy ?? '', location: x.location ?? '',
                  startsAt: toLocalInput(x.startsAt), endsAt: toLocalInput(x.endsAt),
                })),
              },
              {
                kind: 'performers',
                title: tr.lineup,
                fields: [
                  { name: 'name', label: `${tr.name} (${tr.en})`, required: true },
                  { name: 'nameMy', label: `${tr.name} (${tr.myLabel})`, lang: 'my' as const },
                  { name: 'role', label: `${tr.performerRole} (${tr.en})` },
                  { name: 'roleMy', label: `${tr.performerRole} (${tr.myLabel})`, lang: 'my' as const },
                  { name: 'photoKey', label: tr.photo, type: 'image' as const },
                  { name: 'bio', label: `${tr.bio} (${tr.en})`, type: 'textarea' as const },
                  { name: 'bioMy', label: `${tr.bio} (${tr.myLabel})`, type: 'textarea' as const, lang: 'my' as const },
                ],
                initial: (e.performers ?? []).map((x) => ({
                  name: x.name, nameMy: x.nameMy ?? '', role: x.role ?? '', roleMy: x.roleMy ?? '',
                  bio: x.bio ?? '', bioMy: x.bioMy ?? '', photoKey: x.photoKey ?? '', _url: x.photoUrl ?? '',
                })),
              },
              {
                kind: 'media',
                title: tr.gallery,
                fields: [
                  { name: 'key', label: tr.image, type: 'image' as const },
                  { name: 'caption', label: `${tr.caption} (${tr.en})` },
                  { name: 'captionMy', label: `${tr.caption} (${tr.myLabel})`, lang: 'my' as const },
                ],
                initial: (e.media ?? []).map((x) => ({ key: x.key, caption: x.caption ?? '', captionMy: x.captionMy ?? '', _url: x.url })),
              },
              {
                kind: 'faqs',
                title: tr.faq,
                fields: [
                  { name: 'question', label: `${tr.question} (${tr.en})`, required: true },
                  { name: 'questionMy', label: `${tr.question} (${tr.myLabel})`, lang: 'my' as const },
                  { name: 'answer', label: `${tr.answer} (${tr.en})`, type: 'textarea' as const },
                  { name: 'answerMy', label: `${tr.answer} (${tr.myLabel})`, type: 'textarea' as const, lang: 'my' as const },
                ],
                initial: (e.faqs ?? []).map((x) => ({ question: x.question, questionMy: x.questionMy ?? '', answer: x.answer, answerMy: x.answerMy ?? '' })),
              },
            ] as const
          ).map((sec) => (
            <section key={sec.kind}>
              <h2>{sec.title}</h2>
              <div className="card">
                <ActionForm action={saveListAction} submitLabel={tr.saveList} okText={okText}>
                  {hidden}
                  <input type="hidden" name="kind" value={sec.kind} />
                  <ListEditor
                    fields={[...sec.fields]}
                    initial={sec.initial.map((r) => ({ ...r }))}
                    labels={{ add: tr.add, remove: tr.remove, up: tr.moveUp, empty: tr.nothingYet }}
                  />
                </ActionForm>
              </div>
            </section>
          ))}

          <h2>{tr.save}</h2>
          <div className="card">
            <ActionForm action={updateEventAction} submitLabel={tr.save} okText={okText}>
              {hidden}
              <EventFields tr={tr} categories={categories} event={e} />
            </ActionForm>
          </div>
        </>
      )}

      {e.status === 'PUBLISHED' && (
        <section>
          <h2>{tr.checkin}</h2>
          <div className="card">
            <p className="muted">{tr.checkinHint}</p>
            {crewAppUrl && (
              <p>{tr.crewAppHint} <a href={crewAppUrl} target="_blank" rel="noreferrer">{crewAppUrl}</a></p>
            )}
            <h3>{tr.liveAttendance}</h3>
            <AttendanceLive initial={attendance} load={loadAttendance} labels={crewLabels} lang={tr.lang} />
          </div>
          {codes && (
            <>
              <h3>{tr.crewCodes}</h3>
              <div className="card">
                {codes.length === 0 ? (
                  <p className="muted">{tr.noCodes}</p>
                ) : (
                  <div className="table-wrap">
                    <table>
                      <thead><tr><th>{tr.crewCodeLabel}</th><th>{tr.crewGate}</th><th>{tr.devices}</th><th>{tr.expires}</th><th>{tr.status}</th><th /></tr></thead>
                      <tbody>
                        {codes.map((c) => (
                          <tr key={c.id}>
                            <td>{c.label}</td>
                            <td>{c.gate ?? '—'}</td>
                            <td>{c.devices}</td>
                            <td>{fmtDate(c.expiresAt, tr.lang)}</td>
                            <td><span className={`badge ${c.active ? 'PUBLISHED' : 'CANCELLED'}`}>{c.active ? tr.active : tr.inactive}</span></td>
                            <td>
                              {c.active && (
                                <ActionForm action={revokeCrewCodeAction} submitLabel={tr.revoke} variant="danger" confirm={tr.revokeConfirm} okText={{ revoked: tr.saved }}>
                                  {hidden}
                                  <input type="hidden" name="codeId" value={c.id} />
                                </ActionForm>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
                <CrewCodeForm action={createCrewCodeAction} hidden={{ orgId, eventId: id }} labels={crewLabels} crewAppUrl={crewAppUrl} lang={tr.lang} />
              </div>
            </>
          )}
        </section>
      )}

      {streaming && !closed && codes && (
        <section>
          <h2>{tr.liveTitle}</h2>
          <LiveStudio orgId={orgId} eventId={id} initial={streaming} labels={tr.live} lang={tr.lang} />
        </section>
      )}

      <h2>{tr.attendees} ({attendees.length})</h2>
      <p className="row" style={{ gap: 8 }}>
        <Link className="btn secondary" href={`/organizer/${orgId}/events/${id}/dashboard`}>{tr.dashboard}</Link>
        {attendees.length > 0 && <a className="btn secondary" href={`/organizer/${orgId}/events/${id}/attendees.csv`}>{tr.downloadAttendees}</a>}
      </p>
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
