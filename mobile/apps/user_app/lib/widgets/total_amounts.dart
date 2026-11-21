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
