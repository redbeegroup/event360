import { existsSync } from 'fs';
import { join } from 'path';
import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';

export interface PdfTicket {
  title: string;
  titleMy?: string | null;
  startsAt: Date;
  venue: string;
  guestName: string;
  seatLabel: string;
  seatLabelMy?: string | null;
  compLabel: string;
  token: string;
  code: string;
}

/** Noto Sans Myanmar ships with the API (assets/fonts, copied into the image); without it Myanmar text is skipped, never garbled. */
const MY_FONT = [join(__dirname, '../../../assets/fonts/NotoSansMyanmar-400.ttf'), join(process.cwd(), 'assets/fonts/NotoSansMyanmar-400.ttf')].find((p) => existsSync(p));
const HAS_MY = /[က-႟ꩠ-ꩿꧠ-꧿]/;
const A5: [number, number] = [419.53, 595.28];
const MARGIN = 36;

/** Date and time in Myanmar time, e.g. "Saturday 5 December 2026, 18:30 (MMT)". */
export function mmtDate(d: Date): string {
  return `${new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Yangon', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(d).replace(' at ', ', ')} (MMT)`;
}

/** One A5 portrait page per ticket. */
export async function renderTicketsPdf(tickets: PdfTicket[]): Promise<Buffer> {
  const doc = new PDFDocument({ size: A5, margin: MARGIN, autoFirstPage: false, info: { Title: 'Guest tickets' } });
  const chunks: Buffer[] = [];
  doc.on('data', (c: Buffer) => chunks.push(c));
  const done = new Promise<Buffer>((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });
  if (MY_FONT) doc.registerFont('my', MY_FONT);
  const width = A5[0] - MARGIN * 2;

  /** Writes text in a font that can draw it; Myanmar text with no Myanmar font is dropped. Returns whether it wrote. */
  const write = (text: string | null | undefined, size: number, opts: { bold?: boolean; gap?: number; color?: string; align?: 'center' | 'left' } = {}) => {
    if (!text) return false;
    const my = HAS_MY.test(text);
    if (my && !MY_FONT) return false;
    doc.font(my ? 'my' : opts.bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(size).fillColor(opts.color ?? '#111111');
    doc.text(text, MARGIN, doc.y, { width, align: opts.align ?? 'center' });
    doc.moveDown(opts.gap ?? 0.3);
    return true;
  };

  for (const t of tickets) {
    doc.addPage();
    doc.rect(MARGIN / 2, MARGIN / 2, A5[0] - MARGIN, A5[1] - MARGIN).lineWidth(1).strokeColor('#d4a017').stroke();
    doc.y = MARGIN + 6;
    write('EVENT 360 · GUEST TICKET', 9, { bold: true, color: '#8a6d0b', gap: 0.8 });
    write(t.title, 20, { bold: true });
    if (t.titleMy && t.titleMy !== t.title) write(t.titleMy, 16);
    doc.moveDown(0.6);
    write(mmtDate(t.startsAt), 11, { color: '#333333' });
    write(t.venue, 11, { color: '#333333', gap: 1.2 });
    write('GUEST', 8, { bold: true, color: '#777777', gap: 0.1 });
    write(t.guestName, 17, { bold: true });
    doc.moveDown(0.4);
    write('SEAT', 8, { bold: true, color: '#777777', gap: 0.1 });
    write(t.seatLabel, 13, { bold: true });
    if (t.seatLabelMy && t.seatLabelMy !== t.seatLabel) write(t.seatLabelMy, 12);
    doc.moveDown(0.3);
    write(t.compLabel, 11, { color: '#8a6d0b' });

    const qr = await QRCode.toBuffer(t.token, { errorCorrectionLevel: 'M', margin: 1, width: 360 });
    // QR and short code sit in a fixed band at the foot of the page so the code can never spill onto a second page
    const qrY = Math.max(doc.y + 6, 365);
    const size = Math.max(100, Math.min(150, 535 - qrY));
    doc.image(qr, (A5[0] - size) / 2, qrY, { width: size, height: size });
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#333333').text(t.code, MARGIN, qrY + size + 4, { width, align: 'center', lineBreak: false });
  }
  if (!tickets.length) doc.addPage();
  doc.end();
  return done;
}
