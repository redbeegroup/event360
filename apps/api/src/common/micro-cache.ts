/**
 * Tiny per-pod cache for public, user-independent responses (event lists, event pages, categories).
 *
 * Under load the same few pages are requested hundreds of times a second; serving them from memory for
 * a few seconds removes almost all of that database work. Concurrent misses for the same key share one
 * load. Errors are never cached. Seat availability shown can be up to `ttlMs` old; ordering always
 * checks live quotas, so a stale page can't oversell.
 */
export class MicroCache<T> {
  private readonly entries = new Map<string, { at: number; value: T }>();
  private readonly inflight = new Map<string, Promise<T>>();

  constructor(
    private readonly ttlMs: number,
    private readonly maxEntries = 500,
  ) {}

  async get(key: string, load: () => Promise<T>): Promise<T> {
    if (this.ttlMs <= 0) return load();
    const hit = this.entries.get(key);
    if (hit && Date.now() - hit.at < this.ttlMs) return hit.value;
    const pending = this.inflight.get(key);
    if (pending) return pending;
    const p = load()
      .then((value) => {
        if (this.entries.size >= this.maxEntries) this.entries.delete(this.entries.keys().next().value as string);
        this.entries.set(key, { at: Date.now(), value });
        return value;
      })
      .finally(() => this.inflight.delete(key));
    this.inflight.set(key, p);
    return p;
  }

  clear() {
    this.entries.clear();
  }
}

/** Default lifetime for public responses: PUBLIC_CACHE_MS, 10 s, or off under tests. */
export function publicCacheMs(fallback = 10_000) {
  const v = process.env.PUBLIC_CACHE_MS;
  if (v !== undefined && /^\d+$/.test(v)) return Number(v);
  return process.env.NODE_ENV === 'test' ? 0 : fallback;
}
