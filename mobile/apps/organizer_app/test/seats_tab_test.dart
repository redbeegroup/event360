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

  test('isMyanmarMobile accepts the usual spellings only', () {
    for (final ok in ['09123456789', '09 123 456 789', '+959123456789', '959-123-456-789', '0912345678']) {
      expect(isMyanmarMobile(ok), isTrue, reason: ok);
    }
    for (final bad in ['123', '08123456789', '0912345', '09123456789012', '']) {
      expect(isMyanmarMobile(bad), isFalse, reason: bad);
    }
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
    expect(find.text('Issue 2 guest tickets to 09 123 456 789?'), findsOneWidget);
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
    expect(find.text('Revoke the guest ticket for Daw Mya?'), findsOneWidget);
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
}
