import { fetchCategories } from '../lib';

export const dynamic = 'force-dynamic';

const SECTIONS = [
  'Organizer KYC approvals',
  'Event moderation queue',
  'Featured placements & creative approvals',
  'Fee rules & plans',
  'Payments & reconciliation',
  'Payout batches',
  'Streaming monitor',
  'Audit log',
];

export default async function AdminHome() {
  const categories = await fetchCategories();
  return (
    <main style={{ padding: 32 }}>
      <h1>Platform admin</h1>
      <h2>Modules</h2>
      <ul>{SECTIONS.map((s) => <li key={s}>{s}</li>)}</ul>
      <h2>Categories</h2>
      {categories.length === 0 ? (
        <p>API unreachable or no categories seeded.</p>
      ) : (
        <ul>
          {categories.map((c) => (
            <li key={c.id}>
              <strong>{c.nameEn}</strong>
              <ul>{c.children.map((s) => <li key={s.id}>{s.nameEn}</li>)}</ul>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
