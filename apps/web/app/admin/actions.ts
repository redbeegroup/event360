'use server';

import { revalidatePath } from 'next/cache';
import type { FormState } from '../actions';
import { api, ApiError } from '../lib/api';

const err = (e: unknown): FormState => (e instanceof ApiError ? { error: e.message, problems: e.problems } : { error: (e as Error).message });

export async function createOrgAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const r = await api<{ organization: { id: string; name: string }; inviteUrl: string }>('/admin/organizations', {
      method: 'POST',
      json: {
        name: fd.get('name'),
        slug: fd.get('slug'),
        description: fd.get('description') || undefined,
        ownerEmail: fd.get('ownerEmail'),
        contactPhone: fd.get('contactPhone') || undefined,
      },
    });
    revalidatePath('/admin/organizations');
    return { data: { inviteUrl: r.inviteUrl, name: r.organization.name, id: r.organization.id } };
  } catch (e) {
    return err(e);
  }
}

export async function setKycAction(_: FormState, fd: FormData): Promise<FormState> {
  const id = String(fd.get('id'));
  try {
    await api(`/admin/organizations/${id}/kyc`, { method: 'PATCH', json: { status: fd.get('status'), note: fd.get('note') || undefined } });
    revalidatePath(`/admin/organizations/${id}`);
    return { ok: '✓' };
  } catch (e) {
    return err(e);
  }
}

export async function adminInviteMemberAction(_: FormState, fd: FormData): Promise<FormState> {
  const id = String(fd.get('orgId'));
  try {
    const r = await api<{ inviteUrl: string }>(`/organizations/${id}/invitations`, {
      method: 'POST',
      json: { email: fd.get('email'), role: fd.get('role') },
    });
    revalidatePath(`/admin/organizations/${id}`);
    return { data: { inviteUrl: r.inviteUrl } };
  } catch (e) {
    return err(e);
  }
}

export async function approveEventAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/events/${fd.get('id')}/approve`, { method: 'POST' });
    revalidatePath('/admin/events');
    return { ok: '✓' };
  } catch (e) {
    return err(e);
  }
}

export async function rejectEventAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/events/${fd.get('id')}/reject`, { method: 'POST', json: { reason: fd.get('reason') } });
    revalidatePath('/admin/events');
    return { ok: '✓' };
  } catch (e) {
    return err(e);
  }
}

export async function saveSmsSettingsAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const s = (k: string) => String(fd.get(k) ?? '').trim();
    await api('/admin/settings/sms', {
      method: 'PUT',
      json: {
        ...(s('apiKey') ? { apiKey: s('apiKey') } : {}),
        ...(s('apiSecret') ? { apiSecret: s('apiSecret') } : {}),
        senderId: s('senderId'),
        otpTemplate: s('otpTemplate'),
        enabled: fd.get('enabled') === 'on',
        testMode: fd.get('testMode') === 'on',
      },
    });
    revalidatePath('/admin/settings');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function sendTestSmsAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const r = await api<{ messageId?: string; network?: string }>('/admin/settings/sms/test', { method: 'POST', json: { phone: fd.get('phone') } });
    revalidatePath('/admin/settings');
    return { ok: 'testSent', data: { messageId: r.messageId ?? '', network: r.network ?? '' } };
  } catch (e) {
    return err(e);
  }
}
