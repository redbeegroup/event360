'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { FormState } from '../actions';
import { api, ApiError } from '../lib/api';
import { fromLocalInput } from '../lib/i18n';

const err = (e: unknown): FormState => (e instanceof ApiError ? { error: e.message, problems: e.problems } : { error: (e as Error).message });
const str = (fd: FormData, k: string) => {
  const v = fd.get(k);
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined;
};

async function uploadCover(fd: FormData): Promise<string | undefined> {
  const file = fd.get('cover');
  if (!(file instanceof File) || file.size === 0) return undefined;
  const body = new FormData();
  body.set('file', file, file.name);
  const r = await api<{ key: string }>('/media/images', { method: 'POST', body });
  return r.key;
}

const PRACTICAL = [
  'dressCode', 'dressCodeMy', 'languages', 'languagesMy', 'parking', 'parkingMy', 'accessibility', 'accessibilityMy',
  'whatToBring', 'whatToBringMy', 'terms', 'termsMy', 'refundPolicy', 'refundPolicyMy',
] as const;

function eventPayload(fd: FormData, coverImageKey?: string) {
  const venueName = str(fd, 'venueName');
  const age = str(fd, 'ageMin');
  const lat = str(fd, 'latitude');
  const lng = str(fd, 'longitude');
  return {
    categoryId: str(fd, 'categoryId'),
    title: str(fd, 'title'),
    titleMy: str(fd, 'titleMy'),
    summary: str(fd, 'summary'),
    summaryMy: str(fd, 'summaryMy'),
    description: str(fd, 'description'),
    descriptionMy: str(fd, 'descriptionMy'),
    format: str(fd, 'format'),
    visibility: str(fd, 'visibility'),
    startsAt: str(fd, 'startsAt') ? fromLocalInput(str(fd, 'startsAt')!) : undefined,
    endsAt: str(fd, 'endsAt') ? fromLocalInput(str(fd, 'endsAt')!) : undefined,
    ...(coverImageKey ? { coverImageKey } : {}),
    // Empty practical fields are sent as null-ish (omitted) so they can be cleared by saving blanks.
    ...Object.fromEntries(PRACTICAL.map((k) => [k, str(fd, k) ?? ''])),
    ...(age ? { ageMin: Number(age) } : {}),
    ...(fd.has('transferSettings')
      ? { transfersEnabled: fd.get('transfersEnabled') === 'on', transferCutoffHours: Number(str(fd, 'transferCutoffHours') ?? 2) }
      : {}),
    ...(venueName
      ? {
          venue: {
            name: venueName,
            nameMy: str(fd, 'venueNameMy'),
            address: str(fd, 'address'),
            city: str(fd, 'city') ?? 'Yangon',
            mapUrl: str(fd, 'mapUrl'),
            directions: str(fd, 'directions'),
            directionsMy: str(fd, 'directionsMy'),
            ...(lat && lng ? { latitude: Number(lat), longitude: Number(lng) } : {}),
          },
        }
      : {}),
  };
}

export async function createEventAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  let id: string;
  try {
    const cover = await uploadCover(fd);
    const e = await api<{ id: string }>(`/organizations/${orgId}/events`, { method: 'POST', json: eventPayload(fd, cover) });
    id = e.id;
  } catch (e) {
    return err(e);
  }
  redirect(`/organizer/${orgId}/events/${id}`);
}

export async function updateEventAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    const cover = await uploadCover(fd);
    const r = await api<{ reReviewRequired?: boolean }>(`/organizations/${orgId}/events/${id}`, {
      method: 'PATCH',
      json: eventPayload(fd, cover),
    });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: r.reReviewRequired ? 'rereview' : 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function addTicketTypeAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    await api(`/organizations/${orgId}/events/${id}/ticket-types`, {
      method: 'POST',
      json: {
        name: str(fd, 'name'),
        nameMy: str(fd, 'nameMy'),
        priceMmk: Number(fd.get('priceMmk') ?? 0),
        quota: Number(fd.get('quota') ?? 0),
        maxPerOrder: Number(fd.get('maxPerOrder') ?? 10),
      },
    });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function deleteTicketTypeAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    await api(`/organizations/${orgId}/events/${id}/ticket-types/${fd.get('ticketTypeId')}`, { method: 'DELETE' });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return {};
  } catch (e) {
    return err(e);
  }
}

