import type { PaymentProviderCode } from '@prisma/client';

/** What the client does to pay (stored on Payment.action and returned to the app). */
export interface PaymentAction {
  type: 'REDIRECT' | 'DEEPLINK' | 'QR';
  url?: string; // web checkout page
  deeplink?: string; // opens the wallet app
  qr?: string; // text to render as a QR (scan with the wallet app)
  returnUrl?: string;
}

export interface CreateContext {
  paymentId: string; // our merchant order id (unique per attempt)
  orderId: string;
  amountMmk: bigint;
  title: string; // shown in the wallet
  expiresAt: Date;
  notifyUrl: string; // our webhook
  returnUrl?: string; // where the buyer goes after paying (web)
  channel: 'APP' | 'WEB';
}

export interface CreateResult {
  providerRef: string;
  action: PaymentAction;
}

export type ProviderStatus = 'SUCCEEDED' | 'FAILED' | 'PENDING' | 'EXPIRED';

export interface VerifiedCallback {
  /** Our payment id (merchant order id) the provider echoes back. */
  paymentId?: string;
  providerRef?: string;
  status: ProviderStatus;
  amountMmk?: bigint;
}

export class InvalidSignatureError extends Error {}

export interface PaymentProvider {
  readonly code: PaymentProviderCode;
  readonly label: string;
  /** Configured and switched on. */
  available(): Promise<boolean>;
  create(ctx: CreateContext): Promise<CreateResult>;
  /** Throws InvalidSignatureError when the callback isn't authentic. */
  verifyCallback(headers: Record<string, string | string[] | undefined>, body: unknown): Promise<VerifiedCallback>;
  /** Body the provider expects back from our webhook. */
  callbackAck(): { contentType: string; body: string };
  query(p: { paymentId: string; providerRef: string | null; createdAt: Date }): Promise<ProviderStatus>;
  /** Undefined → refunds are done by hand (RefundStatus.MANUAL). */
  refund?(p: { paymentId: string; providerRef: string | null; amountMmk: bigint; refundId: string; reason: string }): Promise<{ providerRef?: string }>;
}
