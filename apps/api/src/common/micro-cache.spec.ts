import { MicroCache } from './micro-cache';

describe('MicroCache', () => {
  it('serves a hit within the lifetime and reloads after it', async () => {
    const c = new MicroCache<number>(50);
    let n = 0;
    const load = async () => ++n;
    expect(await c.get('k', load)).toBe(1);
    expect(await c.get('k', load)).toBe(1);
    await new Promise((r) => setTimeout(r, 60));
    expect(await c.get('k', load)).toBe(2);
  });

  it('shares one load between simultaneous misses', async () => {
    const c = new MicroCache<number>(1000);
    let calls = 0;
    const load = () => new Promise<number>((r) => setTimeout(() => r(++calls), 20));
    const got = await Promise.all(Array.from({ length: 50 }, () => c.get('k', load)));
    expect(calls).toBe(1);
    expect(new Set(got)).toEqual(new Set([1]));
  });

  it('never caches errors, and is a pass-through when disabled', async () => {
    const c = new MicroCache<number>(1000);
    await expect(c.get('k', () => Promise.reject(new Error('nope')))).rejects.toThrow('nope');
    expect(await c.get('k', async () => 7)).toBe(7);
    const off = new MicroCache<number>(0);
    let n = 0;
    await off.get('k', async () => ++n);
    await off.get('k', async () => ++n);
    expect(n).toBe(2);
  });
});
