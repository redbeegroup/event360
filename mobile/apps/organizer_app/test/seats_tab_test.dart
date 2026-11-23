import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/providers.dart';
import 'package:organizer_app/l10n/app_localizations.dart';
import 'package:organizer_app/screens/event/seats_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' hide main;

Future<FakeApi> openSeats(WidgetTester tester, {String role = 'ORG_OWNER', void Function(FakeApi)? setup, String lang = 'en'}) async {
  final api = await pumpApp(tester, role: role, lang: lang);
  setup?.call(api);
  await tester.tap(find.text('Inya Lake Live o1'));
  await tester.pumpAndSettle();
  if (api.hasMap) {
    await tester.tap(find.byKey(const Key('tabSeats')));
    await tester.pumpAndSettle();
  }
  return api;
}

final bar = find.byKey(const Key('selectionBar'));
Finder key(String k) => find.byKey(Key(k));
Finder legend(String k, String text) => find.descendant(of: key(k), matching: find.text(text));

/// Number of gold filled buttons on screen, or inside [within] (the sheet: the bar behind it is covered).
int goldButtons(WidgetTester tester, {Finder? within}) => tester
    .widgetList<FilledButton>(within == null ? find.byType(FilledButton) : find.descendant(of: within, matching: find.byType(FilledButton)))
    .where((b) => b.style?.backgroundColor?.resolve({}) == E360Colors.gold)
    .length;

/// A map with one row of 205 seats, far wider than the screen (zoomed out), all on sale.
class BigApi extends FakeApi {
  BigApi(super.store);
  @override
  Future<OrgSeating> orgSeating(String orgId, String eventId) async => OrgSeating.fromJson({
        'layout': {
          'width': 5000,
          'height': 100,
          'sections': [
            {
              'key': 'B',
              'name': 'Row',
              'kind': 'SEATED',
              'x': 20,
              'y': 30,
              'rows': [
                {'label': '1', 'seats': [for (var n = 1; n <= 205; n++) {'n': n}]},
              ],
            },
          ],
        },
        'seats': [for (var n = 1; n <= 205; n++) {'seatKey': 'B:1:$n', 'status': 'AVAILABLE', 'ticketTypeId': 't1', 'holdLabel': null}],
        'colors': {'t1': '#2f6fed'},
        'counts': {'t1': {'available': 205, 'held': 0, 'offered': 0, 'guest': 0, 'sold': 0, 'comp': 0}},
      });
}