export async function submitEventAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    await api(`/organizations/${orgId}/events/${id}/submit`, { method: 'POST' });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function cancelEventAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    await api(`/organizations/${orgId}/events/${id}/cancel`, { method: 'POST' });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function inviteTeamAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  try {
    const r = await api<{ inviteUrl: string }>(`/organizations/${orgId}/invitations`, {
      method: 'POST',
      json: { email: fd.get('email'), role: fd.get('role') },
    });
    revalidatePath(`/organizer/${orgId}`);
    return { data: { inviteUrl: r.inviteUrl } };
  } catch (e) {
    return err(e);
  }
}

/** Saves one of the replace-all lists: sessions | performers | media | faqs. Uploads any attached images first. */
export async function saveListAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  const kind = String(fd.get('kind'));
  if (!['sessions', 'performers', 'media', 'faqs'].includes(kind)) return { error: 'bad kind' };
  try {
    const rows = JSON.parse(String(fd.get('items') ?? '[]')) as Record<string, string>[];
    const items: Record<string, unknown>[] = [];
    for (const [i, row] of rows.entries()) {
      const item: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(row)) if (typeof v === 'string' && v.trim() !== '') item[k] = v.trim();
      // Image fields: a newly chosen file replaces the stored key
      for (const field of ['photoKey', 'key']) {
        const file = fd.get(`file_${i}_${field}`);
        if (file instanceof File && file.size > 0) {
          const body = new FormData();
          body.set('file', file, file.name);
          item[field] = (await api<{ key: string }>('/media/images', { method: 'POST', body })).key;
        }
      }
      if (kind === 'sessions') {
        if (!item.title || !item.startsAt || !item.endsAt) continue;
        item.startsAt = fromLocalInput(String(item.startsAt));
        item.endsAt = fromLocalInput(String(item.endsAt));
      }
      if (kind === 'performers' && !item.name) continue;
      if (kind === 'media' && !item.key) continue;
      if (kind === 'faqs' && (!item.question || !item.answer)) continue;
      items.push(item);
    }
    const r = await api<{ reReviewRequired?: boolean }>(`/organizations/${orgId}/events/${id}/${kind}`, { method: 'PUT', json: { items } });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: r.reReviewRequired ? 'rereview' : 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function saveProfileAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  try {
    let logoKey: string | undefined;
    const file = fd.get('logo');
    if (file instanceof File && file.size > 0) {
      const body = new FormData();
      body.set('file', file, file.name);
      logoKey = (await api<{ key: string }>('/media/images', { method: 'POST', body })).key;
    }
    await api(`/organizations/${orgId}/profile`, {
      method: 'PATCH',
      json: {
        description: str(fd, 'description') ?? '',
        descriptionMy: str(fd, 'descriptionMy') ?? '',
        website: str(fd, 'website'),
        facebookUrl: str(fd, 'facebookUrl'),
        contactEmail: str(fd, 'contactEmail') ?? '',
        contactPhone: str(fd, 'contactPhone') ?? '',
        showContact: fd.get('showContact') === 'on',
        ...(logoKey ? { logoKey } : {}),
      },
    });
    revalidatePath(`/organizer/${orgId}/profile`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

// ───────────── Check-in (crew) ─────────────

export interface AttendanceStats {
  registered: number;
  checkedIn: number;
  byTicketType: { id: string; name: string; nameMy: string | null; registered: number; checkedIn: number }[];
  byGate: { gate: string | null; checkedIn: number }[];
  recent: {
    id: string;
    at: string;
    gate: string | null;
    method: 'QR' | 'MANUAL';
    offline: boolean;
    duplicate: boolean;
    undone: boolean;
    by: string | null;
    ticket: { code: string; holderName: string; ticketType: { name: string; nameMy: string | null } };
  }[];
}

/** Polled by the live attendance panel. */
export async function attendanceAction(orgId: string, eventId: string): Promise<AttendanceStats | null> {
  try {
    return await api<AttendanceStats>(`/organizations/${orgId}/events/${eventId}/attendance`);
  } catch {
    return null;
  }
}

export async function createCrewCodeAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    const gate = String(fd.get('gate') ?? '').trim();
    const r = await api<{ code: string; label: string; gate: string | null; expiresAt: string; redeemUri: string }>(
      `/organizations/${orgId}/events/${id}/crew-codes`,
      { method: 'POST', json: { label: String(fd.get('label') ?? '').trim(), ...(gate ? { gate } : {}) } },
    );
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { data: { code: r.code, label: r.label, gate: r.gate ?? '', expiresAt: r.expiresAt, redeemUri: r.redeemUri } };
  } catch (e) {
    return err(e);
  }
}

