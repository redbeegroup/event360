import Link from 'next/link';
import { SeatsManager, type Counts, type GuestRow, type SeatRow, type TypeRow } from '../../../../../components/SeatsManager';
import { api } from '../../../../../lib/api';
import { pick, t } from '../../../../../lib/i18n';
import type { Layout } from '../../../../../lib/seat-layout';
import type { EventDto } from '../../../../../lib/types';
import type { SeatRule } from '../../../../actions';

export const dynamic = 'force-dynamic';

interface Overview {
  layout: Layout | null;
  versionId: string | null;
  rules: { sectionKey: string; rowLabel: string | null; ticketTypeId: string }[];
  counts: Record<string, Counts>;
  seats: SeatRow[];
}

export default async function SeatsPage({ params }: { params: Promise<{ orgId: string; id: string }> }) {
  const { orgId, id } = await params;
  const base = `/organizations/${orgId}/events/${id}`;
  const [tr, e, ov, guests, codes] = await Promise.all([
    t(),
    api<EventDto>(base),
    api<Overview>(`${base}/seating`),
    api<GuestRow[]>(`${base}/seating/guests`).catch(() => [] as GuestRow[]),
    api<unknown>(`${base}/crew-codes`).catch(() => null), // null = not an editor (same check as the event page)
  ]);
  const labels = Object.fromEntries(
    Object.entries(tr).filter(([k, v]) => typeof v === 'string' && (/^(st|sm)[A-Z]/.test(k) || ['name', 'phone', 'status'].includes(k))),
  ) as Record<string, string>;
  const types: TypeRow[] = e.ticketTypes.map((x) => ({ id: x.id, name: x.name, nameMy: x.nameMy }));
  const rules: SeatRule[] = ov.rules.map((r) => ({ sectionKey: r.sectionKey, ...(r.rowLabel != null ? { rowLabel: r.rowLabel } : {}), ticketTypeId: r.ticketTypeId }));

  return (
    <>
      <p><Link href={`/organizer/${orgId}/events/${id}`}>← {tr.backToEvent}</Link></p>
      <h1>{tr.stTitle} · {pick(tr.lang, e.title, e.titleMy)}</h1>
      {!ov.layout ? (
        <div className="card"><p className="muted">{tr.stNoMap}</p></div>
      ) : types.length === 0 ? (
        <div className="card"><p className="muted">{tr.stNoTypes}</p></div>
      ) : (
        <SeatsManager
          orgId={orgId}
          eventId={id}
          lang={tr.lang}
          labels={labels}
          layout={ov.layout}
          types={types}
          rules={rules}
          seats={ov.seats}
          counts={ov.counts}
          guests={guests}
          canEdit={codes !== null}
        />
      )}
    </>
  );
}
