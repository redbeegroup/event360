import type { PaymentsService } from '../src/modules/payments/payments.service';
import type { PrismaService } from '../src/modules/prisma/prisma.service';

/**
 * Expires one order's hold now, the way the sweeper does. The sweeper takes expired holds in batches of 200 and
 * other suites leave holds behind, so it sweeps until this order has left PENDING_PAYMENT.
 */
export async function expireHold(prisma: PrismaService, svc: PaymentsService, orderId: string): Promise<void> {
  await prisma.order.update({ where: { id: orderId }, data: { holdExpiresAt: new Date(Date.now() - 1000) } });
  for (let i = 0; i < 50; i++) {
    await svc.sweep();
    const o = await prisma.order.findUniqueOrThrow({ where: { id: orderId }, select: { status: true } });
    if (o.status !== 'PENDING_PAYMENT') return;
  }
  throw new Error(`hold of order ${orderId} did not expire`);
}
