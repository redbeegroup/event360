import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/format.dart';
import 'package:organizer_app/l10n/app_localizations.dart';
import 'package:organizer_app/screens/event/sales_tab.dart';

import 'widget_test.dart' hide main;

Finder key(String k) => find.byKey(Key(k));

Future<void> goSales(WidgetTester tester) async {
  await tester.ensureVisible(key('tabSales'));
  await tester.pumpAndSettle();
  await tester.tap(key('tabSales'));
  await tester.pumpAndSettle();
}

Future<void> goOverview(WidgetTester tester) async {
  await tester.ensureVisible(key('tabOverview'));
  await tester.pumpAndSettle();
  await tester.tap(key('tabOverview'));
  await tester.pumpAndSettle();
}

Future<void> goOrders(WidgetTester tester) async {
  await tester.tap(key('salesViewOrders'));
  await tester.pumpAndSettle();
}

/// Opens the Sales tab; on its Orders view unless [orders] is false (the default view is Summary).
Future<FakeApi> openSales(WidgetTester tester, {String role = 'ORG_OWNER', String lang = 'en', bool orders = true, void Function(FakeApi)? setup}) async {
  final api = await pumpApp(tester, role: role, lang: lang, configure: setup);
  await tester.tap(find.text('Inya Lake Live o1'));
  await tester.pumpAndSettle();
  await goSales(tester);
  if (orders) await goOrders(tester);
  return api;
}

Finder listScrollable() => find.descendant(of: key('orderList'), matching: find.byType(Scrollable)).first;

/// Rows (and the header and footer) the list was given; only a few are built.
int rowCount(WidgetTester tester) => tester.widget<ListView>(key('orderList')).childrenDelegate.estimatedChildCount! - 1;

ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(listScrollable()).position;

/// Scrolls the way a thumb does, 400 px at a time, until the list has asked for another page (or [steps] ran out).
Future<void> scrollForMore(WidgetTester tester, FakeApi api, {int steps = 120}) async {
  final before = api.orderCalls.length;
  for (var i = 0; i < steps && api.orderCalls.length == before; i++) {
    await tester.drag(listScrollable(), const Offset(0, -400));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// From the top, down to [target].
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  position(tester).jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 200, scrollable: listScrollable());
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, String id) => scrollTo(tester, key('orderRow-$id'));

Finder inRow(String id, String text) => find.descendant(of: key('orderRow-$id'), matching: find.text(text));

