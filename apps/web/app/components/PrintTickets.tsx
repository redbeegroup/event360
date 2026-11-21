'use client';

import Link from 'next/link';
import QRCode from 'qrcode';
import { useEffect, useState } from 'react';

export interface PrintTicket {
  id: string;
  guestName: string;
  seatLabel: string;
  seatLabelMy: string | null;
  compLabel: string;
  token: string;
  code: string;
}
export interface PrintLabels {
  head: string;
  guest: string;
  seat: string;
  print: string;
  back: string;
  hint: string;
}
interface PrintEvent {
  title: string;
  titleMy: string | null;
  dateEn: string;
  dateMy: string;
  venue: string;
  venueMy: string;
}

/** One A5 page per guest ticket, English and Myanmar text, with the live QR. Print with the browser (A5 paper). */
export function PrintTickets({ event, tickets, labels, backHref, auto }: { event: PrintEvent; tickets: PrintTicket[]; labels: PrintLabels; backHref: string; auto: boolean }) {
  const [qrs, setQrs] = useState<Record<string, string>>({});

  useEffect(() => {
    let off = false;
    Promise.all(tickets.map(async (t) => [t.id, await QRCode.toDataURL(t.token, { errorCorrectionLevel: 'M', margin: 1, width: 360 })] as const)).then((rows) => {
      if (off) return;
      setQrs(Object.fromEntries(rows));
      if (auto) setTimeout(() => window.print(), 300);
    });
    return () => {
      off = true;
    };
  }, [tickets, auto]);

  return (
    <div className="print-root">
      <style>{`
        @page { size: A5; margin: 0; }
        .print-sheet { background: #fff; color: #111; width: 148mm; min-height: 210mm; margin: 0 auto 16px; padding: 12mm 10mm; border: 2px solid #d4a017; border-radius: 6px; display: flex; flex-direction: column; align-items: center; text-align: center; font-family: var(--body), system-ui, sans-serif; }
        .print-sheet h2, .print-sheet h3 { font-family: inherit; }
        .print-sheet .eyebrow { font-size: 9pt; font-weight: 700; color: #8a6d0b; letter-spacing: .04em; margin-bottom: 6mm; }
        .print-sheet h2 { font-size: 20pt; margin: 0; line-height: 1.25; }
        .print-sheet h3 { font-size: 15pt; margin: 1mm 0 0; font-weight: 600; line-height: 1.5; }
        .print-sheet .when { margin-top: 5mm; font-size: 11pt; color: #333; }
        .print-sheet .cap { font-size: 8pt; font-weight: 700; color: #777; margin-top: 6mm; }
        .print-sheet .big { font-size: 17pt; font-weight: 700; }
        .print-sheet .seat { font-size: 13pt; font-weight: 700; }
        .print-sheet .seat-my { font-size: 12pt; }
        .print-sheet .lab { margin-top: 3mm; font-size: 11pt; color: #8a6d0b; }
        .print-sheet img { width: 44mm; height: 44mm; margin-top: auto; }
        .print-sheet .code { font-weight: 700; font-size: 12pt; color: #333; letter-spacing: .08em; }
        @media print {
          header.top, .no-print { display: none !important; }
          html, body { background: #fff !important; }
          main { max-width: none !important; margin: 0 !important; padding: 0 !important; }
          .print-sheet { margin: 0; border: 0; border-radius: 0; width: 148mm; height: 210mm; min-height: 0; padding: 14mm 12mm; break-after: page; page-break-after: always; break-inside: avoid; overflow: hidden; }
          .print-sheet:last-child { break-after: auto; page-break-after: auto; }
        }
      `}</style>
      <div className="no-print">
        <p><Link href={backHref}>← {labels.back}</Link></p>
        <div className="row" style={{ marginBottom: 12 }}>
          <button type="button" onClick={() => window.print()}>{labels.print}</button>
          <span className="muted">{labels.hint}</span>
        </div>
      </div>
      {tickets.map((tk) => (
        <section key={tk.id} className="print-sheet" aria-label={tk.guestName}>
          <div className="eyebrow">{labels.head}</div>
          <h2>{event.title}</h2>
          {event.titleMy && event.titleMy !== event.title && <h3 lang="my">{event.titleMy}</h3>}
          <div className="when">{event.dateEn}</div>
          {event.dateMy && <div className="when" lang="my" style={{ marginTop: 0 }}>{event.dateMy}</div>}
          <div className="when" style={{ marginTop: '2mm' }}>{event.venue}</div>
          {event.venueMy && event.venueMy !== event.venue && <div className="when" lang="my" style={{ marginTop: 0 }}>{event.venueMy}</div>}
          <div className="cap">{labels.guest}</div>
          <div className="big">{tk.guestName}</div>
          <div className="cap">{labels.seat}</div>
          <div className="seat">{tk.seatLabel}</div>
          {tk.seatLabelMy && tk.seatLabelMy !== tk.seatLabel && <div className="seat-my" lang="my">{tk.seatLabelMy}</div>}
          {tk.compLabel && <div className="lab">{tk.compLabel}</div>}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {qrs[tk.id] ? <img src={qrs[tk.id]} alt="QR" /> : <div style={{ width: '44mm', height: '44mm', marginTop: 'auto' }} />}
          <div className="code">{tk.code}</div>
        </section>
      ))}
    </div>
  );
}
