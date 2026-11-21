/// Group discounts, worked out on the phone so the buyer sees them before ordering. The API's order response is
/// authoritative; this uses the same rules (paid-type tickets only, half-up rounding, the larger of group and promo).
library;

import 'models.dart';
import 'orders.dart';

/// The best tier percentage (basis points) reached by [paidQty] paid-type tickets; 0 when none is.
int bestGroupBp(List<GroupTier> tiers, int paidQty) {
  var best = 0;
  for (final t in tiers) {
    if (paidQty >= t.minQuantity && t.percentBp > best) best = t.percentBp;
  }
  return best;
}

/// The nearest tier above [paidQty] that saves more than the tier already reached, or null.
GroupTier? nextGroupTier(List<GroupTier> tiers, int paidQty) {
  final reached = bestGroupBp(tiers, paidQty);
  GroupTier? next;
  for (final t in tiers) {
    if (t.minQuantity > paidQty && t.percentBp > reached && (next == null || t.minQuantity < next.minQuantity)) next = t;
  }
  return next;
}

/// Half-up percentage of [paidSubtotalMmk], like the API: (base * bp + 5000) / 10000.
int groupDiscountMmk(List<GroupTier> tiers, int paidQty, int paidSubtotalMmk) {
  final bp = bestGroupBp(tiers, paidQty);
  return bp == 0 ? 0 : (paidSubtotalMmk * bp + 5000) ~/ 10000;
}

/// What the buyer is shown for the chosen tickets: which discount applies and the total after it.
class DiscountView {
  const DiscountView({required this.source, required this.discountMmk, required this.totalMmk, required this.promoLost, required this.nextTier});

  /// GROUP, PROMO or null.
  final String? source;
  final int discountMmk;
  final int totalMmk;

  /// A valid code was entered but the group discount is bigger, so the code is not applied.
  final bool promoLost;

  /// The tier the buyer has not reached yet ("Buy N+ tickets to save Y%"), if any.
  final GroupTier? nextTier;
}

/// [paidQty] and [paidSubtotalMmk] count paid-type tickets only; [totalMmk] is the undiscounted total of all chosen tickets.
/// With a checked promo ([promo] valid) the server's answer is used as is; otherwise the group discount is worked out here.
DiscountView resolveDiscount({
  required List<GroupTier> tiers,
  required int paidQty,
  required int paidSubtotalMmk,
  required int totalMmk,
  PromoCheck? promo,
}) {
  final next = paidQty > 0 ? nextGroupTier(tiers, paidQty) : null;
  if (promo != null && promo.valid) {
    final source = promo.discountSource ?? (promo.discountMmk > 0 ? 'PROMO' : null);
    return DiscountView(source: source, discountMmk: promo.discountMmk, totalMmk: promo.totalMmk, promoLost: !promo.promoApplied, nextTier: next);
  }
  final d = groupDiscountMmk(tiers, paidQty, paidSubtotalMmk);
  return DiscountView(source: d > 0 ? 'GROUP' : null, discountMmk: d, totalMmk: totalMmk - d, promoLost: false, nextTier: next);
}
