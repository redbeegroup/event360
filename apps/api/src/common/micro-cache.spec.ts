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

  describe('stale-while-revalidate', () => {
    beforeEach(() => jest.useFakeTimers());
    afterEach(() => jest.useRealTimers());
    const mk = (staleMs = 8000) => new MicroCache<number>(2000, 500, { staleMs });

    it('serves a fresh hit without loading', async () => {
      const c = mk();
      const load = jest.fn(async () => 1);
      await c.get('k', load);
      jest.advanceTimersByTime(1000);
      expect(await c.get('k', load)).toBe(1);
      expect(load).toHaveBeenCalledTimes(1);
    });

    it('returns the stale value at once, runs exactly one refresh, then serves the new value', async () => {
      const c = mk();
      let n = 0;
      let release!: () => void;
      const load = jest.fn(() => new Promise<number>((r) => { const v = ++n; release = () => r(v); }));
      const first = c.get('k', load);
      release();
      expect(await first).toBe(1);
      jest.advanceTimersByTime(3000);
      const got = await Promise.all([c.get('k', load), c.get('k', load), c.get('k', load)]);
      expect(got).toEqual([1, 1, 1]);
      expect(load).toHaveBeenCalledTimes(2);
      release();
      await Promise.resolve();
      await Promise.resolve();
      expect(await c.get('k', load)).toBe(2);
      expect(load).toHaveBeenCalledTimes(2);
    });

    it('waits for the load once past ttl + stale', async () => {
      const c = mk();
      let n = 0;
      const load = jest.fn(async () => ++n);
      await c.get('k', load);
      jest.advanceTimersByTime(10_001);
      expect(await c.get('k', load)).toBe(2);
    });

    it('keeps the old value when a refresh fails', async () => {
      const c = mk();
      await c.get('k', async () => 1);
      jest.advanceTimersByTime(3000);
      const bad = jest.fn(() => Promise.reject(new Error('db down')));
      expect(await c.get('k', bad)).toBe(1);
      await Promise.resolve();
      await Promise.resolve();
      expect(await c.get('k', bad)).toBe(1);
      expect(bad).toHaveBeenCalledTimes(2); // retried later, not cached, no unhandled rejection
    });

    it('staleMs 0 reloads synchronously after ttl as before', async () => {
      const c = mk(0);
      let n = 0;
      const load = jest.fn(async () => ++n);
      await c.get('k', load);
      jest.advanceTimersByTime(2001);
      expect(await c.get('k', load)).toBe(2);
    });
  });
});
