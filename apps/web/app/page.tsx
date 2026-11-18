import Link from 'next/link';

export default function Home() {
  return (
    <main style={{ padding: 32 }}>
      <h1>Event 360 Portal</h1>
      <ul>
        <li><Link href="/organizer">Organizer back-office</Link></li>
        <li><Link href="/admin">Platform admin</Link></li>
      </ul>
    </main>
  );
}
