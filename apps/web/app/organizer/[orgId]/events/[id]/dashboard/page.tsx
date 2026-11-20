import Link from 'next/link';
import { api } from '../../../../../lib/api';
import { fmtMmk, t } from '../../../../../lib/i18n';

export const dynamic = 'force-dynamic';

interface Dashboard {
  totals: { views: number; orders: number; ticketsSold: number; capacity: number; revenueMmk: number; discountMmk: number; refundedOrders: number; checkedIn: number; conversion: number | null };
  daily: { day: string; orders: number; tickets: number; revenueMmk: number; views: number }[];
  checkinsByQuarterHour: { at: string; count: number }[];
  checkinsByGate: { gate: string; count: number }[];
  ticketTypes: { id: string; name: string; sold: number; quota: number; priceMmk: number }[];
}

const nf = (lang: string) => new Intl.NumberFormat(lang === 'my' ? 'my-MM' : 'en-US');
const compact = (lang: string) => new Intl.NumberFormat(lang === 'my' ? 'my-MM' : 'en-US', { notation: 'compact', maximumFractionDigits: 1 });
/** Round an axis maximum up to 1/2/5 × 10^n. */
function niceMax(v: number) {
  if (v <= 0) return 1;
  const p = 10 ** Math.floor(Math.log10(v));
  return [1, 2, 5, 10].map((m) => m * p).find((m) => m >= v)!;
}

/** Single-series vertical bars (one hue, rounded data end, 2px gaps, recessive grid, native hover titles, table view). */
function Bars({ points, title, fmt, tableLabel, xLabel, lang }: { points: { x: string; y: number; label: string }[]; title: string; fmt: (n: number) => string; tableLabel: string; xLabel: string; lang: string }) {
  const W = 640, H = 180, L = 48, B = 22, T = 8;
  const tick = (v: number) => compact(lang).format(v); // axis: compact; hover + table: full value
  const max = niceMax(Math.max(0, ...points.map((p) => p.y)));
  const plotW = W - L - 4, plotH = H - B - T;
  const step = plotW / Math.max(points.length, 1);
  const bw = Math.max(2, Math.min(28, step - 2));
  const ticks = [0, max / 2, max];
  const labelEvery = Math.ceil(points.length / 6);
  return (
    <figure className="chart">
      <figcaption>{title}</figcaption>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={title} style={{ width: "100%", height: "auto" }}>
        {ticks.map((v) => {
          const y = T + plotH - (v / max) * plotH;
          return (
            <g key={v}>
              <line x1={L} x2={W - 4} y1={y} y2={y} className="grid" />
              <text x={L - 6} y={y + 4} textAnchor="end" className="axis">{tick(v)}</text>
            </g>
          );
        })}
        {points.map((p, i) => {
          const h = (p.y / max) * plotH;
          const x = L + i * step + (step - bw) / 2;
          const y = T + plotH - h;
          const r = Math.min(4, bw / 2, h);
          return (
            <g key={p.x}>
              {/* hit target: full column height */}
              <rect x={L + i * step} y={T} width={step} height={plotH} className="hit">
                <title>{`${p.label}: ${fmt(p.y)}`}</title>
              </rect>
              {h > 0 && (
                <path
                  className="bar"
                  d={`M${x},${y + h} V${y + r} Q${x},${y} ${x + r},${y} H${x + bw - r} Q${x + bw},${y} ${x + bw},${y + r} V${y + h} Z`}
                >
                  <title>{`${p.label}: ${fmt(p.y)}`}</title>
                </path>
              )}
              {i % labelEvery === 0 && (
                <text x={L + i * step + step / 2} y={H - 6} textAnchor="middle" className="axis">{p.label}</text>
              )}
            </g>
          );
        })}
      </svg>
      <details>
        <summary>{tableLabel}</summary>
        <table>
          <thead><tr><th>{xLabel}</th><th>{title}</th></tr></thead>
          <tbody>{points.map((p) => <tr key={p.x}><td>{p.label}</td><td>{fmt(p.y)}</td></tr>)}</tbody>
        </table>
      </details>
    </figure>
  );
}

