import type { Prisma } from '@prisma/client';
import type { PrismaService } from '../src/modules/prisma/prisma.service';

/**
 * Lock-order tests. `lockGate` opens a transaction that holds row locks (taken by `lock`) until `release()`;
 * `done` settles when it ends (errors swallowed: a failed gate must not leave an unhandled rejection).
 * `queued` waits until a backend (other than `except`) is blocked by any of `blockers` and returns its pid.
 */
export async function lockGate(prisma: PrismaService, lock: (tx: Prisma.TransactionClient) => Promise<unknown>) {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  let ready!: () => void;
  const locked = new Promise<void>((r) => (ready = r));
  let pid = 0;
  const tx = prisma.$transaction(
    async (t) => {
      pid = (await t.$queryRaw<{ pid: number }[]>`SELECT pg_backend_pid() AS pid`)[0].pid;
      await lock(t);
      ready();
      await gate;
    },
    { timeout: 30_000 },
  );
  try {
    await Promise.race([locked, tx.then(() => Promise.reject(new Error('the gate ended before locking')))]);
  } catch (e) {
    release();
    throw e;
  }
  return { pid, release, done: tx.catch(() => undefined) };
}
export async function queued(prisma: PrismaService, blockers: number[], except: number[] = []): Promise<number> {
  for (let i = 0; i < 200; i++) {
    const rows = await prisma.$queryRaw<{ pid: number }[]>`
      SELECT pid FROM pg_stat_activity WHERE pg_blocking_pids(pid) && ${blockers}::int[] AND NOT (pid = ANY(${except}::int[]))`;
    if (rows.length) return rows[0].pid;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error('nothing queued behind the gate');
}
/**
 * Holds the gate's locks, starts `first` and waits until it queues behind the gate, then starts `second` and waits
 * until it queues behind the gate or `first`; then always releases the gate and returns both results.
 */
export async function gated<A, B>(
  prisma: PrismaService,
  lock: (tx: Prisma.TransactionClient) => Promise<unknown>,
  first: () => Promise<A>,
  second: () => Promise<B>,
): Promise<[A, B]> {
  const gate = await lockGate(prisma, lock);
  let a: Promise<A> | undefined;
  let b: Promise<B> | undefined;
  try {
    a = first();
    const aPid = await queued(prisma, [gate.pid]);
    b = second();
    await queued(prisma, [gate.pid, aPid], [aPid]);
  } catch (e) {
    void a?.catch(() => undefined);
    void b?.catch(() => undefined);
    throw e;
  } finally {
    gate.release();
    await gate.done;
  }
  return Promise.all([a, b]);
}

