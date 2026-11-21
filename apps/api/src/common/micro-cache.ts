import { Logger } from '@nestjs/common';

/**
 * Tiny per-pod cache for public, user-independent responses (event lists, event pages, categories).
 *
 * Under load the same few pages are requested hundreds of times a second; serving them from memory for
 * a few seconds removes almost all of that database work. Concurrent misses for the same key share one
 * load. Errors are never cached. Seat availability shown can be up to `ttlMs` old; ordering always
 * checks live quotas, so a stale page can't oversell.
 *
 * Opt-in stale-while-revalidate: with `staleMs > 0`, an entry older than `ttlMs` but younger than
 * `ttlMs + staleMs` is returned immediately while one background refresh runs (errors are swallowed and
 * the old value kept). Older or missing entries wait for the single-flight load as usual.
 */
export class MicroCache<T> {
  private readonly log = new Logger('MicroCache');
  private readonly entries = new Map<string, { at: number; value: T }>();
  private readonly inflight = new Map<string, Promise<T>>();

  constructor(
    private readonly ttlMs: number,
    private readonly maxEntries = 500,
    private readonly opts: { staleMs?: number } = {},
  ) {}

  async get(key: string, load: () => Promise<T>): Promise<T> {
    if (this.ttlMs <= 0) return load();
    const hit = this.entries.get(key);
    const age = hit ? Date.now() - hit.at : Infinity;
    if (hit && age < this.ttlMs) return hit.value;
    const pending = this.inflight.get(key);
    if (hit && age < this.ttlMs + (this.opts.staleMs ?? 0)) {
      if (!pending) this.refresh(key, load).catch((err) => this.log.debug(`refresh of "${key}" failed: ${err}`));
      return hit.value;
    }
    if (pending) return pending;
    return this.refresh(key, load);
  }

  private refresh(key: string, load: () => Promise<T>): Promise<T> {
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
