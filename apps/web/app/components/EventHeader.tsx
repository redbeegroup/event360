import Link from 'next/link';
import type { ReactNode } from 'react';
import { fmtDate, pick, t } from '../lib/i18n';
import type { EventDto } from '../lib/types';
import { EventTabs } from './EventTabs';
import { PageHeader } from './PageHeader';

/** Page header + Edit / Dashboard / Seats tabs shared by an event's three pages. */
export async function EventHeader({ orgId, event, active, actions, seats }: { orgId: string; event: Pick<EventDto, 'id' | 'title' | 'titleMy' | 'status' | 'startsAt' | 'venue' | 'seating'>; active: 'edit' | 'dashboard' | 'seats'; actions?: ReactNode; /** Force the Seats tab on or off; default follows the event's seat map. */ seats?: boolean }) {
  const tr = await t();
  const venue = event.venue ? pick(tr.lang, event.venue.name, event.venue.nameMy) : null;
  return (
    <>
      <PageHeader
        breadcrumb={<Link href={`/organizer/${orgId}`}>← {tr.events}</Link>}
        title={pick(tr.lang, event.title, event.titleMy)}
        badge={<span className={`badge ${event.status}`}>{tr.statuses[event.status]}</span>}
        subtitle={[fmtDate(event.startsAt, tr.lang), venue].filter(Boolean).join(' · ')}
        actions={actions}
      />
      <EventTabs orgId={orgId} eventId={event.id} active={active} seats={seats ?? !!event.seating} />
    </>
  );
}
