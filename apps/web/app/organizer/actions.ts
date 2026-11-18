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

function eventPayload(fd: FormData, coverImageKey?: string) {
  const venueName = str(fd, 'venueName');
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
    ...(venueName
      ? { venue: { name: venueName, nameMy: str(fd, 'venueNameMy'), address: str(fd, 'address'), city: str(fd, 'city') ?? 'Yangon' } }
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
