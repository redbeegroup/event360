library event360_ui;

import 'package:flutter/material.dart';

export 'src/seat_layout.dart';
export 'src/seat_map_painter.dart';

/// Event 360 look: one brand violet, warm neutrals, Myanmar-safe line heights.
class Event360Theme {
  static const Color brand = Color(0xFF6C2BD9);
  static const String myanmarFont = 'packages/event360_ui/NotoSansMyanmar';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    // Myanmar glyphs stack vertically; give text more line height and fall back to the bundled font.
    final text = base.textTheme.apply(fontFamilyFallback: const [myanmarFont]).copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.55, fontFamilyFallback: const [myanmarFont]),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55, fontFamilyFallback: const [myanmarFont]),
        );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: scheme.surface, scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: base.chipTheme.copyWith(shape: const StadiumBorder()),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Small rounded label, e.g. "Free" or "Sold out".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Centered message with an optional retry button (empty states and errors).
class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}
