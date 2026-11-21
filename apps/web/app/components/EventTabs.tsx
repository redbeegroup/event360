import Link from 'next/link';
import { t } from '../lib/i18n';

/** Edit / Dashboard / Seats tabs under an event title. Seats is shown only where the Seats page is
    available (the event has a seat map); pass `seats` from the event's `seating`. */
export async function EventTabs({ orgId, eventId, active, seats = false }: { orgId: string; eventId: string; active: 'edit' | 'dashboard' | 'seats'; seats?: boolean }) {
  const tr = await t();
  const base = `/organizer/${orgId}/events/${eventId}`;
  const tabs = [
    { key: 'edit', href: base, label: tr.tabEdit },
    { key: 'dashboard', href: `${base}/dashboard`, label: tr.dashboard },
    ...(seats ? [{ key: 'seats', href: `${base}/seats`, label: tr.tabSeats }] : []),
  ];
  return (
    <nav className="event-tabs" aria-label={tr.eventSections}>
      {tabs.map((x) => (
        <Link key={x.key} href={x.href} className={x.key === active ? 'active' : undefined} aria-current={x.key === active ? 'page' : undefined}>
          {x.label}
        </Link>
      ))}
    </nav>
  );
}
