import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {Locale locale = const Locale('en'), bool dark = false}) => MaterialApp(
      theme: Event360Theme.light(locale: locale),
      darkTheme: Event360Theme.dark(locale: locale),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Localizations(
        locale: locale,
        delegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('light scheme primary is night, scaffold is paper', () {
    final t = Event360Theme.light();
    expect(t.colorScheme.primary, E360Colors.night);
    expect(t.scaffoldBackgroundColor, E360Colors.paper);
  });

  test('dark theme uses dark paper and lavender navy buttons', () {
    final t = Event360Theme.dark();
    expect(t.scaffoldBackgroundColor, E360DarkColors.paper);
    expect(t.colorScheme.primary, const Color(0xFF8F96E8));
  });

  testWidgets('gold FilledButton is >= 52 high with a stadium shape', (tester) async {
    await tester.pumpWidget(_app(FilledButton(style: E360Buttons.gold, onPressed: () {}, child: const Text('Go'))));
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(52));
    final style = E360Buttons.gold;
    expect(style.shape!.resolve({}), isA<StadiumBorder>());
  });

  testWidgets('outline button is 44 high pill', (tester) async {
    await tester.pumpWidget(_app(OutlinedButton(style: E360Buttons.outline, onPressed: () {}, child: const Text('Go'))));
    expect(tester.getSize(find.byType(OutlinedButton)).height, 44);
  });

  test('type scale: latin and Myanmar', () {
    final en = Event360Theme.light().textTheme;
    expect(en.headlineMedium!.fontSize, 28);
    expect(en.headlineMedium!.fontWeight, FontWeight.w800);
    expect(en.titleLarge!.fontSize, 20);
    expect(en.titleLarge!.fontWeight, FontWeight.w700);
    expect(en.titleMedium!.fontSize, 16);
    expect(en.bodyLarge!.fontSize, 15);
    expect(en.bodySmall!.fontSize, 13);
    expect(en.bodyLarge!.height, 1.55);
    final my = Event360Theme.light(locale: const Locale('my')).textTheme;
    expect(my.headlineMedium!.fontWeight, FontWeight.w700);
    expect(my.headlineMedium!.fontSize, 24);
    expect(my.headlineMedium!.height, 1.5);
    expect(my.titleLarge!.fontSize, 18);
    expect(my.bodyLarge!.height, 1.55);
    expect(my.headlineMedium!.fontFamilyFallback, contains(Event360Theme.myanmarFont));
  });

  testWidgets('StepperButton is 44x44 with its semantics label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(StepperButton(icon: Icons.add, onPressed: () {}, semanticLabel: 'One more Standing ticket')));
    expect(tester.getSize(find.byType(StepperButton)), const Size(44, 44));
    expect(find.bySemanticsLabel('One more Standing ticket'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('E360Badge uppercases in en, not in my', (tester) async {
    await tester.pumpWidget(_app(const E360Badge('Reserved seating')));
    expect(find.text('RESERVED SEATING'), findsOneWidget);
    await tester.pumpWidget(_app(const E360Badge('Reserved seating'), locale: const Locale('my')));
    expect(find.text('Reserved seating'), findsOneWidget);
    expect(find.text('RESERVED SEATING'), findsNothing);
    final t = tester.widget<Text>(find.text('Reserved seating'));
    expect(t.style!.letterSpacing, 0);
  });

  testWidgets('Pill renders neutral badge keeping case', (tester) async {
    await tester.pumpWidget(_app(const Pill('Free')));
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('InfoRow, PrimaryActionBar and E360Mark render without overflow', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [
      InfoRow(icon: Icons.place, title: 'Shwe Pyi Theatre', subtitle: 'Kamaryut, Yangon', onTap: () => tapped = true),
      const E360Mark(),
      PrimaryActionBar(summary: const Text('15,000 MMK'), action: FilledButton(style: E360Buttons.gold, onPressed: () {}, child: const Text('Choose seats'))),
    ])));
    await tester.tap(find.text('Shwe Pyi Theatre'));
    expect(tapped, isTrue);
    expect(tester.getSize(find.byType(E360Mark)), const Size(28, 28));
    expect(tester.takeException(), isNull);
  });

  test('text/background contrast pairs meet WCAG AA', () {
    const light = <(Color, Color, double)>[
      (E360Colors.ink, E360Colors.paper, 4.5),
      (E360Colors.ink, E360Colors.card, 4.5),
      (E360Colors.ink2, E360Colors.paper, 4.5),
      (E360Colors.muted, E360Colors.paper, 4.5),
      (E360Colors.muted, E360Colors.card, 4.5),
      (E360Colors.muted, E360Colors.tint, 4.5),
      (Colors.white, E360Colors.night, 4.5),
      (E360Colors.goldInk, E360Colors.gold, 4.5),
      (E360Colors.night, E360Colors.tint, 4.5),
      (E360Colors.success, E360Colors.paper, 4.5),
      (E360Colors.successBadgeInk, E360Colors.successBadgeBg, 4.5),
      (E360Colors.amberInk, E360Colors.paper, 4.5),
      (E360Colors.amberInk, E360Colors.amberBg, 4.5),
      (E360Colors.danger, E360Colors.paper, 4.5),
      (E360Colors.danger, E360Colors.dangerBg, 4.5),
    ];
    const dark = <(Color, Color, double)>[
      (E360DarkColors.ink, E360DarkColors.paper, 4.5),
      (E360DarkColors.ink, E360DarkColors.card, 4.5),
      (E360DarkColors.ink2, E360DarkColors.card, 4.5),
      (E360DarkColors.muted, E360DarkColors.paper, 4.5),
      (E360DarkColors.muted, E360DarkColors.card, 4.5),
      (E360DarkColors.onNavy, E360DarkColors.navy, 4.5),
      (E360DarkColors.navy, E360DarkColors.card, 4.5),
      (E360DarkColors.ink, E360DarkColors.tint, 4.5),
      (E360Colors.goldInk, E360Colors.gold, 4.5),
      (E360DarkColors.success, E360DarkColors.card, 4.5),
      (E360DarkColors.successBadgeInk, E360DarkColors.successBadgeBg, 4.5),
      (E360DarkColors.amberInk, E360DarkColors.card, 4.5),
      (E360DarkColors.amberInk, E360DarkColors.amberBg, 4.5),
      (E360DarkColors.danger, E360DarkColors.card, 4.5),
      (E360DarkColors.danger, E360DarkColors.dangerBg, 4.5),
    ];
    for (final (fg, bg, min) in [...light, ...dark]) {
      expect(_contrast(fg, bg), greaterThanOrEqualTo(min), reason: '$fg on $bg');
    }
  });
}
