import Link from 'next/link';

export interface SideMenuItem {
  href: string;
  label: string;
  active?: boolean;
}

/** Vertical menu on wide screens; collapses to a wrapped top menu below 760 px (CSS only). */
export function SideMenu({ items, label }: { items: SideMenuItem[]; label: string }) {
  return (
    <nav className="side-menu" aria-label={label}>
      {items.map((i) => (
        <Link key={i.href} href={i.href} className={i.active ? 'active' : undefined} aria-current={i.active ? 'page' : undefined}>
          {i.label}
        </Link>
      ))}
    </nav>
  );
}
