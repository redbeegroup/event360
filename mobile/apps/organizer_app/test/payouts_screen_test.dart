import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/router.dart';
import 'package:organizer_app/l10n/app_localizations.dart';
import 'package:organizer_app/main.dart';

import 'widget_test.dart' hide main;

Finder key(String k) => find.byKey(Key(k));

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
}

Future<FakeApi> openPayouts(WidgetTester tester, {String role = 'ORG_OWNER', String lang = 'en', void Function(FakeApi)? setup}) async {
  final api = await pumpApp(tester, role: role, lang: lang, configure: setup);
  await openMenu(tester);
  await tester.tap(key('menuPayouts'));
  await tester.pumpAndSettle();
  return api;
}

String textOf(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  testWidgets('tiles show earned, paid out and owed; the organization is under the title', (tester) async {
    await openPayouts(tester);
    expect(textOf(tester, 'payoutTile-earned'), '1,500,000 MMK');
    expect(textOf(tester, 'payoutTile-paidOut'), '900,000 MMK');
    expect(textOf(tester, 'payoutTile-owed'), '600,000 MMK');
    expect(find.text('Owed to you'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Payouts')), findsOneWidget);
    expect(textOf(tester, 'payoutsOrg'), 'Yangon Live');
    expect(find.text('Record payout'), findsNothing);
  });

  testWidgets('negative owed reads "You owe Event 360" with the absolute amount', (tester) async {
    await openPayouts(tester, setup: (a) => a.payoutData = {...a.payoutsFor('o1'), 'owedMmk': -120000});
    expect(textOf(tester, 'payoutTile-owed'), 'You owe Event 360 120,000 MMK');
    expect(find.text('Owed to you'), findsNothing);
    expect(find.textContaining('-120'), findsNothing);
  });

  testWidgets('the reconcile note shows only when the totals do not reconcile', (tester) async {
    await openPayouts(tester, setup: (a) => a.payoutData = {...a.payoutsFor('o1'), 'reconciled': false});
    expect(key('reconcileNote'), findsOneWidget);
    expect(textOf(tester, 'reconcileNote'), 'This is a sales breakdown; totals come from the ledger.');
  });

  testWidgets('no note when reconciled', (tester) async {
    await openPayouts(tester);
    expect(key('reconcileNote'), findsNothing);
  });

  testWidgets('event row shows the net and expands to lines that add up to it', (tester) async {
    await openPayouts(tester);
    expect(find.text('Inya Lake Live'), findsOneWidget);
    expect(textOf(tester, 'payoutNet-pe1'), '1,500,000 MMK');
    expect(find.text('Sales before refunds'), findsNothing);
    await tester.tap(key('payoutEvent-pe1'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'payoutLine-gross-pe1'), '1,600,000 MMK');
    expect(textOf(tester, 'payoutLine-refunds-pe1'), '− 20,000 MMK');
    expect(textOf(tester, 'payoutLine-commission-pe1'), '− 80,000 MMK');
    expect(textOf(tester, 'payoutLine-net-pe1'), '1,500,000 MMK');
    expect(textOf(tester, 'payoutLine-discounts-pe1'), '100,000 MMK');
    for (final label in ['Sales before refunds', 'Refunded', 'Commission', 'Net to you', 'Discounts given (already taken off sales)']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Discounts come last and are not part of the sum
    final y = [for (final id in ['gross', 'refunds', 'commission', 'net', 'discounts']) tester.getTopLeft(key('payoutLine-$id-pe1')).dy];
    expect(y, orderedEquals([...y]..sort()));
    int n(String id) => int.parse(textOf(tester, 'payoutLine-$id-pe1').replaceAll(RegExp(r'[^0-9]'), ''));
    expect(n('gross') - n('refunds') - n('commission'), n('net'), reason: 'the displayed lines sum to the displayed net');
  });

  testWidgets('a debt is labelled Balance and reads "You owe Event 360"', (tester) async {
    await openPayouts(tester, setup: (a) => a.payoutData = {...a.payoutsFor('o1'), 'owedMmk': -120000});
    expect(find.text('Balance'), findsOneWidget);
    expect(textOf(tester, 'payoutTile-owed'), 'You owe Event 360 120,000 MMK');
  });

  test('Myanmar: payouts and paid out differ from payments and paid', () {
    final my = lookupL10n(const Locale('my')), en = lookupL10n(const Locale('en'));
    expect(my.payouts, isNot(my.payments));
    expect(my.paidOut, isNot(my.filterPaid));
    expect(my.payoutHistory, isNot(my.payments));
    expect(en.payouts, isNot(en.payments));
  });

  testWidgets('history rows show date, amount, method, reference and note', (tester) async {
    await openPayouts(tester);
    final row = key('payoutRow-pp1');
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    for (final s in ['500,000 MMK', '10 Nov 2026 · Bank transfer', 'Reference: TRX-1001', 'First instalment']) {
      expect(find.descendant(of: row, matching: find.text(s)), findsOneWidget, reason: s);
    }
    expect(find.descendant(of: key('payoutRow-pp2'), matching: find.textContaining('KBZPay')), findsOneWidget);
    expect(find.descendant(of: key('payoutRow-pp2'), matching: find.textContaining('Reference')), findsNothing);
  });

  testWidgets('a voided payout is struck through with Voided and its reason', (tester) async {
    await openPayouts(tester);
    final row = key('payoutRow-pp3');
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    final amount = tester.widget<Text>(find.descendant(of: row, matching: find.text('250,000 MMK')));
    expect(amount.style?.decoration, TextDecoration.lineThrough);
    expect(find.descendant(of: row, matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').toLowerCase() == 'voided')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Paid twice by mistake')), findsOneWidget);
    final normal = tester.widget<Text>(find.descendant(of: key('payoutRow-pp1'), matching: find.text('500,000 MMK')));
    expect(normal.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('empty summary says no sales and no payouts yet', (tester) async {
    await openPayouts(tester, setup: (a) => a.payoutData = {'earnedMmk': 0, 'paidOutMmk': 0, 'owedMmk': 0, 'reconciled': true, 'events': [], 'payouts': []});
    expect(find.text('No sales yet'), findsOneWidget);
    expect(find.text('No payouts yet.'), findsOneWidget);
  });

  testWidgets('owner and finance see the menu entry, a manager does not', (tester) async {
    for (final role in ['ORG_OWNER', 'ORG_FINANCE']) {
      await pumpApp(tester, role: role);
      await openMenu(tester);
      expect(key('menuPayouts'), findsOneWidget, reason: role);
      await tester.pumpWidget(const SizedBox());
    }
    await pumpApp(tester, role: 'ORG_MANAGER');
    await openMenu(tester);
    expect(key('menuPayouts'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('/payouts as a manager lands on the events list', (tester) async {
    await pumpApp(tester, role: 'ORG_MANAGER');
    final router = ProviderScope.containerOf(tester.element(find.byType(OrganizerApp))).read(routerProvider);
    router.go('/payouts');
    await tester.pumpAndSettle();
    expect(find.text('Inya Lake Live o1'), findsOneWidget);
    expect(key('payoutTile-earned'), findsNothing);
  });

  testWidgets('after switching to an organization where the user is only a manager, /payouts redirects and the entry goes', (tester) async {
    await pumpApp(tester, configure: (a) => a.managerOrgs = {'o2'});
    await openMenu(tester);
    expect(key('menuPayouts'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(key('orgPicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandalay Arts').last);
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(key('menuPayouts'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final router = ProviderScope.containerOf(tester.element(find.byType(OrganizerApp))).read(routerProvider);
    router.go('/payouts');
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/');
    expect(key('payoutTile-earned'), findsNothing);
  });

  testWidgets('switching organization and reopening shows the other organization', (tester) async {
    final api = await openPayouts(tester);
    expect(textOf(tester, 'payoutTile-earned'), '1,500,000 MMK');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(key('orgPicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandalay Arts').last);
    await tester.pumpAndSettle();
    await openMenu(tester);
    await tester.tap(key('menuPayouts'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'payoutTile-earned'), '777,000 MMK');
    expect(textOf(tester, 'payoutsOrg'), 'Mandalay Arts');
    expect(find.text('Mandalay Night Market'), findsOneWidget);
    expect(api.payoutCalls, ['o1', 'o2']);
  });

  testWidgets('reopening fetches again', (tester) async {
    final api = await openPayouts(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openMenu(tester);
    await tester.tap(key('menuPayouts'));
    await tester.pumpAndSettle();
    expect(api.payoutCalls, ['o1', 'o1']);
  });

  testWidgets('pull to refresh fetches again', (tester) async {
    final api = await openPayouts(tester);
    expect(api.payoutCalls.length, 1);
    await tester.fling(key('payoutsList'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(api.payoutCalls.length, 2);
    expect(textOf(tester, 'payoutTile-earned'), '1,500,000 MMK');
  });

  testWidgets('a failed refresh keeps the earlier numbers and says so', (tester) async {
    final api = await openPayouts(tester);
    api.failPayoutsOnce = true;
    await tester.fling(key('payoutsList'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't refresh. Showing earlier data."), findsOneWidget);
    expect(textOf(tester, 'payoutTile-earned'), '1,500,000 MMK');
  });

  testWidgets('a load error shows the retry state, and Retry loads', (tester) async {
    final api = await pumpApp(tester, configure: (a) => a.failPayoutsOnce = true);
    await openMenu(tester);
    await tester.tap(key('menuPayouts'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load. Check your connection."), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.payoutCalls.length, 2);
    expect(textOf(tester, 'payoutTile-earned'), '1,500,000 MMK');
  });

  testWidgets('Myanmar: the screen reads in Myanmar', (tester) async {
    await openPayouts(tester, lang: 'my', setup: (a) => a.payoutData = {...a.payoutsFor('o1'), 'owedMmk': -5000, 'reconciled': false});
    expect(find.text('ရရှိငွေ'), findsOneWidget);
    expect(find.text('ထုတ်ပေးပြီးငွေ'), findsOneWidget);
    expect(textOf(tester, 'payoutTile-owed'), contains('Event 360'));
    expect(key('reconcileNote'), findsOneWidget);
  });
}
