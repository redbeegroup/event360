export function StatTile({ label, value, unit, testId, tone }: { label: string; value: string | number; unit?: string; testId?: string; tone?: 'danger' }) {
  return (
    <div className="stat-tile">
      {label && <span className="stat-label">{label}</span>}
      <span className={tone === 'danger' ? 'stat-value danger-text' : 'stat-value'} data-testid={testId}>
        {value}
        {unit && <span className="stat-unit"> {unit}</span>}
      </span>
    </div>
  );
}
