import type { Metadata } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = { title: 'Event 360 Portal', description: 'Admin & organizer portal' };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui, "Noto Sans Myanmar", sans-serif', margin: 0 }}>{children}</body>
    </html>
  );
}
