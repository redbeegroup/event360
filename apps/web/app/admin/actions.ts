'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
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

// ───────────── finance ─────────────

const num = (fd: FormData, k: string) => {
  const v = String(fd.get(k) ?? '').trim();
  return v === '' ? null : Number(v);
};

export async function saveFeeAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const pct = Number(String(fd.get('percent') ?? '0').trim() || '0');
    await api('/admin/finance/fee', {
      method: 'PUT',
      json: {
        percentBp: Math.round(pct * 100),
        fixedMmk: num(fd, 'fixedMmk') ?? 0,
        minMmk: num(fd, 'minMmk'),
        maxMmk: num(fd, 'maxMmk'),
        isActive: fd.get('isActive') === 'on',
      },
    });
    revalidatePath('/admin/finance');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function refundOrderAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/finance/orders/${fd.get('id')}/refund`, { method: 'POST', json: { reason: fd.get('reason') } });
    revalidatePath('/admin/finance');
    return { ok: 'refunded' };
  } catch (e) {
    return err(e);
  }
}

export async function completeRefundAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/finance/refunds/${fd.get('id')}/complete`, { method: 'POST', json: { reference: fd.get('reference') } });
    revalidatePath('/admin/finance');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function retryRefundAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/finance/refunds/${fd.get('id')}/retry`, { method: 'POST' });
    revalidatePath('/admin/finance');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function savePaymentSettingsAction(_: FormState, fd: FormData): Promise<FormState> {
  const provider = String(fd.get('provider'));
  try {
    const values: Record<string, string> = {};
    for (const [k, v] of fd.entries()) if (k.startsWith('v_')) values[k.slice(2)] = String(v).trim();
    await api(`/admin/settings/payments/${provider}`, {
      method: 'PUT',
      json: { values, mode: fd.get('mode'), enabled: fd.get('enabled') === 'on' },
    });
    revalidatePath('/admin/settings');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function savePushSettingsAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const file = fd.get('keyFile');
    let json = String(fd.get('serviceAccountJson') ?? '').trim();
    if (!json && file instanceof File && file.size > 0) {
      if (file.size > 20_000) return { error: 'File too large for a service account key' };
      json = (await file.text()).trim();
    }
    await api('/admin/settings/push', { method: 'PUT', json: { ...(json ? { serviceAccountJson: json } : {}), enabled: fd.get('enabled') === 'on' } });
    revalidatePath('/admin/settings');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function sendTestPushAction(): Promise<FormState> {
  try {
    const r = await api<{ devices: number }>('/admin/settings/push/test', { method: 'POST' });
    return { ok: 'pushTestSent', data: { devices: String(r.devices) } };
  } catch (e) {
    return err(e);
  }
}

export async function saveEmailSettingsAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    const pass = String(fd.get('pass') ?? '');
    const alertTo = String(fd.get('alertTo') ?? '').split(/[\s,;]+/).map((s) => s.trim()).filter(Boolean);
    await api('/admin/settings/email', {
      method: 'PUT',
      json: {
        host: String(fd.get('host') ?? '').trim(),
        port: Number(fd.get('port') || 587),
        secure: fd.get('secure') === 'on',
        user: String(fd.get('user') ?? '').trim(),
        ...(pass ? { pass } : {}),
        from: String(fd.get('from') ?? '').trim(),
        alertTo,
        enabled: fd.get('enabled') === 'on',
      },
    });
    revalidatePath('/admin/settings');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function sendTestEmailAction(): Promise<FormState> {
  try {
    await api('/admin/settings/email/test', { method: 'POST' });
    return { ok: 'emailTestSent' };
  } catch (e) {
    return err(e);
  }
}

export async function resolveErrorAction(_: FormState, fd: FormData): Promise<FormState> {
  try {
    await api(`/admin/ops/errors/${encodeURIComponent(String(fd.get('id')))}/resolve`, { method: 'POST' });
    revalidatePath('/admin/ops');
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

// ---- Venues and seat maps ----

const numField = (fd: FormData, k: string) => {
  const v = String(fd.get(k) ?? '').trim();
  return v === '' ? undefined : Number(v);
};

function venueBody(fd: FormData, clear: boolean) {
  // On update, cleared optional fields are sent as null (the DTOs allow null via @IsOptional) so they really clear.
  const none = clear ? null : undefined;
  return {
    venueName: String(fd.get('venueName') ?? '').trim(),
    venueNameMy: String(fd.get('venueNameMy') ?? '').trim() || none,
    city: String(fd.get('city') ?? '').trim(),
    address: String(fd.get('address') ?? '').trim() || none,
    latitude: numField(fd, 'latitude') ?? none,
    longitude: numField(fd, 'longitude') ?? none,
    mapUrl: String(fd.get('mapUrl') ?? '').trim() || none,
  };
}

export async function createSeatMapAction(_: FormState, fd: FormData): Promise<FormState> {
  let id: string;
  try {
    id = (await api<{ id: string }>('/admin/seat-maps', { method: 'POST', json: venueBody(fd, false) })).id;
  } catch (e) {
    return err(e);
  }
  revalidatePath('/admin/venues');
  redirect(`/admin/venues/${id}`);
}

export async function updateSeatMapAction(_: FormState, fd: FormData): Promise<FormState> {
  const id = String(fd.get('id'));
  try {
    await api(`/admin/seat-maps/${id}`, { method: 'PATCH', json: { ...venueBody(fd, true), isActive: fd.get('isActive') === 'on' } });
    revalidatePath(`/admin/venues/${id}`);
    revalidatePath('/admin/venues');
    return { ok: '✓' };
  } catch (e) {
    return err(e);
  }
}

/** Called from the editor (client component). Returns the API's validation `problems` on a 400. */
export async function saveSeatDraftAction(id: string, layout: unknown): Promise<FormState> {
  try {
    await api(`/admin/seat-maps/${id}/draft`, { method: 'PUT', json: { layout } });
    revalidatePath(`/admin/venues/${id}`);
    return { ok: 'saved' };
  } catch (e) {
    return err(e);
  }
}

export async function importSeatLayoutAction(id: string, layout: unknown): Promise<FormState> {
  try {
    await api(`/admin/seat-maps/${id}/import`, { method: 'POST', json: { layout } });
    revalidatePath(`/admin/venues/${id}`);
    return { ok: 'imported' };
  } catch (e) {
    return err(e);
  }
}

export async function publishSeatMapAction(id: string): Promise<FormState> {
  try {
    await api(`/admin/seat-maps/${id}/publish`, { method: 'POST' });
    revalidatePath(`/admin/venues/${id}`);
    revalidatePath('/admin/venues');
    return { ok: 'published' };
  } catch (e) {
    return err(e);
  }
}
