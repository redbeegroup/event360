library event360_ui;

import 'package:flutter/material.dart';

import 'src/tokens.dart';

export 'src/seat_layout.dart';
export 'src/seat_map_painter.dart';
export 'src/tokens.dart';
export 'src/widgets.dart';

/// Event 360 look: navy + gold on cool paper, Bricolage Grotesque titles, Figtree body,
/// Myanmar-safe line heights.
class Event360Theme {
  static const Color brand = E360Colors.night;
  static const String myanmarFont = E360Fonts.myanmar;

  static ThemeData light({Locale? locale}) => _build(Brightness.light, locale);
  static ThemeData dark({Locale? locale}) => _build(Brightness.dark, locale);

  static ColorScheme _scheme(Brightness b) {
    if (b == Brightness.light) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: E360Colors.night,
        onPrimary: Colors.white,
        secondary: E360Colors.gold,
        onSecondary: E360Colors.goldInk,
        tertiary: E360Colors.ink2,
        onTertiary: Colors.white,
        error: E360Colors.danger,
        onError: Colors.white,
        surface: E360Colors.card,
        onSurface: E360Colors.ink,
        onSurfaceVariant: E360Colors.muted,
        outline: E360Colors.muted,
        outlineVariant: E360Colors.line,
        surfaceContainerLowest: E360Colors.card,
        surfaceContainerLow: E360Colors.card,
        surfaceContainer: E360Colors.paper,
        surfaceContainerHigh: E360Colors.tint,
        surfaceContainerHighest: E360Colors.tint,
        primaryContainer: E360Colors.tint,
        onPrimaryContainer: E360Colors.night,
        secondaryContainer: E360Colors.tint,
        onSecondaryContainer: E360Colors.night,
        errorContainer: E360Colors.dangerBg,
        onErrorContainer: E360Colors.danger,
      );
    }
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: E360DarkColors.navy,
      onPrimary: E360DarkColors.onNavy,
      secondary: E360Colors.gold,
      onSecondary: E360Colors.goldInk,
      tertiary: E360DarkColors.ink2,
      onTertiary: E360DarkColors.paper,
      error: E360DarkColors.danger,
      onError: E360DarkColors.paper,
      surface: E360DarkColors.card,
      onSurface: E360DarkColors.ink,
      onSurfaceVariant: E360DarkColors.muted,
      outline: E360DarkColors.muted,
      outlineVariant: E360DarkColors.line,
      surfaceContainerLowest: E360DarkColors.paper,
      surfaceContainerLow: E360DarkColors.card,
      surfaceContainer: E360DarkColors.card,
      surfaceContainerHigh: E360DarkColors.tint,
      surfaceContainerHighest: E360DarkColors.tint,
      primaryContainer: E360DarkColors.tint,
      onPrimaryContainer: E360DarkColors.ink,
      secondaryContainer: E360DarkColors.tint,
      onSecondaryContainer: E360DarkColors.ink,
      errorContainer: E360DarkColors.dangerBg,
      onErrorContainer: E360DarkColors.danger,
    );
  }

  static TextTheme _text(Brightness b, bool my) {
    final dark = b == Brightness.dark;
    final ink = dark ? E360DarkColors.ink : E360Colors.ink;
    final ink2 = dark ? E360DarkColors.ink2 : E360Colors.ink2;
    final muted = dark ? E360DarkColors.muted : E360Colors.muted;
    const fallback = [E360Fonts.myanmar];
    // Myanmar: weight 700 where Latin uses 800, titles one step smaller at 1.5 line height.
    final w800 = my ? FontWeight.w700 : FontWeight.w800;
    TextStyle display(double size, FontWeight w, double h, Color c) =>
        TextStyle(fontFamily: E360Fonts.display, fontFamilyFallback: fallback, fontSize: size, fontWeight: w, height: h, color: c, letterSpacing: my ? 0 : -0.01 * size);
    TextStyle body(double size, FontWeight w, double h, Color c) =>
        TextStyle(fontFamily: E360Fonts.body, fontFamilyFallback: fallback, fontSize: size, fontWeight: w, height: h, color: c);
    return TextTheme(
      displayLarge: display(40, w800, my ? 1.5 : 1.1, ink),
      displayMedium: display(34, w800, my ? 1.5 : 1.15, ink),
      displaySmall: display(30, w800, my ? 1.5 : 1.15, ink),
      headlineLarge: display(my ? 28 : 32, w800, my ? 1.5 : 1.15, ink),
      headlineMedium: display(my ? 24 : 28, w800, my ? 1.5 : 1.15, ink),
      headlineSmall: display(my ? 20 : 22, FontWeight.w700, my ? 1.5 : 1.2, ink),
      titleLarge: display(my ? 18 : 20, FontWeight.w700, my ? 1.5 : 1.25, ink),
      titleMedium: body(16, FontWeight.w700, my ? 1.55 : 1.3, ink),
      titleSmall: body(14, FontWeight.w700, my ? 1.55 : 1.3, ink),
      bodyLarge: body(15, FontWeight.w400, 1.55, ink2),
      bodyMedium: body(14, FontWeight.w400, 1.55, ink2),
      bodySmall: body(13, FontWeight.w400, 1.55, muted),
      labelLarge: body(15, FontWeight.w700, my ? 1.5 : 1.25, ink),
      labelMedium: body(13, FontWeight.w600, my ? 1.5 : 1.25, ink),
      labelSmall: body(12, FontWeight.w700, my ? 1.5 : 1.25, muted),
    );
  }

  static ThemeData _build(Brightness b, Locale? locale) {
    final my = locale?.languageCode == 'my';
    final dark = b == Brightness.dark;
    final scheme = _scheme(b);
    final paper = dark ? E360DarkColors.paper : E360Colors.paper;
    final text = _text(b, my);
    const pill = StadiumBorder();
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: scheme.outlineVariant,
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // Slim bar like the event page's pinned bar: surface with a 1 px line under it
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        titleTextStyle: text.titleMedium,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primary,
        side: BorderSide.none,
        labelStyle: text.labelMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: pill,
          textStyle: text.labelLarge?.copyWith(fontSize: 16, color: null),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: pill,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          textStyle: text.labelLarge?.copyWith(color: null, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge?.copyWith(color: null, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
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
