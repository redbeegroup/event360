import type { PayoutLabels } from '../components/PayoutAdmin';
import type { t } from './i18n';

/** The admin record-payout / void labels, in the current language. */
export function payoutLabels(tr: Awaited<ReturnType<typeof t>>): PayoutLabels {
  const methods = Object.fromEntries(['BANK', 'KBZPAY', 'WAVEPAY', 'CASH', 'OTHER'].map((m) => [m, String((tr as Record<string, unknown>)[`pyMethod${m}`])]));
  return {
    record: tr.pyRecord, amount: tr.pyAmount, paidAt: tr.pyDate, method: tr.pyMethod, reference: tr.pyReference, note: tr.note,
    review: tr.pyReview, confirmLine: tr.pyConfirmLine, confirm: tr.pyConfirm, back: tr.pyBack, overWarn: tr.pyOverWarn,
    recorded: tr.pyRecorded, newOwed: tr.pyNewOwed, newOwing: tr.pyNewOwing, voidBtn: tr.pyVoidBtn, voidReasonPh: tr.pyVoidReasonPh,
    voidConfirm: tr.pyVoidConfirm, voidDone: tr.pyVoidDone, alreadyVoided: tr.pyAlreadyVoided, methods,
    currency: tr.lang === 'my' ? 'ကျပ်' : 'MMK', locale: tr.lang === 'my' ? 'my-MM' : 'en-US',
  };
}
