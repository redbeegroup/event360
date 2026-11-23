import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'widget_test.dart' hide main;

const _wrong = 'Something went wrong. Try again.';
Finder key(String k) => find.byKey(Key(k));

Future<FakeApi> openTab(WidgetTester t, String tab, {void Function(FakeApi)? configure}) async {
  final api = await pumpApp(t, configure: configure);
  await t.tap(find.text('Inya Lake Live o1'));
  await t.pumpAndSettle();
  await t.ensureVisible(key(tab));
  await t.pumpAndSettle();
  await t.tap(key(tab));
  await t.pumpAndSettle();
  return api;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  // Every action failure ends with a visible sentence, whatever was thrown.
  final failures = <String, Object>{
    'a 500': ApiException(500, 'Internal server error'),
    'an unexpected error': StateError('boom'),
  };

  for (final MapEntry(key: name, value: error) in failures.entries) {
    group('failing with $name', () {
      testWidgets('Promos: create says so', (tester) async {
        await openTab(tester, 'tabPromos', configure: (a) => a.actionError = error);
        await tester.enterText(key('promoCode'), 'EARLY20');
        await tester.enterText(key('promoValue'), '20');
        await tester.tap(key('createPromo'));
        await tester.pumpAndSettle();
        expect(find.text(_wrong), findsOneWidget);
        expect(tester.widget<FilledButton>(key('createPromo')).onPressed, isNotNull, reason: 'not stuck busy');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Promos: turn off says so', (tester) async {
        final api = await openTab(tester, 'tabPromos', configure: (a) => a.promos.add({'id': 'p0', 'code': 'EARLY20', 'kind': 'PERCENT', 'value': 20, 'maxUses': null, 'used': 0, 'isActive': true, 'orders': 0, 'discountGivenMmk': 0}));
        api.actionError = error;
        await tester.tap(find.text('Turn off'));
        await tester.pumpAndSettle();
        expect(find.text(_wrong), findsOneWidget);
        expect(find.text('EARLY20 · 20%'), findsOneWidget, reason: 'still on');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Announce: send says so', (tester) async {
        await openTab(tester, 'tabAnnounce', configure: (a) => a.actionError = error);
        await tester.enterText(key('annTitle'), 'Gates open at 4');
        await tester.enterText(key('annBody'), 'Bring your QR code.');
        await tester.tap(key('sendAnnouncement'));
        await tester.pumpAndSettle();
        await tester.tap(key('confirmSend'));
        await tester.pumpAndSettle();
        expect(find.text(_wrong), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Door: create code says so', (tester) async {
        await openTab(tester, 'tabDoor', configure: (a) => a.actionError = error);
        await tester.enterText(key('codeLabel'), 'Volunteers for the north side entrance');
        await tester.ensureVisible(key('createCode'));
        await tester.pumpAndSettle();
        await tester.tap(key('createCode'));
        await tester.pumpAndSettle();
        expect(find.text(_wrong), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Door: revoke code says so', (tester) async {
        final api = await openTab(tester, 'tabDoor', configure: (a) => a.codes.add({'id': 'c0', 'label': 'Volunteers', 'gate': null, 'expiresAt': '2099-01-15T10:30:00.000Z', 'devices': 0, 'active': true}));
        api.actionError = error;
        await tester.tap(find.text('Revoke'));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Revoke')));
        await tester.pumpAndSettle();
        expect(find.text(_wrong), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}