Finder inSheet(String text) => find.descendant(of: key('orderSheet'), matching: find.text(text));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  testWidgets('totals, caption and the paid ticket types with next price, sold of quota and revenue', (tester) async {
    final api = await openSales(tester, orders: false);
    expect(key('salesTotals'), findsOneWidget);
    expect(key('orderSearch'), findsNothing, reason: 'Summary is the default view');
    expect(tester.widget<Text>(key('paidOrders')).data, '43');
    expect(tester.widget<Text>(key('grossSales')).data, '700,000 MMK');
    expect(tester.widget<Text>(key('commission')).data, '35,000 MMK');
    expect(tester.widget<Text>(key('net')).data, '665,000 MMK');
    expect(tester.widget<Text>(key('refunded')).data, '2 · 50,000 MMK');
    expect(find.text('Paid orders only, after discounts'), findsOneWidget);
    expect(key('salesType-t2'), findsOneWidget);
    expect(key('salesType-t3'), findsOneWidget);
    expect(key('salesType-t1'), findsNothing, reason: 'free types are not listed');
    expect(find.text('Next price 40,000 MMK on ${formatDayTime(DateTime.utc(2026, 12, 1, 5), 'en')}'), findsOneWidget);
    expect(find.textContaining('Next price'), findsOneWidget, reason: 'only the scheduled type');
    expect(find.text('3 of 20 sold'), findsOneWidget);
    expect(find.text('40 of 200 sold'), findsOneWidget);
    expect(find.text('Revenue 100,000 MMK'), findsOneWidget);
    expect(api.salesCalls, 1, reason: '/sales is read once');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an event with no paid types says so and shows neither totals nor the order list', (tester) async {
    final api = await openSales(tester, orders: false, setup: (a) => a.sales = {...a.sales, 'ticketTypes': [], 'paidOrders': 0});
    expect(key('noPaidTickets'), findsOneWidget);
    expect(find.text('This event has no paid tickets'), findsOneWidget);
    expect(key('salesTotals'), findsNothing);
    // The Orders segment is still there and says there are none, without asking the API
    await goOrders(tester);
    expect(find.text('No orders yet'), findsOneWidget);
    expect(key('orderList'), findsNothing);
    expect(api.orderCalls, isEmpty);
    // Nothing to search or filter: no field and no chips, so nothing can start a request
    expect(key('orderSearch'), findsNothing);
    expect(key('orderFilter-paid'), findsNothing);
    await tester.drag(key('ordersEmpty'), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(api.orderCalls, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the first page is 30 orders, built lazily; scrolling loads each next page once, without duplicates', (tester) async {
    final api = await openSales(tester);
    expect(api.orderCalls, hasLength(1));
    expect(api.orderCalls.single, (status: null, q: null, cursor: null, limit: 30));
    expect(rowCount(tester), 30);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('orderRow-')).evaluate().length, lessThan(30));
    api.orderCalls.clear();
    await scrollForMore(tester, api);
    expect([for (final c in api.orderCalls) c.cursor], ['30']);
    expect(rowCount(tester), 60);
    await scrollForMore(tester, api);
    expect([for (final c in api.orderCalls) c.cursor], ['30', '60']);
    expect(rowCount(tester), 75);
    await scrollForMore(tester, api, steps: 40);
    expect(api.orderCalls, hasLength(2), reason: 'no cursor, no more requests');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row that two pages both return is listed once', (tester) async {
    final api = await openSales(tester);
    // Page 2 starts with the last row of page 1 again: rebuild the fake's data so cursor 30 repeats o030.
    api.ordersData.insert(30, api.ordersData[29]);
    await scrollForMore(tester, api);
    await scrollForMore(tester, api);
    expect(api.orderCalls, hasLength(3));
    expect(rowCount(tester), 75, reason: '76 rows from the API, one repeated');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a filter chip sends its status, clears the list and starts again from the first page', (tester) async {
    final api = await openSales(tester);
    await scrollForMore(tester, api);
    expect(rowCount(tester), 60);
    api.orderCalls.clear();
    position(tester).jumpTo(0);
    await tester.pump();
    await tester.ensureVisible(key('orderFilter-pending'));
    await tester.pumpAndSettle();
    await tester.tap(key('orderFilter-pending'));
    await tester.pumpAndSettle();
    expect(api.orderCalls.single, (status: 'pending', q: null, cursor: null, limit: 30));
    expect(rowCount(tester), 15);
    expect(tester.widget<FilterChip>(key('orderFilter-pending')).selected, isTrue);
    expect(tester.widget<FilterChip>(key('orderFilter-all')).selected, isFalse);
    final onPrimary = Theme.of(tester.element(key('orderFilter-pending'))).colorScheme.onPrimary;
    expect(tester.widget<FilterChip>(key('orderFilter-pending')).labelStyle?.color, onPrimary, reason: 'readable selected label');
    await reveal(tester, 'o005');
    expect(inRow('o005', 'WAITING FOR PAYMENT'), findsOneWidget);
    for (final f in ['paid', 'refunded', 'incomplete', 'all']) {
      position(tester).jumpTo(0);
      await tester.pump();
      await tester.ensureVisible(key('orderFilter-$f'));
      await tester.pumpAndSettle();
      await tester.tap(key('orderFilter-$f'));
      await tester.pumpAndSettle();
      expect(api.orderCalls.last.status, f == 'all' ? isNull : f);
      expect(api.orderCalls.last.cursor, isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing sends one request after the debounce, with q', (tester) async {
    final api = await openSales(tester);
    api.orderCalls.clear();
    await tester.enterText(key('orderSearch'), 'a');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(key('orderSearch'), 'abc');
    await tester.pump(const Duration(milliseconds: 349));
    expect(api.orderCalls, isEmpty);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pumpAndSettle();
    expect(api.orderCalls.single, (status: null, q: 'abc', cursor: null, limit: 30));
    expect(rowCount(tester), 1);
    await reveal(tester, 'o010');
    // Clearing the box lists everything again
    position(tester).jumpTo(0);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(api.orderCalls.last.q, isNull);
    expect(rowCount(tester), 30);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a search with no result says so', (tester) async {
    await openSales(tester);
    await tester.enterText(key('orderSearch'), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('No orders match'));
    expect(find.text('No orders match'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a slow answer for "ab" arriving after "abc" does not replace the "abc" results', (tester) async {
    final api = await openSales(tester);
    api.ordersGates['ab'] = Completer<void>();
    await tester.enterText(key('orderSearch'), 'ab');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(key('orderSearch'), 'abc');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect([for (final c in api.orderCalls) c.q], [null, 'ab', 'abc']);
    expect(rowCount(tester), 1);
    api.ordersGates['ab']!.complete();
    await tester.pumpAndSettle();
    expect(rowCount(tester), 1, reason: 'the "ab" answer (two rows) was dropped');
    await reveal(tester, 'o010');
    expect(key('orderRow-o011'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pull to refresh reloads the totals and the first page', (tester) async {
    final api = await openSales(tester);
    expect(api.salesCalls, 1);
    api.orderCalls.clear();
    await tester.fling(listScrollable(), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(api.salesCalls, 2);
    expect(api.orderCalls.single.cursor, isNull);
    expect(rowCount(tester), 30);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rows: flagged order, masked phone instead of a missing name, walk-up, and when a hold ends', (tester) async {
    await openSales(tester);
    await reveal(tester, 'o003');
    expect(inRow('o003', 'Flagged Buyer'), findsOneWidget);
    expect(inRow('o003', 'BEING REVIEWED'), findsOneWidget);
    expect(inRow('o003', 'PAID'), findsOneWidget);
    expect(inRow('o003', 'Order E360-0003 · 1 ticket · 40,000 MMK'), findsOneWidget);
    await reveal(tester, 'o002');
    expect(inRow('o002', '0979•••102'), findsOneWidget);
    expect(inRow('o002', 'BEING REVIEWED'), findsNothing);
    await reveal(tester, 'o001');
    expect(inRow('o001', 'Walk-up'), findsOneWidget);
    final t = L10n.of(tester.element(key('orderSearch')));
    await reveal(tester, 'o005');
    expect(inRow('o005', holdLine(t, DateTime.utc(2026, 11, 22, 11, 30), DateTime.now(), 'en')), findsOneWidget);
    expect(find.descendant(of: key('orderRow-o005'), matching: find.textContaining('Hold ended ')), findsOneWidget, reason: 'its hold ran out yesterday');
    expect(find.descendant(of: key('orderRow-o005'), matching: find.textContaining('Hold ended ${formatDayTime(DateTime.utc(2026, 11, 22, 11, 30), 'en').split(' · ').first}')), findsOneWidget, reason: 'with the date');
    expect(inRow('o005', 'WAITING FOR PAYMENT'), findsOneWidget, reason: 'the badge reads like the chip');
    await reveal(tester, 'o015');
    expect(find.descendant(of: key('orderRow-o015'), matching: find.textContaining('Hold ends ')), findsOneWidget);
    await reveal(tester, 'o004');
    expect(inRow('o004', 'REFUNDED'), findsOneWidget);
    expect(find.descendant(of: key('orderRow-o004'), matching: find.textContaining('Hold ends')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed load of more shows a retry line; no automatic retries; a tap retries', (tester) async {
    final api = await openSales(tester);
    api.orderCalls.clear();
    api.failOrdersOnce = true;
    await scrollForMore(tester, api);
    await scrollTo(tester, key('loadMoreFailed'));
    expect(find.text("Couldn't load more. Tap to retry."), findsOneWidget);
    expect(rowCount(tester), 30);
    await scrollForMore(tester, api, steps: 30);
    expect(api.orderCalls, hasLength(1), reason: 'scrolling does not retry by itself');
    await scrollTo(tester, key('loadMoreFailed'));
    await tester.tap(key('loadMoreFailed'));
    await tester.pumpAndSettle();
    expect([for (final c in api.orderCalls) c.cursor], ['30', '30']);
    expect(rowCount(tester), 60);
    expect(find.text("Couldn't load more. Tap to retry."), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed first page shows the retry view; retry loads it', (tester) async {
    final api = await pumpApp(tester, configure: (a) => a.failOrdersOnce = true);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    await goOrders(tester);
    await scrollTo(tester, find.text("Couldn't load. Check your connection."));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(rowCount(tester), 30);
    expect(api.orderCalls, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the order sheet shows the whole order, view only, with the review note only on a flagged order', (tester) async {
    await openSales(tester);
    await reveal(tester, 'o003');
    await tester.tap(key('orderRow-o003'));
    await tester.pumpAndSettle();
    expect(key('orderSheet'), findsOneWidget);
    expect(inSheet('Order E360-0003'), findsOneWidget);
    expect(inSheet('Flagged Buyer'), findsOneWidget);
    expect(inSheet('0979•••103'), findsOneWidget);
    expect(inSheet('PAID'), findsOneWidget);
    expect(inSheet('BEING REVIEWED'), findsOneWidget);
    expect(inSheet('Event 360 is reviewing this payment. If money needs to go back to the buyer, we will refund it.'), findsOneWidget);
    expect(find.descendant(of: key('orderSheet'), matching: find.textContaining('Ordered ')), findsOneWidget);
    expect(find.descendant(of: key('orderSheet'), matching: find.textContaining('Paid ${formatDayTime(DateTime.utc(2026, 11, 22, 10).subtract(const Duration(minutes: 20)), 'en')}')), findsOneWidget);
    expect(inSheet('VIP deck'), findsOneWidget);
    expect(inSheet('2 × 35,000 MMK'), findsOneWidget);
    expect(inSheet('Seats: Stalls · Row 1 · Seat 4, Stalls · Row 1 · Seat 5'), findsOneWidget);
    expect(inSheet('Subtotal'), findsOneWidget);
    expect(inSheet('Discount (EARLY20)'), findsOneWidget);
    expect(tester.widget<Text>(key('orderDiscount')).data, '− 5,000 MMK');
    expect(tester.widget<Text>(key('orderTotal')).data, '40,000 MMK');
    expect(inSheet('Commission'), findsOneWidget);
    expect(inSheet('KBZPay · Failed'), findsOneWidget);
    expect(inSheet('WavePay · Paid'), findsOneWidget);
    expect(inSheet('Mock · Waiting for payment'), findsOneWidget, reason: 'an unknown provider is title-cased');
    expect(inSheet('40,000 MMK'), findsNWidgets(2), reason: 'total and the whole-order refund');
    expect(inSheet('Refund in progress'), findsOneWidget);
    expect(inSheet('Refunds are always for the whole order.'), findsOneWidget);
    expect(inSheet('1 of 2 tickets checked in'), findsOneWidget);
    // View only: the one button closes the sheet
    expect(find.descendant(of: key('orderSheet'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsOneWidget);
    expect(find.descendant(of: key('orderSheet'), matching: find.byType(IconButton)), findsNothing);
    expect(find.descendant(of: key('orderSheet'), matching: find.byType(FilledButton)), findsNothing);
    await tester.tap(key('orderSheetClose'));
    await tester.pumpAndSettle();
    expect(key('orderSheet'), findsNothing);
    // An order that is not flagged has no note
    await reveal(tester, 'o002');
    await tester.tap(key('orderRow-o002'));
    await tester.pumpAndSettle();
    expect(key('orderSheet'), findsOneWidget);
    expect(key('reviewNote'), findsNothing);
    expect(inSheet('0979•••102'), findsNWidgets(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('commission shows only on a paid order, not on a refunded or waiting one', (tester) async {
    await openSales(tester);
    for (final (id, shown) in [('o003', true), ('o004', false), ('o005', false), ('o009', false)]) {
      await reveal(tester, id);
      await tester.tap(key('orderRow-$id'));
      await tester.pumpAndSettle();
      expect(inSheet('Commission'), shown ? findsOneWidget : findsNothing, reason: id);
      await tester.tap(key('orderSheetClose'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rows count tickets in words; one ticket is singular', (tester) async {
    await openSales(tester);
    expect(inRow('o001', 'Order E360-0001 · 2 tickets · 20,000 MMK'), findsOneWidget);
    expect(inRow('o003', 'Order E360-0003 · 1 ticket · 40,000 MMK'), findsOneWidget);
    expect(find.textContaining(' × '), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the filter chips scroll fully into view with a fade while there is more, and drag with a mouse', (tester) async {
    await openSales(tester);
    expect(tester.widget<AnimatedOpacity>(key('orderFiltersFade')).opacity, 1);
    final row = find.descendant(of: find.ancestor(of: key('orderFilter-all'), matching: find.byType(SingleChildScrollView)).first, matching: find.byType(Row)).first;
    final scrollable = find.ancestor(of: key('orderFilter-all'), matching: find.byType(Scrollable)).first;
    final gesture = await tester.startGesture(tester.getCenter(key('orderFilter-paid')), kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0), reason: 'a mouse drag scrolls the row');
    final pos = tester.state<ScrollableState>(scrollable).position;
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pumpAndSettle();
    final last = tester.getRect(key('orderFilter-incomplete'));
    expect(last.right, lessThanOrEqualTo(tester.getSize(find.byType(MaterialApp)).width - 16), reason: 'the last chip is fully visible with room after it');
    expect(tester.widget<AnimatedOpacity>(key('orderFiltersFade')).opacity, 0);
    expect(row, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refund states in plain words', (tester) async {
    final api = await openSales(tester);
    for (final (status, text) in [
      ('PENDING', 'Refund in progress'),
      ('FAILED', 'Refund in progress'),
      ('MANUAL', 'Event 360 is returning it by hand'),
      ('SUCCEEDED', 'Refunded'),
    ]) {
      api.refundStatus = status;
      await reveal(tester, 'o002');
      await tester.tap(key('orderRow-o002'));
      await tester.pumpAndSettle();
      expect(inSheet(text), findsOneWidget, reason: status);
      await tester.tap(key('orderSheetClose'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a walk-up order sheet names the buyer Walk-up and shows no phone', (tester) async {
    await openSales(tester);
    await reveal(tester, 'o001');
    await tester.tap(key('orderRow-o001'));
    await tester.pumpAndSettle();
    expect(inSheet('Walk-up'), findsOneWidget);
    expect(key('orderPhone'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final hasMap in [true, false]) {
    testWidgets('Overview All orders opens the Sales tab on Orders (seat map: $hasMap)', (tester) async {
      await pumpApp(tester, configure: (a) => a.hasMap = hasMap);
      await tester.tap(find.text('Inya Lake Live o1'));
      await tester.pumpAndSettle();
      expect(key('salesTotals'), findsNothing);
      await tester.drag(key('sold'), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.tap(key('allOrdersLink'));
      await tester.pumpAndSettle();
      expect(key('orderSearch'), findsOneWidget);
      expect(key('salesTotals'), findsNothing, reason: 'Orders, not Summary');
      expect(key('tabSeats'), hasMap ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  Map<String, dynamic> newOrder() => {
        'id': 'onew',
        'number': 'E360-9999',
        'status': 'PAID',
        'needsReview': false,
        'createdAt': DateTime.utc(2026, 11, 22, 12).toIso8601String(),
        'paidAt': DateTime.utc(2026, 11, 22, 12).toIso8601String(),
        'holdExpiresAt': null,
        'totalMmk': 10000,
        'discountMmk': 0,
        'quantity': 1,
        'buyer': {'name': 'Fresh Buyer', 'phone': '0979•••999'},
      };

  testWidgets('All orders after a new order arrived shows it at the top, with fresh totals', (tester) async {
    final api = await pumpApp(tester);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    await goOrders(tester);
    expect(key('orderRow-onew'), findsNothing);
    await goOverview(tester);
    // The order arrives while the user is on Overview; later than the quiet period
    api.ordersData.insert(0, newOrder());
    api.sales = {...api.sales, 'paidOrders': 44};
    await tester.pump(const Duration(seconds: 6));
    api.orderCalls.clear();
    final salesBefore = api.salesCalls;
    await tester.drag(key('sold'), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.tap(key('allOrdersLink'));
    await tester.pumpAndSettle();
    expect(key('orderRow-onew'), findsOneWidget);
    expect(inRow('onew', 'Fresh Buyer'), findsOneWidget);
    expect(api.orderCalls.length, 1, reason: 'one quiet reload of the first page, not two');
    expect(api.orderCalls.single.cursor, isNull);
    expect(api.salesCalls, salesBefore + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('coming back to the Sales tab refetches totals and the first page once; not again within 5 seconds', (tester) async {
    final api = await openSales(tester, orders: false);
    expect(api.salesCalls, 1);
    expect(api.orderCalls.length, 1);
    await goOverview(tester);
    api.sales = {...api.sales, 'paidOrders': 44};
    await goSales(tester);
    expect(api.salesCalls, 2);
    expect(api.orderCalls.length, 2);
    expect(tester.widget<Text>(key('paidOrders')).data, '44');
    // A quick flip back and forth stays quiet
    await goOverview(tester);
    await goSales(tester);
    expect(api.salesCalls, 2);
    expect(api.orderCalls.length, 2);
    await tester.pump(const Duration(seconds: 6));
    await goOverview(tester);
    await goSales(tester);
    expect(api.salesCalls, 3);
    expect(api.orderCalls.length, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning while scrolled deep refetches totals but keeps rows and scroll; at the top the first page reloads', (tester) async {
    final api = await openSales(tester);
    await scrollForMore(tester, api);
    await scrollForMore(tester, api);
    final rows = rowCount(tester);
    final offset = position(tester).pixels;
    expect(offset, greaterThan(500));
    api.orderCalls.clear();
    final salesBefore = api.salesCalls;
    await goOverview(tester);
    await goSales(tester);
    expect(api.salesCalls, salesBefore + 1);
    expect(api.orderCalls, isEmpty);
    expect(rowCount(tester), rows);
    expect(position(tester).pixels, offset);
    // At the top the first page is loaded again
    position(tester).jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await goOverview(tester);
    await goSales(tester);
    expect(api.orderCalls.length, 1);
    expect(api.orderCalls.single.cursor, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a quiet refetch that fails keeps the rows and shows no error', (tester) async {
    final api = await openSales(tester);
    await goOverview(tester);
    api.failOrdersOnce = true;
    await goSales(tester);
    expect(rowCount(tester), 30);
    expect(find.text('Try again'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finance and manager both see the Sales tab', (tester) async {
    for (final role in ['ORG_FINANCE', 'ORG_MANAGER']) {
      await openSales(tester, role: role, orders: false);
      expect(key('salesTotals'), findsOneWidget, reason: role);
      await goOrders(tester);
      await reveal(tester, 'o001');
      expect(key('orderRow-o001'), findsOneWidget, reason: role);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Sales sits after Seats and before Door, and the open tab stays when Seats appears late', (tester) async {
    final api = await pumpApp(tester);
    api.seatingGate = Completer<void>();
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    expect(key('salesTotals'), findsOneWidget);
    api.seatingGate!.complete();
    await tester.pumpAndSettle();
    expect(key('tabSeats'), findsOneWidget);
    expect(key('salesTotals'), findsOneWidget, reason: 'still on the Sales tab');
    final x = [for (final k in ['tabGuests', 'tabSeats', 'tabSales', 'tabDoor']) tester.getTopLeft(key(k)).dx];
    expect(x, orderedEquals([...x]..sort()));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Myanmar: the tab, chips and sheet read in Myanmar', (tester) async {
    await openSales(tester, lang: 'my');
    expect(find.text('ရောင်းချမှု'), findsOneWidget);
    expect(find.text('အနှစ်ချုပ်'), findsOneWidget);
    expect(find.text('ငွေပေးချေရန် စောင့်နေ'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('re-entering the event shows fresh totals: /sales is fetched again', (tester) async {
    final api = await openSales(tester, orders: false);
    expect(api.salesCalls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    expect(api.salesCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed refresh of the orders says so and keeps the earlier rows', (tester) async {
    final api = await openSales(tester);
    api.failOrdersOnce = true;
    await tester.fling(listScrollable(), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't refresh. Showing earlier data."), findsOneWidget);
    expect(rowCount(tester), 30);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed refresh of the totals says so and keeps the earlier totals', (tester) async {
    final api = await openSales(tester, orders: false);
    api.failSalesOnce = true;
    await tester.fling(key('salesSummary'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't refresh. Showing earlier data."), findsNWidgets(2), reason: 'the snackbar and the hint in Summary');
    expect(tester.widget<Text>(key('grossSales')).data, '700,000 MMK');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the failed-refresh hint stays in Summary until the next load works', (tester) async {
    final api = await openSales(tester, orders: false);
    expect(key('salesRefreshFailed'), findsNothing);
    api.failSalesOnce = true;
    await tester.fling(key('salesSummary'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(key('salesRefreshFailed'), findsOneWidget);
    expect(tester.widget<Text>(key('salesRefreshFailed')).data, "Couldn't refresh. Showing earlier data.");
    expect(tester.widget<Text>(key('grossSales')).data, '700,000 MMK');
    // The snackbar goes; the hint does not
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(key('salesRefreshFailed'), findsOneWidget);
    await tester.fling(key('salesSummary'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(key('salesRefreshFailed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the ticket types say their revenue is before discounts', (tester) async {
    await openSales(tester, orders: false);
    await tester.scrollUntilVisible(key('revenueCaption'), 200, scrollable: find.descendant(of: key('salesSummary'), matching: find.byType(Scrollable)).first);
    expect(tester.widget<Text>(key('revenueCaption')).data, 'Ticket revenue is before discounts');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the typed search, filter and view survive a look at another tab', (tester) async {
    final api = await openSales(tester);
    await tester.enterText(key('orderSearch'), 'abc');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(key('orderFilter-paid'));
    await tester.pumpAndSettle();
    final calls = api.orderCalls.length;
    await tester.ensureVisible(key('tabGuests'));
    await tester.pumpAndSettle();
    await tester.tap(key('tabGuests'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('tabSales'));
    await tester.pumpAndSettle();
    await tester.tap(key('tabSales'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(key('orderSearch')).controller!.text, 'abc');
    expect(tester.widget<FilterChip>(key('orderFilter-paid')).selected, isTrue);
    // Coming back reloads the first page once, quietly, with the same search and filter
    expect(api.orderCalls, hasLength(calls + 1));
    expect(api.orderCalls.last.q, 'abc');
    expect(api.orderCalls.last.status, 'paid');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the typed search survives the Seats tab appearing late', (tester) async {
    final api = await pumpApp(tester);
    api.seatingGate = Completer<void>();
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    await goOrders(tester);
    await tester.enterText(key('orderSearch'), 'abc');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    api.seatingGate!.complete();
    await tester.pumpAndSettle();
    expect(key('tabSeats'), findsOneWidget);
    expect(tester.widget<TextField>(key('orderSearch')).controller!.text, 'abc');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the keyboard up the search field and an order row are both on screen', (tester) async {
    await pumpApp(tester, size: const Size(390 * 3, 844 * 3));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await goSales(tester);
    await goOrders(tester);
    final search = tester.getRect(key('orderSearch'));
    final row = tester.getRect(key('orderRow-o001'));
    expect(search.bottom, lessThanOrEqualTo(844 - 300));
    expect(row.top, greaterThanOrEqualTo(search.bottom));
    expect(row.bottom, lessThanOrEqualTo(844 - 300));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing the filter while an earlier filter is still loading keeps the newer rows', (tester) async {
    final api = await openSales(tester);
    api.statusGates['paid'] = Completer<void>();
    await tester.tap(key('orderFilter-paid'));
    await tester.pump();
    await tester.tap(key('orderFilter-refunded'));
    await tester.pumpAndSettle();
    expect(rowCount(tester), 8, reason: 'refunded rows');
    api.statusGates['paid']!.complete();
    await tester.pumpAndSettle();
    expect(rowCount(tester), 8, reason: 'the slow paid answer was dropped');
    expect(tester.widget<FilterChip>(key('orderFilter-refunded')).selected, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('holdLine: ends or ended, with the date when it is not today', (tester) async {
    await openSales(tester);
    final t = L10n.of(tester.element(key('orderSearch')));
    final now = DateTime.utc(2026, 11, 23, 8);
    expect(holdLine(t, DateTime.utc(2026, 11, 23, 9), now, 'en'), 'Hold ends ${formatTime(DateTime.utc(2026, 11, 23, 9), 'en')}');
    expect(holdLine(t, DateTime.utc(2026, 11, 23, 7), now, 'en'), 'Hold ended ${formatTime(DateTime.utc(2026, 11, 23, 7), 'en')}');
    expect(holdLine(t, DateTime.utc(2026, 11, 22, 7), now, 'en'), 'Hold ended ${formatDayTime(DateTime.utc(2026, 11, 22, 7), 'en')}');
    expect(holdLine(t, DateTime.utc(2026, 11, 24, 7), now, 'en'), 'Hold ends ${formatDayTime(DateTime.utc(2026, 11, 24, 7), 'en')}');
    await tester.pumpWidget(const SizedBox());
  });
}
