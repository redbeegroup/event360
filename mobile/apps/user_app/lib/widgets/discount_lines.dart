import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';

/// "Price rises to X on DATE" for a ticket type with a scheduled next price (hidden for free types and when none is set).
String? priceRiseText(L10n t, String lang, int priceMmk, NextPrice? next) =>
    next == null || priceMmk == 0 ? null : t.priceRisesTo(t.mmk(formatAmount(next.priceMmk, lang)), formatEventDate(next.startsAt, lang));

/// 1000 → "10", 750 → "7.5".
String percentText(int bp) => (bp / 100).toString().replaceFirst(RegExp(r'\.0$'), '');

/// The discount lines under the ticket choice: "Group discount −X" when it applies, "Buy N+ tickets to save Y%" while a
/// tier is not reached yet, and why a valid promo code is not applied when the group discount is bigger.
class DiscountLines extends StatelessWidget {
  const DiscountLines({super.key, required this.view, required this.lang});
  final DiscountView view;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final next = view.nextTier;
    final groupApplies = view.source == 'GROUP' && view.discountMmk > 0;
    if (!groupApplies && next == null && !view.promoLost) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (groupApplies)
          Text(t.groupDiscountLine(t.mmk(formatAmount(view.discountMmk, lang))),
              key: const Key('groupDiscountLine'), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        if (view.promoLost) Text(t.promoLostToGroup, key: const Key('promoLostNote'), style: theme.textTheme.bodySmall),
        if (next != null) Text(t.groupDiscountHint(next.minQuantity, percentText(next.percentBp)), key: const Key('groupDiscountHint'), style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
