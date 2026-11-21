'use client';

import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { SideMenu } from './SideMenu';

export interface ShellItem {
  href: string;
  label: string;
  /** Extra path prefixes that also mark this item active (the item's own href always does). */
  also?: string[];
  /** Only the exact href marks it active (for the section's root page). */
  exact?: boolean;
}

/** Side menu + content frame. Path-aware so the menu highlights the current section.
    `bare` is a path suffix (e.g. the print page) where no shell is drawn at all. */
export function Shell({ items, label, bare, children }: { items: ShellItem[]; label: string; bare?: string; children: ReactNode }) {
  const path = usePathname() ?? '';
  if (bare && path.endsWith(bare)) return <>{children}</>;
  const isActive = (i: ShellItem) =>
    path === i.href || (!i.exact && path.startsWith(`${i.href}/`)) || (i.also ?? []).some((p) => path === p || path.startsWith(`${p}/`));
  return (
    <div className="shell">
      <SideMenu label={label} items={items.map((i) => ({ href: i.href, label: i.label, active: isActive(i) }))} />
      <div className="shell-main">{children}</div>
    </div>
  );
}