export async function revokeCrewCodeAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    await api(`/organizations/${orgId}/events/${id}/crew-codes/${fd.get('codeId')}`, { method: 'DELETE' });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'revoked' };
  } catch (e) {
    return err(e);
  }
}

// ───────────── Live & recordings ─────────────

export interface StreamingOverview {
  maxLiveChannels: number;
  pipelineReady: boolean;
  sessions: {
    id: string;
    title: string;
    titleMy: string | null;
    startsAt: string;
    endsAt: string;
    channel: null | {
      id: string;
      status: 'IDLE' | 'LIVE' | 'ENDED';
      recordingEnabled: boolean;
      startedAt: string | null;
      endedAt: string | null;
      viewers: number;
      peakViewers: number;
      obsServer: string;
      obsStreamKey: string;
      srtUrl: string | null;
    };
  }[];
  recordings: {
    id: string;
    title: string;
    titleMy: string | null;
    sessionId: string | null;
    source: 'LIVE' | 'UPLOAD';
    status: 'UPLOADING' | 'PROCESSING' | 'READY' | 'FAILED';
    error: string | null;
    durationSec: number | null;
    published: boolean;
    availableUntil: string | null;
    createdAt: string;
  }[];
}

export type StreamKeys = { obsServer: string; obsStreamKey: string; srtUrl: string | null };
type Res<T> = { ok: true; data: T } | { ok: false; error: string };
const wrap = async <T>(f: () => Promise<T>): Promise<Res<T>> => {
  try {
    return { ok: true, data: await f() };
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }
};
const base = (orgId: string, eventId: string) => `/organizations/${orgId}/events/${eventId}/streaming`;

export async function streamingOverviewAction(orgId: string, eventId: string) {
  return wrap(() => api<StreamingOverview>(base(orgId, eventId)));
}
export async function createChannelAction(orgId: string, eventId: string, sessionId: string) {
  return wrap(() => api<StreamKeys>(`${base(orgId, eventId)}/sessions/${sessionId}/channel`, { method: 'POST' }));
}
export async function rotateKeyAction(orgId: string, eventId: string, channelId: string) {
  return wrap(() => api<StreamKeys>(`${base(orgId, eventId)}/channels/${channelId}/rotate-key`, { method: 'POST' }));
}
export async function setRecordingAction(orgId: string, eventId: string, channelId: string, recordingEnabled: boolean) {
  return wrap(() => api(`${base(orgId, eventId)}/channels/${channelId}`, { method: 'PATCH', json: { recordingEnabled } }));
}
export async function stopChannelAction(orgId: string, eventId: string, channelId: string) {
  return wrap(() => api(`${base(orgId, eventId)}/channels/${channelId}/stop`, { method: 'POST' }));
}
export async function deleteChannelAction(orgId: string, eventId: string, channelId: string) {
  return wrap(() => api(`${base(orgId, eventId)}/channels/${channelId}`, { method: 'DELETE' }));
}
export async function updateRecordingAction(
  orgId: string,
  eventId: string,
  assetId: string,
  data: { published?: boolean; availableUntil?: string | null; title?: string; titleMy?: string },
) {
  return wrap(() => api(`${base(orgId, eventId)}/recordings/${assetId}`, { method: 'PATCH', json: data }));
}
export async function deleteRecordingAction(orgId: string, eventId: string, assetId: string) {
  return wrap(() => api(`${base(orgId, eventId)}/recordings/${assetId}`, { method: 'DELETE' }));
}
export async function createUploadAction(
  orgId: string,
  eventId: string,
  data: { title: string; titleMy?: string; sessionId?: string; fileName: string; size: number; contentType: string },
) {
  return wrap(() => api<{ assetId: string; partSize: number; parts: { partNumber: number; url: string }[] }>(`${base(orgId, eventId)}/uploads`, { method: 'POST', json: data }));
}
export async function completeUploadAction(orgId: string, eventId: string, assetId: string, parts: { partNumber: number; etag: string }[]) {
  return wrap(() => api(`${base(orgId, eventId)}/uploads/${assetId}/complete`, { method: 'POST', json: { parts } }));
}
/** Organizer preview: staff are entitled to watch their own streams. */
export async function previewTokenAction(kind: 'live' | 'vod', id: string) {
  return wrap(() => api<{ url: string; sessionId: string; watermark: string }>(`/watch/${kind}/${id}/token`, { method: 'POST' }));
}

