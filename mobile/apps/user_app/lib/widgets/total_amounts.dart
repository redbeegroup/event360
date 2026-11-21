import 'package:flutter/material.dart';

/// A total, with the struck-through price before a discount on its own line above it. Long amounts (Myanmar
/// digits and units on a narrow phone) scale down instead of overflowing the row.
class TotalAmounts extends StatelessWidget {
  const TotalAmounts({super.key, required this.total, this.original, this.totalKey});
  final String total;
  final String? original;
  final Key? totalKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fit(Widget w) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: w);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (original != null) fit(Text(original!, style: theme.textTheme.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough))),
      fit(Text(total, key: totalKey, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
    ]);
  }
}

/// A total row: [label] on the left, the amounts on the right. The amounts take the room they need (up to 70% of
/// the row) and only shrink when even that is too little; the label takes the rest and wraps if it must.
class TotalRow extends StatelessWidget {
  const TotalRow({super.key, required this.label, required this.total, this.original, this.totalKey});
  final Widget label;
  final String total;
  final String? original;
  final Key? totalKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(child: label),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.7),
            child: TotalAmounts(total: total, original: original, totalKey: totalKey),
          ),
        ]),
      );
}
