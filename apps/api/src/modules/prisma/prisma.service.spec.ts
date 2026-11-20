import { databaseUrl } from './prisma.service';

describe('databaseUrl', () => {
  const base = 'postgresql://u:p%40ss@db:5433/event360?schema=prod&connection_limit=5';
  it('replaces the pool size and adds a pool timeout, keeping everything else', () => {
    const u = new URL(databaseUrl(base, '15')!);
    expect(u.searchParams.get('connection_limit')).toBe('15');
    expect(u.searchParams.get('pool_timeout')).toBe('20');
    expect(u.searchParams.get('schema')).toBe('prod');
    expect(u.password).toBe('p%40ss');
  });
  it('leaves the URL alone without a valid limit', () => {
    expect(databaseUrl(base, undefined)).toBe(base);
    expect(databaseUrl(base, 'abc')).toBe(base);
    expect(databaseUrl('', '15')).toBe('');
  });
});
