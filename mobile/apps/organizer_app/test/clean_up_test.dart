import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/errors.dart';
import 'package:organizer_app/app/format.dart';
import 'package:organizer_app/app/providers.dart';
import 'package:organizer_app/l10n/app_localizations_en.dart';
import 'package:organizer_app/l10n/app_localizations_my.dart';
import 'package:organizer_app/main.dart';
import 'package:organizer_app/screens/event/common.dart';
import 'package:organizer_app/screens/event/guests_tab.dart' show typeAndSeat;
import 'package:organizer_app/screens/event_screen.dart' show StatTile;

import 'widget_test.dart' hide main;

const _k = (orgId: 'o1', eventId: 'e1');
Finder key(String k) => find.byKey(Key(k));
ProviderContainer containerOf(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(OrganizerApp)));

Future<void> openEventTab(WidgetTester t, [String? tab]) async {
  await t.tap(find.byKey(const Key('event-e1')));
  await t.pumpAndSettle();
  if (tab != null) {
    await t.ensureVisible(key(tab));
    await t.pumpAndSettle();
    await t.tap(key(tab));
    await t.pumpAndSettle();
  }
}

Future<void> openPayoutsScreen(WidgetTester t) async {
  await t.tap(find.byType(PopupMenuButton<String>));
  await t.pumpAndSettle();
  await t.tap(key('menuPayouts'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  group('errorText', () {
    final en = L10nEn(), my = L10nMy();
    test('by status', () {
      expect(errorText(en, ApiException(401, 'Unauthorized')), 'Please sign in again');
      expect(errorText(en, ApiException(403, 'Forbidden resource')), 'You no longer have access to this');
      expect(errorText(en, ApiException(404, 'Event not found')), 'This is no longer available');
      for (final s in [500, 502, 400, 409, 429]) {
        expect(errorText(en, ApiException(s, 'Some server sentence')), 'Something went wrong. Try again.', reason: '$s');
      }
    });
    test('by reasonCode', () {
      const texts = {
        'SEATS_NOT_AVAILABLE': 'Some of those seats are no longer free',
        'SEATS_NOT_HELD': 'Hold those seats for guests first',
        'SEATS_MUST_BE_HELD_FIRST': 'Hold those seats for guests first',
        'NO_SEAT_MAP': 'This event has no seat map',
        'EVENT_ENDED': 'This event has ended',
        'GUEST_ALREADY_CHECKED_IN': 'This guest has already checked in',
        'GUEST_ALREADY_REVOKED': 'This ticket was already revoked',
        'GUEST_TICKET_NOT_FOUND': 'Guest ticket not found',
        'NOT_CHECKED_IN': 'This ticket is not checked in',
      };
      for (final e in texts.entries) {
        expect(errorText(en, ApiException(409, 'raw server english', reasonCode: e.key)), e.value, reason: e.key);
        expect(errorText(my, ApiException(409, 'raw server english', reasonCode: e.key)), isNot(e.value), reason: '${e.key} in Myanmar');
      }
      // a 404 that carries its own code says that
      expect(errorText(en, ApiException(404, 'x', reasonCode: 'GUEST_TICKET_NOT_FOUND')), 'Guest ticket not found');
      // SeatsChanged carries the code too
      expect(errorText(en, const SeatsChanged('x', ['A:1:1'], reasonCode: 'SEATS_NOT_AVAILABLE')), 'Some of those seats are no longer free');
      // an unknown code reads as the generic text, never the server's words
      expect(errorText(en, ApiException(409, 'raw server english', reasonCode: 'SOMETHING_NEW')), 'Something went wrong. Try again.');
    });
    test('promo and announcement codes', () {
      expect(errorText(en, ApiException(409, 'x', reasonCode: 'PROMO_CODE_EXISTS')), 'This code already exists for the event');
      expect(errorText(en, ApiException(400, 'x', reasonCode: 'PROMO_PERCENT_RANGE')), 'Percent must be between 1 and 100');
      expect(errorText(en, ApiException(400, 'x', reasonCode: 'PROMO_DATES_ORDER')), 'The end must be after the start');
      expect(errorText(en, ApiException(409, 'x', reasonCode: 'ANNOUNCE_NOT_PUBLISHED')), 'Announcements can only be sent for published events');
      expect(errorText(en, ApiException(409, 'x', reasonCode: 'ANNOUNCE_DAILY_LIMIT')), 'You can send at most 3 announcements a day for an event');
      expect(errorText(en, ApiException(409, 'x', reasonCode: 'EVENT_ENDED')), 'This event has ended');
    });
    test('only network errors read as the connection text', () {
      expect(errorText(en, ApiException(null, 'Network error')), en.loadError);
      expect(errorText(en, StateError('boom')), 'Something went wrong. Try again.');
      expect(errorText(my, ApiException(null, 'Network error')), my.loadError);
    });
    test('only 403 and 404 are final (no Retry)', () {
      expect(isFinalError(ApiException(403, 'x')), isTrue);
      expect(isFinalError(ApiException(404, 'x')), isTrue);
      expect(isFinalError(ApiException(null, 'x')), isFalse);
      expect(isFinalError(ApiException(500, 'x')), isFalse);
      expect(isFinalError(null), isFalse);
    });
  });

  group('session ended', () {
    testWidgets('a 401 that survives the refresh signs out; sign-in says so once', (tester) async {
      final api = await pumpApp(tester);
      expect(find.text('Inya Lake Live o1'), findsOneWidget);
      await api.expireSession();
      await tester.pumpAndSettle();
      expect(find.text('Sign in with your organizer account'), findsOneWidget);
      expect(find.text('Please sign in again'), findsOneWidget);
      expect(containerOf(tester).read(sessionEndedProvider), isFalse, reason: 'taken by the screen: not shown again');
      // a language switch rebuilds the screen and keeps the notice; it does not come back after signing in and out
      await tester.enterText(key('email'), 'owner@yl.test');
      await tester.enterText(key('password'), 'secret-123');
      await tester.tap(key('signIn'));
      await tester.pumpAndSettle();
      expect(find.text('Inya Lake Live o1'), findsOneWidget);
      await containerOf(tester).read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Sign in with your organizer account'), findsOneWidget);
      expect(find.text('Please sign in again'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a wrong password does not read as an ended session', (tester) async {
      await pumpApp(tester, signedIn: false);
      await tester.enterText(key('email'), 'owner@yl.test');
      await tester.enterText(key('password'), 'nope');
      await tester.tap(key('signIn'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong email or password'), findsOneWidget);
      expect(find.text('Please sign in again'), findsNothing);
    });

    testWidgets('a second report from another request while signed out does nothing', (tester) async {
      final api = await pumpApp(tester);
      await api.expireSession();
      await tester.pumpAndSettle();
      await api.expireSession();
      await tester.pumpAndSettle();
      expect(find.text('Please sign in again'), findsOneWidget);
      expect(containerOf(tester).read(sessionEndedProvider), isFalse);
      expect(find.text('Sign in with your organizer account'), findsOneWidget);
    });
  });

  group('sign-out', () {
    testWidgets('the next user does not see or reuse what the last one loaded', (tester) async {
      final api = await pumpApp(tester);
      await openEventTab(tester, 'tabGuests');
      expect(find.text('Aung Min'), findsOneWidget);
      final d = api.dashboardCalls, a = api.attendeesCalls;
      await containerOf(tester).read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Aung Min'), findsNothing);
      api.attendeesList.removeWhere((x) => x['id'] == 'a1'); // user B's data differs
      await tester.enterText(key('email'), 'b@yl.test');
      await tester.enterText(key('password'), 'secret-123');
      await tester.tap(key('signIn'));
      await tester.pumpAndSettle();
      await openEventTab(tester, 'tabGuests');
      expect(api.dashboardCalls, greaterThan(d), reason: 'fetched again');
      expect(api.attendeesCalls, greaterThan(a), reason: 'fetched again');
      expect(find.text('Aung Min'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after the session ended too', (tester) async {
      final api = await pumpApp(tester);
      await openEventTab(tester, 'tabGuests');
      final a = api.attendeesCalls;
      await api.expireSession();
      await tester.pumpAndSettle();
      await tester.enterText(key('email'), 'b@yl.test');
      await tester.enterText(key('password'), 'secret-123');
      await tester.tap(key('signIn'));
      await tester.pumpAndSettle();
      await openEventTab(tester, 'tabGuests');
      expect(api.attendeesCalls, greaterThan(a));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('signing out on purpose while the session is already dead does not say it ended', (tester) async {
      final api = await pumpApp(tester);
      final c = containerOf(tester);
      await c.read(prefsProvider).setString(pushTokenKey, 'tok');
      api.sessionDead = true;
      await c.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.text('Sign in with your organizer account'), findsOneWidget);
      expect(find.text('Please sign in again'), findsNothing);
      expect(c.read(sessionEndedProvider), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('load error states', () {
    Future<void> overviewWith(WidgetTester tester, Object error, {String lang = 'en'}) async {
      await pumpApp(tester, lang: lang, configure: (a) => a.dashboardError = error);
      await openEventTab(tester);
    }

    testWidgets('403: says so, no Retry', (tester) async {
      await overviewWith(tester, ApiException(403, 'Forbidden'));
      expect(find.text('You no longer have access to this'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('404: says so, no Retry', (tester) async {
      await overviewWith(tester, ApiException(404, 'Not found'));
      expect(find.text('This is no longer available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('connection error and server error: Retry stays', (tester) async {
      await overviewWith(tester, ApiException(null, 'Network error'));
      expect(find.text("Couldn't load. Check your connection."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a server error says something went wrong, with Retry and no wifi icon', (tester) async {
      await overviewWith(tester, ApiException(500, 'Internal server error'));
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Myanmar: the same, in Myanmar', (tester) async {
      await overviewWith(tester, ApiException(403, 'Forbidden'), lang: 'my');
      expect(find.text(L10nMy().noAccess), findsOneWidget);
      expect(find.text(L10nMy().retry), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the guests list and the event list use it too', (tester) async {
      await pumpApp(tester, configure: (a) => a.attendeesError = ApiException(404, 'x'));
      await openEventTab(tester, 'tabGuests');
      expect(find.text('This is no longer available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a seat action refused with a reason code says it in plain words, not the server English', (tester) async {
      await pumpApp(tester, configure: (a) => a.holdError = ApiException(409, 'Seats are not free', reasonCode: 'SEATS_NOT_AVAILABLE'));
      await openEventTab(tester, 'tabSeats');
      await tapSeats(tester, ['A:3:1', 'A:3:2']);
      await tester.tap(key('seatsHold'));
      await tester.pumpAndSettle();
      await tester.enterText(key('holdLabel'), 'Press');
      await tester.tap(key('holdSubmit'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('sheetError')).data, 'Some of those seats are no longer free');
      expect(find.text('Seats are not free'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Myanmar names', () {
    testWidgets('Sales: nameMy in my, ignored in en, falls back when absent', (tester) async {
      void configure(FakeApi a) {
        final types = [...(a.sales['ticketTypes'] as List)].cast<Map<String, dynamic>>();
        types[0] = {...types[0], 'nameMy': 'ဗီအိုင်ပီ ထပ်ခိုး'};
        a.sales = {...a.sales, 'ticketTypes': types};
      }

      await pumpApp(tester, lang: 'my', configure: configure);
      await openEventTab(tester, 'tabSales');
      expect(find.text('ဗီအိုင်ပီ ထပ်ခိုး'), findsOneWidget);
      expect(find.text('VIP deck'), findsNothing);
      expect(find.text('Standing'), findsOneWidget, reason: 'no nameMy: the English name');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, lang: 'en', configure: configure);
      await openEventTab(tester, 'tabSales');
      expect(find.text('VIP deck'), findsOneWidget);
      expect(find.text('ဗီအိုင်ပီ ထပ်ခိုး'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Payouts: titleMy in my, ignored in en', (tester) async {
      void configure(FakeApi a) {
        final d = a.payoutsFor('o1');
        final events = [...(d['events'] as List)].cast<Map<String, dynamic>>();
        events[0] = {...events[0], 'titleMy': 'အင်းလျားကန် ဖျော်ဖြေပွဲ'};
        a.payoutData = {...d, 'events': events};
      }

      await pumpApp(tester, lang: 'my', configure: configure);
      await openPayoutsScreen(tester);
      expect(find.text('အင်းလျားကန် ဖျော်ဖြေပွဲ'), findsOneWidget);
      expect(find.text('Inya Lake Live'), findsNothing);
      expect(find.text('Thingyan Gala'), findsOneWidget, reason: 'no titleMy: the English title');
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, lang: 'en', configure: configure);
      await openPayoutsScreen(tester);
      expect(find.text('Inya Lake Live'), findsOneWidget);
      expect(find.text('အင်းလျားကန် ဖျော်ဖြေပွဲ'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('counts', () {
    testWidgets('go through formatAmount: the digits of money in the same screen', (tester) async {
      await pumpApp(tester, lang: 'my');
      await openEventTab(tester);
      final money = tester.widget<Text>(key('revenue')).data!;
      expect(money, '${formatAmount(138000, 'my')} ကျပ်');
      final digits = RegExp(r'[၀-၉]');
      expect(digits.hasMatch(money), isTrue, reason: 'money uses Myanmar digits');
      for (final k in ['sold', 'checkedIn']) {
        final v = tester.widget<Text>(key(k)).data!;
        expect(RegExp(r'[0-9]').hasMatch(v), isFalse, reason: '$k: $v');
      }
      await tester.tap(key('tabGuests'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('guestsCount')).data, L10nMy().guestsCount(formatAmount(2, 'my'), formatAmount(5, 'my')));
      expect(RegExp(r'[0-9]').hasMatch(tester.widget<Text>(key('guestsCount')).data!), isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Seats: selection, guest tickets and legend counts', (tester) async {
      await pumpApp(tester, lang: 'my');
      await openEventTab(tester, 'tabSeats');
      await tapSeats(tester, ['A:3:1', 'A:3:2']);
      expect(tester.widget<Text>(key('seatsSelected')).data, L10nMy().seatsSelected(2, formatAmount(2, 'my')));
      expect(RegExp(r'[0-9]').hasMatch(tester.widget<Text>(key('seatsSelected')).data!), isFalse);
      for (final k in ['seatsViewGuests', 'legendAvailable', 'legendSold']) {
        final texts = find.descendant(of: key(k), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data ?? '').join();
        expect(RegExp(r'[0-9]').hasMatch(texts), isFalse, reason: '$k: $texts');
      }
      await tester.pumpWidget(const SizedBox());
    });

    test('formatAmount separators', () {
      expect(formatAmount(3000, 'en'), '3,000');
    });
  });

  group('layout', () {
    testWidgets('issue confirm dialog in Myanmar at 390 wide: one-line button, phone not broken', (tester) async {
      await pumpApp(tester, lang: 'my', size: const Size(390 * 3, 844 * 3));
      await openEventTab(tester, 'tabSeats');
      await tapSeats(tester, ['A:2:4', 'A:1:5']);
      await tester.tap(key('seatsIssue'));
      await tester.pumpAndSettle();
      await tester.enterText(key('guestName'), 'Daw Aye Aye Khin');
      await tester.enterText(key('guestPhone'), '09 123-456 789');
      await tester.tap(key('issueSubmit'));
      await tester.pumpAndSettle();
      expect(key('issueConfirm'), findsOneWidget);
      final label = tester.renderObject<RenderParagraph>(find.descendant(of: key('issueConfirm'), matching: find.byType(RichText)));
      expect({for (final b in label.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.text.toPlainText().length))) b.top.round()}.length, 1, reason: 'the button label is on one line');
      final p = tester.renderObject<RenderParagraph>(find.descendant(of: key('issueConfirmText'), matching: find.byType(RichText)));
      final text = p.text.toPlainText();
      final at = text.indexOf('09\u00A0123\u2011456\u00A0789');
      expect(at, greaterThanOrEqualTo(0), reason: text);
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 14));
      expect({for (final b in boxes) b.top.round()}.length, 1, reason: 'the number sits on one line');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('order filter chips: the last one is fully reachable in Myanmar', (tester) async {
      await pumpApp(tester, lang: 'my', size: const Size(390 * 3, 844 * 3));
      await openEventTab(tester, 'tabSales');
      await tester.tap(key('salesViewOrders'));
      await tester.pumpAndSettle();
      final row = find.descendant(of: find.byType(FadingHScroll), matching: find.byType(SingleChildScrollView)).first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(row, const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
      final chipRight = tester.getTopRight(key('orderFilter-incomplete')).dx;
      final viewRight = tester.getTopRight(row).dx;
      expect(chipRight, lessThanOrEqualTo(viewRight - kFadeWidth + 0.5), reason: 'clear of the fade at the edge');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Overview tile says Orders and registrations', (tester) async {
      await pumpApp(tester);
      await openEventTab(tester);
      final tile = find.ancestor(of: find.text('Orders and registrations'), matching: find.byType(StatTile));
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('9')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, lang: 'my');
      await openEventTab(tester);
      expect(find.text('အော်ဒါနှင့် စာရင်းသွင်းမှုများ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Payouts: the discounts line is a footnote, apart from the sum', (tester) async {
      await pumpApp(tester);
      await openPayoutsScreen(tester);
      await tester.tap(key('payoutEvent-pe1'));
      await tester.pumpAndSettle();
      final net = key('payoutLine-net-pe1'), disc = key('payoutLine-discounts-pe1'), commission = key('payoutLine-commission-pe1');
      final gap = tester.getTopLeft(disc).dy - tester.getBottomLeft(net).dy;
      expect(gap, greaterThanOrEqualTo(18), reason: 'a clear space before the footnote (it was 10 as a line of the sum)');
      final discSize = tester.widget<Text>(disc).style!.fontSize!;
      final lineSize = tester.widget<Text>(commission).style!.fontSize!;
      expect(discSize, lessThan(lineSize));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('guest rows', () {
    test('typeAndSeat: the type is not printed twice', () {
      expect(typeAndSeat('Stalls', 'Stalls · Row C · Seat 4'), 'Stalls · Row C · Seat 4');
      expect(typeAndSeat('stalls', 'Stalls · Row C · Seat 4'), 'Stalls · Row C · Seat 4');
      expect(typeAndSeat('VIP', 'Stalls · Row C · Seat 4'), 'VIP · Stalls · Row C · Seat 4');
      expect(typeAndSeat('VIP', 'VIP Lounge · Row A · Seat 1'), 'VIP · VIP Lounge · Row A · Seat 1', reason: 'only the whole first part counts');
      expect(typeAndSeat(' Stalls ', 'stalls · Row C'), 'stalls · Row C');
      expect(typeAndSeat('Stall', 'Stalls · Row C · Seat 4'), 'Stall · Stalls · Row C · Seat 4');
      expect(typeAndSeat('Standing', ''), 'Standing');
    });

    testWidgets('list rows and the attendee sheet', (tester) async {
      Map<String, dynamic> row(String id, String name, String type) => {
            'id': id,
            'status': 'VALID',
            'createdAt': '2026-11-20T04:00:00.000Z',
            'seatLabel': 'Stalls · Row C · Seat 4',
            'seatLabelMy': null,
            'isComplimentary': false,
            'guestName': null,
            'holder': {'displayName': name, 'phone': '09771111222'},
            'ticketType': {'name': type},
          };
      await pumpApp(tester, configure: (a) => a.attendeesList.addAll([row('s1', 'Aaa Stalls', 'Stalls'), row('s2', 'Aab Vip', 'VIP')]));
      await openEventTab(tester, 'tabGuests');
      expect(find.descendant(of: key('guestRow-s1'), matching: find.text('Stalls · Row C · Seat 4')), findsOneWidget);
      expect(find.descendant(of: key('guestRow-s2'), matching: find.text('VIP · Stalls · Row C · Seat 4')), findsOneWidget);
      await tester.tap(key('guestRow-s1'));
      await tester.pumpAndSettle();
      expect(find.text('Stalls · Row C · Seat 4'), findsNWidgets(2), reason: 'the row behind the sheet and the sheet, once each');
      expect(find.text('Stalls · Stalls · Row C · Seat 4'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the attendee sheet keeps its name clear of the rounded edge', (tester) async {
      await pumpApp(tester);
      await openEventTab(tester, 'tabGuests');
      await tester.tap(key('guestRow-a1'));
      await tester.pumpAndSettle();
      final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
      final nameTop = tester.getTopLeft(find.descendant(of: find.byType(BottomSheet), matching: find.text('Aung Min'))).dy;
      expect(nameTop - sheetTop, greaterThanOrEqualTo(16));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('tabs', () {
    testWidgets('Seats keeps its selection across a tab switch', (tester) async {
      await pumpApp(tester);
      await openEventTab(tester, 'tabSeats');
      await tapSeats(tester, ['A:3:1', 'A:3:2']);
      expect(find.text('2 seats selected'), findsOneWidget);
      for (final other in ['tabGuests', 'tabSales']) {
        await tester.tap(key(other));
        await tester.pumpAndSettle();
        await tester.tap(key('tabSeats'));
        await tester.pumpAndSettle();
        expect(find.text('2 seats selected'), findsOneWidget, reason: 'after $other');
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Seats keeps its sub-view and selection when it arrives late', (tester) async {
      late FakeApi api;
      await pumpApp(tester, configure: (a) {
        api = a;
        a.seatingGate = Completer<void>();
      });
      await tester.tap(find.byKey(const Key('event-e1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(key('tabSeats'), findsNothing);
      api.seatingGate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(key('tabSeats'));
      await tester.pumpAndSettle();
      await tapSeats(tester, ['A:3:1']);
      await openGuestTickets(tester);
      await tester.tap(key('tabGuests'));
      await tester.pumpAndSettle();
      await tester.tap(key('tabSeats'));
      await tester.pumpAndSettle();
      expect(key('guestTicketList'), findsOneWidget, reason: 'still on the guest tickets view');
      await tester.tap(key('seatsViewMap'));
      await tester.pumpAndSettle();
      expect(find.text('1 seat selected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('guests: stale data', () {
    testWidgets('a failed refresh keeps the rows and says so until the next success', (tester) async {
      await pumpApp(tester);
      await openEventTab(tester, 'tabGuests');
      expect(key('guestsRefreshFailed'), findsNothing);
      final api = containerOf(tester).read(apiProvider) as FakeApi;
      api.attendeesError = ApiException(null, 'x');
      containerOf(tester).invalidate(attendeesProvider(_k));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't refresh. Showing earlier data."), findsOneWidget);
      expect(key('guestRow-a1'), findsOneWidget, reason: 'the earlier rows stay');
      // it stays through another failed attempt, and goes with the next success
      containerOf(tester).invalidate(attendeesProvider(_k));
      await tester.pumpAndSettle();
      expect(key('guestsRefreshFailed'), findsOneWidget);
      api.attendeesError = null;
      containerOf(tester).invalidate(attendeesProvider(_k));
      await tester.pumpAndSettle();
      expect(key('guestsRefreshFailed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
