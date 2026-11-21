import type { ReactNode } from 'react';

export function PageHeader({ breadcrumb, title, badge, subtitle, actions }: { breadcrumb?: ReactNode; title: ReactNode; badge?: ReactNode; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="page-header">
      <div className="page-header-main">
        {breadcrumb && <div className="crumb">{breadcrumb}</div>}
        <div className="page-header-title">
          <h1>{title}</h1>
          {badge}
        </div>
        {subtitle && <div className="page-header-sub">{subtitle}</div>}
      </div>
      {actions && <div className="page-header-actions">{actions}</div>}
    </header>
  );
}
