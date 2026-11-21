import 'package:flutter/material.dart';

import 'tokens.dart';

bool _isMy(BuildContext context) => Localizations.maybeLocaleOf(context)?.languageCode == 'my';
bool _isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// Button styles. Pills; primary 52 high, secondary 44.
/// Navy and outline take their colours from the theme (navy in light, lavender in dark).
class E360Buttons {
  E360Buttons._();

  static const StadiumBorder _pill = StadiumBorder();
  static const TextStyle _label = TextStyle(fontWeight: FontWeight.w700, fontSize: 16);

  /// The single main action of a screen.
  static ButtonStyle get gold => FilledButton.styleFrom(
        backgroundColor: E360Colors.gold,
        foregroundColor: E360Colors.goldInk,
        minimumSize: const Size(88, 52),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: _pill,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _label,
      );

  /// Other primary actions.
  static ButtonStyle get navy => FilledButton.styleFrom(
        minimumSize: const Size(88, 52),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: _pill,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _label,
      );

  /// Secondary actions.
  static ButtonStyle get outline => OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: _pill,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _label.copyWith(fontSize: 14),
      );
}

enum E360BadgeKind { gold, neutral, success, dark }

/// Pill label. Uppercase with +0.04em tracking, except in Myanmar.
class E360Badge extends StatelessWidget {
  const E360Badge(this.label, {super.key, this.kind = E360BadgeKind.neutral});
  final String label;
  final E360BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final my = _isMy(context);
    final (Color bg, Color fg) = switch (kind) {
      E360BadgeKind.gold => (E360Colors.gold, E360Colors.goldInk),
      E360BadgeKind.neutral => dark ? (E360DarkColors.tint, E360DarkColors.ink) : (E360Colors.tint, E360Colors.night),
      E360BadgeKind.success =>
        dark ? (E360DarkColors.successBadgeBg, E360DarkColors.successBadgeInk) : (E360Colors.successBadgeBg, E360Colors.successBadgeInk),
      E360BadgeKind.dark => dark ? (E360DarkColors.navy, E360DarkColors.onNavy) : (E360Colors.night, Colors.white),
    };
    return _BadgeBox(label: label, bg: bg, fg: fg, my: my);
  }
}

class _BadgeBox extends StatelessWidget {
  const _BadgeBox({required this.label, required this.bg, required this.fg, required this.my, this.upper = true});
  final String label;
  final Color bg, fg;
  final bool my;
  final bool upper;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
        child: Text(
          my || !upper ? label : label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: my || !upper ? 0 : 0.48,
            height: my ? 1.5 : 1.3,
          ),
        ),
      );
}

/// Small rounded label, e.g. "Free" or "Sold out". Kept for source compatibility:
/// renders like [E360Badge] neutral, but keeps the label's case (existing screens and tests
/// rely on it). Only an error [color] keeps its meaning (danger tint).
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (color != null && color == Theme.of(context).colorScheme.error) {
      final dark = _isDark(context);
      return _BadgeBox(
        label: label,
        bg: dark ? E360DarkColors.dangerBg : E360Colors.dangerBg,
        fg: dark ? E360DarkColors.danger : E360Colors.danger,
        my: _isMy(context),
        upper: false,
      );
    }
    final dark = _isDark(context);
    return _BadgeBox(
      label: label,
      bg: dark ? E360DarkColors.tint : E360Colors.tint,
      fg: dark ? E360DarkColors.ink : E360Colors.night,
      my: _isMy(context),
      upper: false,
    );
  }
}

/// Bottom bar with a summary on the left and the main action on the right.
class PrimaryActionBar extends StatelessWidget {
  const PrimaryActionBar({super.key, required this.summary, required this.action});
  final Widget summary;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(children: [
              Expanded(child: summary),
              const SizedBox(width: 16),
              action,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Icon tile + title + optional subtitle (date, venue).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
          ]),
        ),
      ]),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: row);
  }
}

/// 44 px round +/- button for quantity steppers.
class StepperButton extends StatelessWidget {
  const StepperButton({super.key, required this.icon, this.onPressed, required this.semanticLabel});
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = enabled ? scheme.primary : (_isDark(context) ? E360DarkColors.disabledLine : E360Colors.disabledLine);
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: scheme.surface,
          shape: CircleBorder(side: BorderSide(color: color, width: 1.5)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// The Event 360 mark: navy rounded square with a gold dot. No logo file.
class E360Mark extends StatelessWidget {
  const E360Mark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: E360Colors.night, borderRadius: BorderRadius.circular(size * 9 / 28)),
          child: Container(
            width: size * 10 / 28,
            height: size * 10 / 28,
            decoration: const BoxDecoration(color: E360Colors.gold, shape: BoxShape.circle),
          ),
        ),
      );
}