export async function sendAnnouncementAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  const s = (k: string) => String(fd.get(k) ?? '').trim();
  try {
    const r = await api<{ recipients: number }>(`/organizations/${orgId}/events/${id}/announcements`, {
      method: 'POST',
      json: { title: s('title'), body: s('body'), ...(s('titleMy') ? { titleMy: s('titleMy') } : {}), ...(s('bodyMy') ? { bodyMy: s('bodyMy') } : {}) },
    });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'announced', data: { recipients: String(r.recipients) } };
  } catch (e) {
    return err(e);
  }
}

export async function createPromoAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  const s = (k: string) => String(fd.get(k) ?? '').trim();
  try {
    const types = fd.getAll('ticketTypeIds').map(String).filter(Boolean);
    await api(`/organizations/${orgId}/events/${id}/promo-codes`, {
      method: 'POST',
      json: {
        code: s('code'),
        kind: s('kind'),
        value: Number(s('value')),
        ...(s('maxUses') ? { maxUses: Number(s('maxUses')) } : {}),
        ...(s('startsAt') ? { startsAt: fromLocalInput(s('startsAt')) } : {}),
        ...(s('endsAt') ? { endsAt: fromLocalInput(s('endsAt')) } : {}),
        ...(types.length ? { ticketTypeIds: types } : {}),
      },
    });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function togglePromoAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    const promoId = String(fd.get('promoId'));
    if (fd.get('op') === 'delete') await api(`/organizations/${orgId}/events/${id}/promo-codes/${promoId}`, { method: 'DELETE' });
    else await api(`/organizations/${orgId}/events/${id}/promo-codes/${promoId}`, { method: 'PATCH', json: { isActive: fd.get('op') === 'on' } });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

/** Timed prices of one ticket type. The API replaces the whole list, so steps already in effect are sent back as stored. */
export async function setPriceStepsAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  const ttId = String(fd.get('ticketTypeId'));
  try {
    const rows = JSON.parse(String(fd.get('items') ?? '[]')) as Record<string, string>[];
    const ev = await api<{ ticketTypes: { id: string; priceSteps?: { startsAt: string; priceMmk: number }[] }[] }>(`/organizations/${orgId}/events/${id}`);
    const now = Date.now();
    const keep = (ev.ticketTypes.find((x) => x.id === ttId)?.priceSteps ?? []).filter((x) => new Date(x.startsAt).getTime() <= now);
    const steps = keep.map((x) => ({ startsAt: x.startsAt, priceMmk: x.priceMmk }));
    for (const r of rows) {
      const at = String(r.startsAt ?? '').trim();
      const price = String(r.priceMmk ?? '').trim();
      if (!at && !price) continue;
      if (!at || !price || !Number.isInteger(Number(price)) || Number(price) <= 0) return { error: 'badStep' };
      let iso: string;
      try {
        iso = fromLocalInput(at);
      } catch {
        return { error: 'badStep' }; // not a valid date
      }
      const inEffect = steps.some((x) => new Date(x.startsAt).getTime() === new Date(iso).getTime());
      if (!inEffect && new Date(iso).getTime() <= now) return { error: 'badStep' }; // steps can only start in the future
      if (steps.some((x) => new Date(x.startsAt).getTime() === new Date(iso).getTime())) continue; // came into effect while editing
      steps.push({ startsAt: iso, priceMmk: Number(price) });
    }
    await api(`/organizations/${orgId}/events/${id}/ticket-types/${ttId}/price-steps`, { method: 'PUT', json: { steps } });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    if (e instanceof ApiError && e.status === 409) return { error: 'conflict' };
    // The API's English text never reaches the user: a rejected step list reads as the bilingual "bad step" message
    if (e instanceof ApiError && e.status === 400) return { error: 'badStep' };
    return err(e);
  }
}