/** Horizontal share bars with direct value labels (categories by count). */
function HBars({ rows, title, lang }: { rows: { name: string; value: number; of?: number }[]; title: string; lang: string }) {
  const max = Math.max(1, ...rows.map((r) => r.of ?? r.value));
  return (
    <figure className="chart">
      <figcaption>{title}</figcaption>
      {rows.map((r) => (
        <div key={r.name} className="hrow" title={`${r.name}: ${nf(lang).format(r.value)}${r.of ? ` / ${nf(lang).format(r.of)}` : ''}`}>
          <span className="hname">{r.name}</span>
          <span className="htrack">
            {r.of ? <span className="hcap" style={{ width: `${(r.of / max) * 100}%` }} /> : null}
            <span className="hbar" style={{ width: `${(r.value / max) * 100}%` }} />
          </span>
          <span className="hval">{nf(lang).format(r.value)}{r.of ? ` / ${nf(lang).format(r.of)}` : ''}</span>
        </div>
      ))}
    </figure>
  );
}

export default async function DashboardPage({ params }: { params: Promise<{ orgId: string; id: string }> }) {
  const { orgId, id } = await params;
  const [tr, d, ev] = await Promise.all([
    t(),
    api<Dashboard>(`/organizations/${orgId}/events/${id}/dashboard`),
    api<{ title: string; titleMy: string | null }>(`/organizations/${orgId}/events/${id}`),
  ]);
  const n = nf(tr.lang);
  const dayLabel = (iso: string) => new Intl.DateTimeFormat(tr.lang === 'my' ? 'my-MM' : 'en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso}T00:00:00Z`));
  const tiles: [string, string][] = [
    [tr.dashViews, n.format(d.totals.views)],
    [tr.dashOrders, n.format(d.totals.orders)],
    [tr.dashTickets, `${n.format(d.totals.ticketsSold)} / ${n.format(d.totals.capacity)}`],
    [tr.dashRevenue, fmtMmk(d.totals.revenueMmk, tr.lang)],
    [tr.dashDiscount, fmtMmk(d.totals.discountMmk, tr.lang)],
    [tr.dashCheckedIn, n.format(d.totals.checkedIn)],
    [tr.dashConversion, d.totals.conversion == null ? '—' : `${d.totals.conversion}%`],
  ];
  const daily = (k: 'orders' | 'revenueMmk' | 'views') => d.daily.map((r) => ({ x: r.day, y: r[k], label: dayLabel(r.day) }));
  return (
    <>
      <p><Link href={`/organizer/${orgId}/events/${id}`}>← {tr.backToEvent}</Link></p>
      <h1>{tr.dashboard}: {tr.lang === 'my' && ev.titleMy ? ev.titleMy : ev.title}</h1>
      <div className="tiles">
        {tiles.map(([k, v]) => (
          <div key={k} className="tile"><div className="muted">{k}</div><div className="tile-v">{v}</div></div>
        ))}
      </div>
      <div className="card">
        <Bars points={daily('orders')} title={tr.dashDailyOrders} fmt={(v) => n.format(Math.round(v))} tableLabel={tr.dashShowTable} xLabel={tr.day} lang={tr.lang} />
        <Bars points={daily('revenueMmk')} title={tr.dashDailyRevenue} fmt={(v) => n.format(Math.round(v))} tableLabel={tr.dashShowTable} xLabel={tr.day} lang={tr.lang} />
        <Bars points={daily('views')} title={tr.dashDailyViews} fmt={(v) => n.format(Math.round(v))} tableLabel={tr.dashShowTable} xLabel={tr.day} lang={tr.lang} />
      </div>
      <div className="card">
        <HBars title={tr.dashByType} rows={d.ticketTypes.map((x) => ({ name: x.name, value: x.sold, of: x.quota }))} lang={tr.lang} />
      </div>
      <div className="card">
        {d.checkinsByQuarterHour.length === 0 ? (
          <p className="muted">{tr.dashCheckinsTime}: {tr.dashNoData}</p>
        ) : (
          <>
            <Bars
              points={d.checkinsByQuarterHour.map((c) => ({ x: c.at, y: c.count, label: c.at.slice(11) }))}
              title={`${tr.dashCheckinsTime} (${tr.dashTimeNote})`}
              fmt={(v) => n.format(Math.round(v))}
              tableLabel={tr.dashShowTable}
              xLabel={tr.time}
              lang={tr.lang}
            />
            <HBars title={tr.dashByGate} rows={d.checkinsByGate.map((g) => ({ name: g.gate, value: g.count }))} lang={tr.lang} />
          </>
        )}
      </div>
    </>
  );
}
