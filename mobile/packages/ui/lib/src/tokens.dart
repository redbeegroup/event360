import 'package:flutter/material.dart';

/// Event 360 colour tokens (light). Names match the design spec token table.
class E360Colors {
  E360Colors._();

  /// Brand navy: primary buttons, selected states.
  static const Color night = Color(0xFF1B1E4B);

  /// The one main action on a screen, highlight badges.
  static const Color gold = Color(0xFFF2B632);

  /// Text on gold.
  static const Color goldInk = Color(0xFF3B2A00);

  /// Page background.
  static const Color paper = Color(0xFFF7F8FC);

  /// Cards, bars, sheets.
  static const Color card = Color(0xFFFFFFFF);

  /// Main text.
  static const Color ink = Color(0xFF15172E);

  /// Body paragraphs.
  static const Color ink2 = Color(0xFF33364F);

  /// Secondary text.
  static const Color muted = Color(0xFF555A78);

  /// Borders and dividers.
  static const Color line = Color(0xFFDDE0EE);

  /// Neutral chips, selected rows.
  static const Color tint = Color(0xFFE9EAF5);

  /// Success text used inline, e.g. "Free".
  static const Color success = Color(0xFF1F6F5C);

  /// Success badge text (on [successBadgeBg]).
  static const Color successBadgeInk = Color(0xFF14594A);
  static const Color successBadgeBg = Color(0xFFD9F2E9);

  /// Scarcity lines such as "48 tickets left".
  static const Color amberInk = Color(0xFF8A4B00);

  /// Errors.
  static const Color danger = Color(0xFFB42318);

  /// Light tint behind danger text.
  static const Color dangerBg = Color(0xFFFDE8E6);

  /// Disabled outline (stepper at its limit).
  static const Color disabledLine = Color(0xFFC5C8DC);
}

/// Dark-mode counterparts (spec decision 10). Gold stays the main action.
class E360DarkColors {
  E360DarkColors._();

  static const Color paper = Color(0xFF111326);
  static const Color card = Color(0xFF1A1D38);
  static const Color ink = Color(0xFFEEF0FA);
  static const Color ink2 = Color(0xFFC9CDE6);
  static const Color muted = Color(0xFFA6ABC8);
  static const Color line = Color(0xFF2C3054);
  static const Color tint = Color(0xFF262A52);

  /// Navy filled buttons become this in dark mode, with [onNavy] text.
  static const Color navy = Color(0xFF8F96E8);
  static const Color onNavy = Color(0xFF111326);

  static const Color success = Color(0xFF5FD0B0);
  static const Color successBadgeInk = Color(0xFFA7ECD6);
  static const Color successBadgeBg = Color(0xFF123D33);
  static const Color amberInk = Color(0xFFF2B632);
  static const Color danger = Color(0xFFFF8A80);
  static const Color dangerBg = Color(0xFF3A1F26);
  static const Color disabledLine = Color(0xFF3F4470);
}

/// Font family names (bundled in this package, see pubspec.yaml).
class E360Fonts {
  E360Fonts._();
  static const String display = 'packages/event360_ui/BricolageGrotesque';
  static const String body = 'packages/event360_ui/Figtree';
  static const String myanmar = 'packages/event360_ui/NotoSansMyanmar';
}
