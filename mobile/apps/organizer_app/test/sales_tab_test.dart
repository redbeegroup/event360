import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/format.dart';

import 'widget_test.dart' hide main;

Finder key(String k) => find.byKey(Key(k));

Future<void> goSales(WidgetTester tester) async {
  await tester.ensureVisible(key('tabSales'));
  await tester.pumpAndSettle();
  await tester.tap(key('tabSales'));
  await tester.pumpAndSettle();
}

Future<FakeApi> openSales(WidgetTester tester, {String role = 'ORG_OWNER', String lang = 'en', void Function(FakeApi)? setup}) async {
  final api = await pumpApp(tester, role: role, lang: lang, configure: setup);
  await tester.tap(find.text('Inya Lake Live o1'));
  await tester.pumpAndSettle();
  await goSales(tester);
  return api;
}

Finder listScrollable() => find.descendant(of: key('orderList'), matching: find.byType(Scrollable)).first;

/// Rows (and the header and footer) the list was given; only a few are built.
int rowCount(WidgetTester tester) => tester.widget<ListView>(key('orderList')).childrenDelegate.estimatedChildCount! - 2;

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
    final api = await openSales(tester);
    expect(key('salesTotals'), findsOneWidget);
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
    final api = await openSales(tester, setup: (a) => a.sales = {...a.sales, 'ticketTypes': [], 'paidOrders': 0});
    expect(key('noPaidTickets'), findsOneWidget);
    expect(find.text('This event has no paid tickets'), findsOneWidget);
    expect(key('salesTotals'), findsNothing);
    expect(key('orderSearch'), findsNothing);
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
    expect(inRow('o005', 'AWAITING PAYMENT'), findsOneWidget);
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
    expect(inRow('o003', 'Order E360-0003 · 1 × · 40,000 MMK'), findsOneWidget);
    await reveal(tester, 'o002');
    expect(inRow('o002', '0979•••102'), findsOneWidget);
    expect(inRow('o002', 'BEING REVIEWED'), findsNothing);
    await reveal(tester, 'o001');
    expect(inRow('o001', 'Walk-up'), findsOneWidget);
    await reveal(tester, 'o005');
    expect(inRow('o005', 'Hold ends ${formatTime(DateTime.utc(2026, 11, 22, 11, 30), 'en')}'), findsOneWidget);
    expect(inRow('o005', 'WAITING FOR PAYMENT'), findsNothing, reason: 'the status badge reads Awaiting payment');
    expect(inRow('o005', 'AWAITING PAYMENT'), findsOneWidget);
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

  testWidgets('Overview All orders opens the Sales tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    expect(key('salesTotals'), findsNothing);
    await tester.drag(key('sold'), const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.tap(key('allOrdersLink'));
    await tester.pumpAndSettle();
    expect(key('salesTotals'), findsOneWidget);
    expect(key('orderSearch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finance and manager both see the Sales tab', (tester) async {
    for (final role in ['ORG_FINANCE', 'ORG_MANAGER']) {
      await openSales(tester, role: role);
      expect(key('salesTotals'), findsOneWidget, reason: role);
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
    expect(find.text('ငွေပေးချေရန် စောင့်နေ'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