Future<void> pumpBig(WidgetTester tester, int selected) async {
  tester.view.physicalSize = const Size(1236, 2745);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'org_lang': 'en'});
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(sp), apiProvider.overrideWithValue(BigApi(MemoryTokenStore()))],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: SeatsTab(k: (orgId: 'o1', eventId: 'e1'), canEdit: true, initialSelected: {for (var n = 1; n <= selected; n++) 'B:1:$n'})),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tallTests();
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  test('orgSeatState maps the six server statuses onto the existing seat states', () {
    expect(orgSeatState('AVAILABLE'), SeatState.available);
    expect(orgSeatState('GUEST_HOLD'), SeatState.held);
    expect(orgSeatState('UNSOLD'), SeatState.unavailable);
    expect(orgSeatState('SOLD'), SeatState.taken);
    expect(orgSeatState('CHECKOUT_HOLD'), SeatState.taken);
    expect(orgSeatState('WAITLIST_HOLD'), SeatState.taken);
  });

  test(
    'isMyanmarMobile follows the server rule: +959 / 959 / 09, then 7 to 10 digits, spaces, dashes and brackets ignored',
    () {
      for (final ok in [
        '09123456789',
        '09 123 456 789',
        '+959123456789',
        '959-123-456-789',
        '0912345678',
        '09 (123) 4567', // 7 digits after the 9: the shortest the server takes
        '091234567890', // 10 after the 9: the longest
        '+959 12 345-6789',
      ]) {
        expect(isMyanmarMobile(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '123',
        '08123456789',
        '091234', // 4 after the 9
        '09123456', // 6
        '0912345678901', // 11
        '09123456789012', // 12
        '+95912345678901', // 11
        '+09123456789',
        '9123456789', // no prefix
        '09 12a 456 789',
        '',
      ]) {
        expect(isMyanmarMobile(bad), isFalse, reason: bad);
      }
    },
  );

  test('refreshSeating also reloads the attendance totals', () async {
    final api = FakeApi(MemoryTokenStore());
    var loads = 0;
    final c = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(api),
        attendanceProvider((orgId: 'o1', eventId: 'e1')).overrideWith((
          ref,
        ) async {
          loads++;
          return api.eventAttendance('o1', 'e1');
        }),
      ],
    );
    addTearDown(c.dispose);
    final k = (orgId: 'o1', eventId: 'e1');
    final sub = c.listen(attendanceProvider(k), (_, __) {});
    await c.read(attendanceProvider(k).future);
    expect(loads, 1);
    refreshSeating(c, k);
    await c.read(attendanceProvider(k).future);
    expect(loads, 2);
    sub.close();
  });

  testWidgets('no Seats tab when the event has no seat map', (tester) async {
    await openSeats(tester, setup: (a) => a.hasMap = false);
    expect(key('tabSeats'), findsNothing);
    expect(key('tabGuests'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Seats tab sits between Guests and Door, with the legend counts', (tester) async {
    await openSeats(tester);
    final x = [for (final k in ['tabGuests', 'tabSeats', 'tabDoor']) tester.getTopLeft(key(k)).dx];
    expect(x, orderedEquals([...x]..sort()));
    expect(legend('legendAvailable', 'On sale 10'), findsOneWidget);
    expect(legend('legendHeld', 'Held for guests 4'), findsOneWidget);
    expect(legend('legendSold', 'Sold 1'), findsOneWidget);
    expect(legend('legendGuest', 'Guest tickets 2'), findsOneWidget);
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the tab appearing late keeps the tab that is open', (tester) async {
    final api = await pumpApp(tester);
    api.seatingGate = Completer<void>();
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    expect(key('tabSeats'), findsNothing);
    await tester.tap(key('tabDoor'));
    await tester.pumpAndSettle();
    expect(key('codeLabel'), findsOneWidget);
    api.seatingGate!.complete();
    await tester.pumpAndSettle();
    expect(key('tabSeats'), findsOneWidget);
    expect(key('codeLabel'), findsOneWidget, reason: 'still on the Door tab');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a free seat selects and offers Hold only; tapping again unselects', (tester) async {
    await openSeats(tester);
    await tapSeat(tester, 'A:3:1');
    expect(find.text('1 seat selected'), findsOneWidget);
    expect(key('seatsHold'), findsOneWidget);
    expect(key('seatsIssue'), findsNothing);
    expect(key('seatsRelease'), findsNothing);
    expect(goldButtons(tester), 1);
    await tapSeat(tester, 'A:3:1');
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Hold needs a label, calls the API, refreshes the map and clears the selection', (tester) async {
    final api = await openSeats(tester);
    await tapSeats(tester, ['A:3:1', 'A:3:2']);
    expect(find.text('2 seats selected'), findsOneWidget);
    await tester.tap(key('seatsHold'));
    await tester.pumpAndSettle();
    expect(goldButtons(tester, within: find.byType(BottomSheet)), 1, reason: 'the sheet submit is the only gold button');
    await tester.tap(key('holdSubmit'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('hold')), isEmpty);
    await tester.enterText(key('holdLabel'), 'Sponsor');
    await tester.tap(key('holdSubmit'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('hold:A:3:1,A:3:2:Sponsor'));
    expect(key('holdLabel'), findsNothing);
    expect(bar, findsNothing);
    expect(legend('legendAvailable', 'On sale 8'), findsOneWidget);
    expect(legend('legendHeld', 'Held for guests 6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('held seats: Issue is the single gold button, Release is outlined; one seat shows its label', (tester) async {
    await openSeats(tester);
    await tapSeat(tester, 'A:1:5');
    expect(find.text('Held: Sponsor'), findsOneWidget);
    await tapSeat(tester, 'A:1:6');
    expect(find.textContaining('Held:'), findsNothing);
    expect(key('seatsHold'), findsNothing);
    expect(goldButtons(tester), 1);
    expect(tester.widget<FilledButton>(key('seatsIssue')).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(key('seatsRelease')).onPressed, isNotNull);
    await tester.tap(key('seatsClear'));
    await tester.pumpAndSettle();
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Release confirms first, then calls the API and refreshes', (tester) async {
    final api = await openSeats(tester);
    await tapSeats(tester, ['A:1:5', 'A:1:6']);
    await tester.tap(key('seatsRelease'));
    await tester.pumpAndSettle();
    expect(find.text('Put 2 seats back on sale?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('release')), isEmpty);
    expect(find.text('2 seats selected'), findsOneWidget);
    await tester.tap(key('seatsRelease'));
    await tester.pumpAndSettle();
    await tester.tap(key('releaseConfirm'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('release:A:1:5,A:1:6'));
    expect(bar, findsNothing);
    expect(legend('legendAvailable', 'On sale 12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Issue validates, repeats the number, calls the API and the guest list gains rows', (tester) async {
    final api = await openSeats(tester);
    await tapSeats(tester, ['A:1:5', 'A:1:6']);
    await tester.tap(key('seatsIssue'));
    await tester.pumpAndSettle();
    expect(find.text('The guest finds the tickets in the Event 360 app after signing in with this number. No SMS is sent.'), findsOneWidget);
    expect(goldButtons(tester, within: find.byType(BottomSheet)), 1);
    await tester.tap(key('issueSubmit'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));
    await tester.enterText(key('guestName'), 'Aung Aung');
    await tester.enterText(key('guestPhone'), '123');
    await tester.tap(key('issueSubmit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a Myanmar mobile number'), findsOneWidget);
    expect(find.text('Required'), findsNothing);
    await tester.enterText(key('guestPhone'), '09 123 456 789');
    await tester.enterText(key('guestLabel'), 'Family');
    await tester.tap(key('issueSubmit'));
    await tester.pumpAndSettle();
    expect(find.text('Issue 2 guest tickets to 09\u00A0123\u00A0456\u00A0789?'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('issue')), isEmpty);
    await tester.tap(key('issueConfirm'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('issue:A:1:5,A:1:6:Aung Aung:09 123 456 789:Family'));
    expect(key('guestName'), findsNothing);
    expect(bar, findsNothing);
    expect(find.text('2 guest tickets issued'), findsOneWidget);
    expect(key('seatsZoomHint'), findsNothing);
    expect(find.text('Guest tickets (4)'), findsOneWidget, reason: 'the count in the segment follows');
    expect(legend('legendHeld', 'Held for guests 2'), findsOneWidget, reason: 'still on the map');
    await openGuestTickets(tester);
    expect(key('guestTicket-g3'), findsOneWidget);
    expect(key('guestTicket-g4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 400 from the server puts phoneInvalid under the phone field and keeps the sheet', (tester) async {
    final api = await openSeats(tester, setup: (a) => a.rejectPhone = true);
    await tapSeat(tester, 'A:1:5');
    await tester.tap(key('seatsIssue'));
    await tester.pumpAndSettle();
    await tester.enterText(key('guestName'), 'Aung Aung');
    await tester.enterText(key('guestPhone'), '09123456789');
    await tester.tap(key('issueSubmit'));
    await tester.pumpAndSettle();
    await tester.tap(key('issueConfirm'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('issue')), hasLength(1));
    expect(find.text('Enter a Myanmar mobile number'), findsOneWidget);
    expect(key('guestName'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a mixed selection shows the hint and no action', (tester) async {
    await openSeats(tester);
    await tapSeats(tester, ['A:3:1', 'A:1:5']);
    expect(find.text('Select only free seats or only held seats'), findsOneWidget);
    for (final k in ['seatsHold', 'seatsIssue', 'seatsRelease']) {
      expect(key(k), findsNothing, reason: k);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sold and unsold seats cannot be selected', (tester) async {
    await openSeats(tester);
    await tapSeat(tester, 'A:1:4'); // SOLD
    await tapSeat(tester, 'A:2:3'); // UNSOLD
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a held seat without a ticket type disables Issue with a hint; Release still works', (tester) async {
    await openSeats(tester);
    await tapSeats(tester, ['A:1:5', 'A:2:5']);
    expect(find.text('Some held seats have no ticket type'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('seatsIssue')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(key('seatsRelease')).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seats that changed: message, refreshed map, dropped from the selection', (tester) async {
    final api = await openSeats(tester, setup: (a) => a.nextSeatsChanged = 'A:3:2');
    await tapSeats(tester, ['A:3:1', 'A:3:2']);
    await tester.tap(key('seatsHold'));
    await tester.pumpAndSettle();
    await tester.enterText(key('holdLabel'), 'Sponsor');
    await tester.tap(key('holdSubmit'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('hold')), hasLength(1));
    expect(find.text('Some of those seats changed. The map has been updated.'), findsOneWidget);
    expect(key('holdLabel'), findsNothing);
    expect(find.text('1 seat selected'), findsOneWidget);
    expect(legend('legendAvailable', 'On sale 9'), findsOneWidget, reason: 'A:3:2 is sold now');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a release that hits changed seats reports it too', (tester) async {
    await openSeats(tester, setup: (a) => a.nextSeatsChanged = 'A:1:6');
    await tapSeats(tester, ['A:1:5', 'A:1:6']);
    await tester.tap(key('seatsRelease'));
    await tester.pumpAndSettle();
    await tester.tap(key('releaseConfirm'));
    await tester.pumpAndSettle();
    expect(find.text('Some of those seats changed. The map has been updated.'), findsOneWidget);
    expect(find.text('1 seat selected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Revoke confirms, calls the API, the row shows Revoked and loses its button; checked-in has none', (tester) async {
    final api = await openSeats(tester);
    await openGuestTickets(tester);
    expect(key('guestRevoke-g1'), findsOneWidget);
    expect(key('guestTicket-g2'), findsOneWidget);
    expect(key('guestRevoke-g2'), findsNothing, reason: 'checked in');
    expect(find.descendant(of: key('guestTicket-g2'), matching: find.text('CHECKED IN')), findsOneWidget);
    await tester.tap(key('guestRevoke-g1'));
    await tester.pumpAndSettle();
    expect(find.text('Revoke the guest ticket for Daw Mya, Stalls · Row 1 · Seat 4?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('revokeGuest')), isEmpty);
    await tester.tap(key('guestRevoke-g1'));
    await tester.pumpAndSettle();
    await tester.tap(key('revokeConfirm'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('revokeGuest:g1'));
    expect(find.text('Revoked'), findsOneWidget, reason: 'the snack bar');
    expect(find.descendant(of: key('guestTicket-g1'), matching: find.text('REVOKED')), findsOneWidget);
    expect(key('guestRevoke-g1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finance sees map, legend and guest list; taps select nothing; no actions', (tester) async {
    await openSeats(tester, role: 'ORG_FINANCE');
    expect(find.text('You can view seats but not change them'), findsOneWidget);
    expect(legend('legendAvailable', 'On sale 10'), findsOneWidget);
    await tapSeat(tester, 'A:3:1');
    await tapSeat(tester, 'A:1:5');
    expect(bar, findsNothing);
    for (final k in ['seatsHold', 'seatsIssue', 'seatsRelease']) {
      expect(key(k), findsNothing, reason: k);
    }
    await openGuestTickets(tester);
    expect(key('guestTicket-g1'), findsOneWidget);
    expect(key('guestRevoke-g1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('200 seats can be acted on, 201 disables the actions with a reason; zoomed out shows the hint', (tester) async {
    await pumpBig(tester, 201);
    expect(find.text('201 seats selected'), findsOneWidget);
    expect(find.text('Select 200 seats or fewer'), findsOneWidget);
    expect(key('seatsHold'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('seatsHold')).onPressed, isNull, reason: 'visible but disabled');
    expect(key('seatsZoomHint'), findsOneWidget);
    expect(find.text('Zoom in to select seats'), findsOneWidget);
    expect(tester.getRect(key('seatsZoomHint')).bottom, lessThanOrEqualTo(tester.getTopLeft(bar).dy), reason: 'the hint is not hidden under the bar');
    await tester.pumpWidget(const SizedBox());
    await pumpBig(tester, 200);
    expect(find.text('Select 200 seats or fewer'), findsNothing);
    expect(tester.widget<FilledButton>(key('seatsHold')).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the guest list is reachable and Revoke works while seats are selected on the map', (tester) async {
    final api = await openSeats(tester);
    await tapSeats(tester, ['A:3:1', 'A:3:2']);
    expect(find.text('2 seats selected'), findsOneWidget);
    await openGuestTickets(tester);
    expect(bar, findsNothing, reason: 'the bar belongs to the map');
    await tester.tap(key('guestRevoke-g1'));
    await tester.pumpAndSettle();
    await tester.tap(key('revokeConfirm'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('revokeGuest:g1'));
    await tester.tap(key('seatsViewMap'));
    await tester.pumpAndSettle();
    expect(find.text('2 seats selected'), findsOneWidget, reason: 'the selection survived');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dismissing the sheet during a slow request is not possible; the event screen stays and the map refreshes', (tester) async {
    final api = await openSeats(tester);
    api.actionGate = Completer<void>();
    await tapSeat(tester, 'A:3:1');
    await tester.tap(key('seatsHold'));
    await tester.pumpAndSettle();
    await tester.enterText(key('holdLabel'), 'Sponsor');
    await tester.tap(key('holdSubmit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute(); // the back button
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('holdLabel'), findsOneWidget, reason: 'still open while the request runs');
    expect(key('tabSeats'), findsOneWidget);
    api.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(key('holdLabel'), findsNothing);
    expect(key('tabSeats'), findsOneWidget, reason: 'the event screen was not popped');
    expect(legend('legendAvailable', 'On sale 9'), findsOneWidget);
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Guest tickets count leaves out revoked tickets', (tester) async {
    await openSeats(tester, setup: (a) => a.guestRows.add({...a.guestRows.first, 'id': 'g9', 'status': 'VOID'}));
    await tester.tap(key('seatsViewMap'));
    await tester.pumpAndSettle();
    expect(find.text('Guest tickets (2)'), findsOneWidget, reason: 'g1 and g2 are valid; the voided one is not counted');
    await openGuestTickets(tester);
    await tester.tap(key('guestRevoke-g1'));
    await tester.pumpAndSettle();
    await tester.tap(key('revokeConfirm'));
    await tester.pumpAndSettle();
    expect(find.text('Guest tickets (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the legend fades at the right edge while it can scroll on', (tester) async {
    await openSeats(tester);
    double fade() => tester.widget<AnimatedOpacity>(key('legendFade')).opacity;
    expect(fade(), 1);
    await tester.drag(find.ancestor(of: key('legendAvailable'), matching: find.byType(SingleChildScrollView)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.ancestor(of: key('legendAvailable'), matching: find.byType(SingleChildScrollView)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(fade(), 0, reason: 'at the end: no fade');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a selected held seat is handed to the map as selected, with a drawable state', (tester) async {
    await openSeats(tester);
    final layout = SeatLayout.fromJson(seatLayoutJson());
    final sel = layout.seatByKey('A:1:5')!.index, other = layout.seatByKey('A:1:6')!.index;
    var map = tester.widget<SeatMapView>(find.byType(SeatMapView));
    expect(map.states[sel], SeatState.held);
    await tapSeat(tester, 'A:1:5');
    map = tester.widget<SeatMapView>(find.byType(SeatMapView));
    expect(map.selected, {sel});
    expect(map.states[sel], SeatState.available, reason: 'the painter marks selection only on drawable seats');
    expect(map.colors[sel], isNotNull);
    expect(map.states[other], SeatState.held);
    expect(key('legendSelected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a refresh a selected seat that is no longer selectable drops out', (tester) async {
    final api = await openSeats(tester);
    await tapSeats(tester, ['A:3:1', 'A:3:2']);
    final i = api.seatRows.indexWhere((r) => r['seatKey'] == 'A:3:2');
    api.seatRows[i] = {...api.seatRows[i], 'status': 'SOLD'};
    ProviderScope.containerOf(tester.element(find.byType(SeatsTab))).invalidate(orgSeatingProvider((orgId: 'o1', eventId: 'e1')));
    await tester.pumpAndSettle();
    expect(find.text('1 seat selected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('when the seating request fails the Seats tab stays, with a retry', (tester) async {
    final api = await openSeats(tester, setup: (a) => a.failSeating = true); // opens the tab: it is there
    expect(find.text("Couldn't load. Check your connection."), findsOneWidget);
    api.failSeating = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(key('seatsViewMap'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Myanmar: the sheet and bar open without errors', (tester) async {
    await openSeats(tester, lang: 'my');
    await tapSeats(tester, ['A:3:1', 'A:3:2']);
    await tester.tap(key('seatsHold'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ဧည့်သည်အတွက် ထိန်းထားမည်'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an unexpected error in a seat action ends the busy state, shows the load error and the sheet can be closed',
    (tester) async {
      final api = await openSeats(tester, setup: (a) => a.crashHold = true);
      await tapSeat(tester, 'A:3:1');
      await tester.tap(key('seatsHold'));
      await tester.pumpAndSettle();
      await tester.enterText(key('holdLabel'), 'Sponsor');
      await tester.tap(key('holdSubmit'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('hold:A:3:1:Sponsor'));
      expect(
        find.text('Something went wrong. Try again.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(key('holdSubmit')).onPressed,
        isNotNull,
        reason: 'not busy any more',
      );
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      expect(key('holdLabel'), findsNothing, reason: 'the sheet closed');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an unexpected error while revoking shows the load error and frees the list',
    (tester) async {
      final api = await openSeats(tester, setup: (a) => a.crashRevoke = true);
      await openGuestTickets(tester);
      await tester.tap(key('guestRevoke-g1'));
      await tester.pumpAndSettle();
      await tester.tap(key('revokeConfirm'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('revokeGuest:g1'));
      expect(
        find.text('Something went wrong. Try again.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    api.crashRevoke = false;
      await tester.tap(key('guestRevoke-g1'));
      await tester.pumpAndSettle();
      await tester.tap(key('revokeConfirm'));
      await tester.pumpAndSettle();
      expect(
        find.text('Revoked'),
        findsOneWidget,
        reason: 'a second try works: nothing was left busy',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

/// 21 rows x 6 seats at 24-unit spacing; the last row sits at the bottom edge of the layout.
class TallApi extends FakeApi {
  TallApi(super.store);
  static const rows = 21;
  @override
  Future<OrgSeating> orgSeating(String orgId, String eventId) async =>
      OrgSeating.fromJson({
        'layout': {
          'width': 200,
          'height': 30 + (rows - 1) * 24 + 8,
          'sections': [
            {
              'key': 'T',
              'name': 'Tall',
              'kind': 'SEATED',
              'x': 30,
              'y': 30,
              'rows': [
                for (var r = 1; r <= rows; r++)
                  {
                    'label': '$r',
                    'seats': [
                      for (var n = 1; n <= 6; n++) {'n': n},
                    ],
                  },
              ],
            },
          ],
        },
        'seats': [
          for (var r = 1; r <= rows; r++)
            for (var n = 1; n <= 6; n++)
              {
                'seatKey': 'T:$r:$n',
                'status': r <= 2 || r == rows ? 'GUEST_HOLD' : 'AVAILABLE',
                'ticketTypeId': 't1',
                'holdLabel': 'Sponsor',
              },
        ],
        'colors': {'t1': '#2f6fed'},
        'counts': {
          't1': {
            'available': 100,
            'held': 0,
            'offered': 0,
            'guest': 12,
            'sold': 0,
            'comp': 0,
          },
        },
      });
}

void tallTests() {
  testWidgets(
    'held seats selected at 390x844: the lowest seat row can be dragged above the bar and tapped',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'org_lang': 'en'});
      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(sp),
            apiProvider.overrideWithValue(TallApi(MemoryTokenStore())),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Scaffold(
              body: SeatsTab(
                k: (orgId: 'o1', eventId: 'e1'),
                canEdit: true,
                initialSelected: {'T:1:1', 'T:1:2'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layout = SeatLayout.fromJson(
        (await TallApi(MemoryTokenStore()).orgSeating('o', 'e')).layout!,
      );
      final last = layout.seatByKey('T:21:3')!;
      final map = find.byKey(const Key('seatMap'));
      Offset screen() =>
          tester.renderObject<RenderBox>(map).localToGlobal(last.pos);
      double scale() =>
          (tester.getBottomRight(map).dx - tester.getTopLeft(map).dx) / 200;
      // Zoom in on the top rows, where the selection is.
      final first = layout.seatByKey('T:1:3')!;
      await tester.tapAt(
        tester.renderObject<RenderBox>(map).localToGlobal(first.pos),
      );
      await tester.pumpAndSettle();
      expect(scale(), greaterThanOrEqualTo(kSeatTapScale));
      final barTop = tester.getTopLeft(bar).dy;
      final top = tester.getTopLeft(find.byType(SeatMapView)).dy;
      for (var i = 0; i < 40 && screen().dy > barTop - 40; i++) {
        await tester.dragFrom(
          Offset(195, (top + barTop) / 2),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
      }
      expect(
        screen().dy,
        lessThan(barTop - 8),
        reason: 'the lowest row is above the bar',
      );
      await tester.tapAt(screen());
      await tester.pumpAndSettle();
      expect(find.text('3 seats selected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (name, setup) in <(String, void Function(FakeApi))>[
    ('a server error (500)', (a) => a.releaseError = ApiException(500, 'Internal server error')),
    ('an unexpected error', (a) => a.crashRelease = true),
  ]) {
    testWidgets('Release failing with $name says so and keeps the selection', (tester) async {
      final api = await openSeats(tester, setup: setup);
      await tapSeats(tester, ['A:1:5', 'A:1:6']);
      await tester.tap(key('seatsRelease'));
      await tester.pumpAndSettle();
      await tester.tap(key('releaseConfirm'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('release:A:1:5,A:1:6'));
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.text('2 seats selected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a failed Release is not queued behind an older message', (tester) async {
    await openSeats(tester, setup: (a) => a.releaseError = ApiException(500, 'Internal server error'));
    ScaffoldMessenger.of(tester.element(find.byType(SeatsTab))).showSnackBar(const SnackBar(content: Text('Older message'), duration: Duration(seconds: 30)));
    await tester.pump();
    await tapSeats(tester, ['A:1:5', 'A:1:6']);
    tester.widget<OutlinedButton>(key('seatsRelease')).onPressed!(); // the older message covers the bar
    await tester.pumpAndSettle();
    await tester.tap(key('releaseConfirm'));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
