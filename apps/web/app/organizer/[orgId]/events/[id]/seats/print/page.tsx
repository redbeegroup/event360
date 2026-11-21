import Link from 'next/link';
import { PrintTickets, type PrintLabels, type PrintTicket } from '../../../../../../components/PrintTickets';
import { api } from '../../../../../../lib/api';
import { fmtDate, t } from '../../../../../../lib/i18n';

export const dynamic = 'force-dynamic';

interface PrintData {
  event: { title: string; titleMy: string | null; startsAt: string; venue: string; venueMy: string };
  tickets: (PrintTicket & { phoneHint: string })[];
}

export default async function PrintPage({
  params,
  searchParams,
}: {
  params: Promise<{ orgId: string; id: string }>;
  searchParams: Promise<{ ids?: string; auto?: string }>;
}) {
  const [{ orgId, id }, q, tr] = await Promise.all([params, searchParams, t()]);
  const qs = q.ids ? `?ids=${encodeURIComponent(q.ids)}` : '';
  const data = await api<PrintData>(`/organizations/${orgId}/events/${id}/seating/comps/print${qs}`).catch(() => null);
  const back = `/organizer/${orgId}/events/${id}/seats`;
  if (!data) {
    return (
      <>
        <p><Link href={back}>← {tr.stBackSeats}</Link></p>
        <div className="card"><p className="muted">{tr.stNothingPrint}</p></div>
      </>
    );
  }
  const labels: PrintLabels = { head: tr.stTicketHead, guest: tr.stTicketGuest, seat: tr.stTicketSeat, print: tr.stPrintNow, back: tr.stBackSeats, hint: tr.stPrintHint };
  return (
    <PrintTickets
      event={{
        title: data.event.title,
        titleMy: data.event.titleMy,
        dateEn: fmtDate(data.event.startsAt, 'en'),
        dateMy: fmtDate(data.event.startsAt, 'my'),
        venue: data.event.venue,
        venueMy: data.event.venueMy,
      }}
      tickets={data.tickets}
      labels={labels}
      backHref={back}
      auto={q.auto === '1'}
    />
  );
}