/** Group discount tiers of an event (replaces all tiers). Percent is entered as a number, sent as basis points. */
export async function setGroupDiscountsAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const id = String(fd.get('eventId'));
  try {
    const rows = JSON.parse(String(fd.get('items') ?? '[]')) as Record<string, string>[];
    const tiers: { minQuantity: number; percentBp: number }[] = [];
    for (const r of rows) {
      const q = String(r.minQuantity ?? '').trim();
      const p = String(r.percent ?? '').trim();
      if (!q && !p) continue;
      const minQuantity = Number(q);
      const percentBp = Math.round(Number(p) * 100);
      if (!q || !p || !Number.isInteger(minQuantity) || minQuantity < 2 || minQuantity > 100 || !(percentBp >= 100 && percentBp <= 9000)) return { error: 'badTier' };
      tiers.push({ minQuantity, percentBp });
    }
    await api(`/organizations/${orgId}/events/${id}/group-discounts`, { method: 'PUT', json: { tiers } });
    revalidatePath(`/organizer/${orgId}/events/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    if (e instanceof ApiError && e.status === 400) return { error: 'badTier' }; // never the API's English text
    return err(e);
  }
}

// ───────────── Seats: map, assignments, guest holds and comps ─────────────

export interface SeatRule {
  sectionKey: string;
  rowLabel?: string;
  ticketTypeId: string;
}
export type SeatRes<T = null> = { ok: true; data: T } | { ok: false; error: string };
const seatWrap = async <T>(orgId: string, eventId: string, f: () => Promise<T>): Promise<SeatRes<T>> => {
  try {
    const data = await f();
    revalidatePath(`/organizer/${orgId}/events/${eventId}/seats`);
    return { ok: true, data };
  } catch (e) {
    // api() redirects to /login on 401; let that through
    if ((e as { digest?: string })?.digest?.startsWith('NEXT_REDIRECT')) throw e;
    return { ok: false, error: e instanceof ApiError ? e.message : (e as Error).message };
  }
};
const seating = (orgId: string, eventId: string) => `/organizations/${orgId}/events/${eventId}/seating`;

/** Event page: pick a published venue map, or go back to "venue address only" when the version id is empty. */
export async function pickSeatMapAction(_: FormState, fd: FormData): Promise<FormState> {
  const orgId = String(fd.get('orgId'));
  const eventId = String(fd.get('eventId'));
  const versionId = str(fd, 'seatMapVersionId');
  try {
    const r = versionId
      ? await api<{ reReviewRequired: boolean }>(`${seating(orgId, eventId)}/map`, { method: 'PUT', json: { seatMapVersionId: versionId } })
      : await api<{ reReviewRequired: boolean }>(`${seating(orgId, eventId)}/map`, { method: 'DELETE' });
    revalidatePath(`/organizer/${orgId}/events/${eventId}`);
    return { ok: r.reReviewRequired ? 'rereview' : versionId ? 'mapSaved' : 'mapCleared' };
  } catch (e) {
    return err(e);
  }
}

/** Sends the whole rule set; the API replaces all of the event's assignments. */
export async function saveAssignmentsAction(orgId: string, eventId: string, rules: SeatRule[]) {
  return seatWrap(orgId, eventId, () => api(`${seating(orgId, eventId)}/assignments`, { method: 'PUT', json: { rules } }).then(() => null));
}

export async function holdSeatsAction(orgId: string, eventId: string, seats: string[], label: string) {
  return seatWrap(orgId, eventId, () => api<{ held: number }>(`${seating(orgId, eventId)}/hold`, { method: 'POST', json: { seats, label } }));
}

export async function releaseSeatsAction(orgId: string, eventId: string, seats: string[]) {
  return seatWrap(orgId, eventId, () => api<{ released: number }>(`${seating(orgId, eventId)}/release`, { method: 'POST', json: { seats } }));
}

export async function issueCompsAction(orgId: string, eventId: string, body: { seats: string[]; guestName: string; phone: string; label?: string }) {
  return seatWrap(orgId, eventId, () => api<{ tickets: unknown[] }>(`${seating(orgId, eventId)}/comps`, { method: 'POST', json: body }));
}

export async function revokeCompAction(orgId: string, eventId: string, ticketId: string) {
  return seatWrap(orgId, eventId, () => api(`${seating(orgId, eventId)}/comps/${ticketId}/revoke`, { method: 'POST' }).then(() => null));
}
