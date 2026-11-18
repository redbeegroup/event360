const SECTIONS = [
  'Events (in-person / online / hybrid)',
  'Ticket types & promo codes',
  'Attendees',
  'Crew, shifts & gates',
  'Live studio & recordings',
  'Promote (Featured placements)',
  'Sales & attendance reports',
  'Payouts',
  'Plan & billing',
];

export default function OrganizerHome() {
  return (
    <main style={{ padding: 32 }}>
      <h1>Organizer back-office</h1>
      <ul>{SECTIONS.map((s) => <li key={s}>{s}</li>)}</ul>
    </main>
  );
}
