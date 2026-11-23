import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:organizer_app/app/providers.dart';
import 'package:organizer_app/l10n/app_localizations.dart';
import 'package:organizer_app/screens/event/guests_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' hide main;

Future<FakeApi> openGuests(WidgetTester tester, {String role = 'ORG_OWNER', bool open = true, void Function(FakeApi)? setup, String lang = 'en'}) async {
  final api = await pumpApp(tester, role: role, eventOpen: open, lang: lang);
  setup?.call(api);
  await tester.tap(find.text('Inya Lake Live o1'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('tabGuests')));
  await tester.pumpAndSettle();
  return api;
}

Future<void> openRow(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('guestRow-$id')));
  await tester.pumpAndSettle();
}

Map<String, dynamic> aRow(String id) => {'id': id, 'status': 'VALID', 'createdAt': '2026-11-20T04:00:00.000Z', 'isComplimentary': false, 'ticketType': {'name': 'Standing'}};

Finder status(String id, String label) => find.descendant(of: find.byKey(Key('guestRow-$id')), matching: find.text(label.toUpperCase()));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  OrgEvent event(String status, DateTime start, DateTime end) =>
      OrgEvent(id: 'e', slug: 's', title: 't', status: status, startsAt: start, endsAt: end);

  test('checkInOpen: published or ongoing, from 24h before start to 12h after end', () {
    final start = DateTime.utc(2026, 12, 1, 12);
    final end = DateTime.utc(2026, 12, 1, 18);
    bool at(String s, DateTime now) => checkInOpen(event(s, start, end), now);
    expect(at('PUBLISHED', start.subtract(const Duration(hours: 24))), isTrue);
    expect(at('PUBLISHED', start.subtract(const Duration(hours: 24, seconds: 1))), isFalse);
    expect(at('ONGOING', end.add(const Duration(hours: 12))), isTrue);
    expect(at('ONGOING', end.add(const Duration(hours: 12, seconds: 1))), isFalse);
    expect(at('DRAFT', start), isFalse);
    expect(at('COMPLETED', start), isFalse);
  });

  testWidgets('header counts exclude cancelled tickets; order is not in, in, cancelled', (tester) async {
    await openGuests(tester);
    expect(find.text('2 of 5 checked in'), findsOneWidget);
    final ys = [for (final id in ['a1', 'a6', 'a2', 'a4', 'a3', 'a5']) tester.getTopLeft(find.byKey(Key('guestRow-$id'))).dy];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'Aung Min, Daw Khin, Zaw Win, Bo Bo, Hnin Si, Cherry');
    expect(find.text('Cancelled'.toUpperCase()), findsOneWidget);
    expect(find.text('Guest'.toUpperCase()), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search by phone digits, name and seat; no match message', (tester) async {
    await openGuests(tester);
    await tester.enterText(find.byKey(const Key('guestSearch')), '0991');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a1')), findsOneWidget);
    expect(find.byKey(const Key('guestRow-a2')), findsNothing);
    await tester.enterText(find.byKey(const Key('guestSearch')), 'hnin');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a3')), findsOneWidget);
    expect(find.byKey(const Key('guestRow-a1')), findsNothing);
    await tester.enterText(find.byKey(const Key('guestSearch')), 'row c');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('guestSearch')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No one matches'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Not checked in" chip hides checked-in and cancelled rows', (tester) async {
    await openGuests(tester);
    await tester.tap(find.byKey(const Key('guestFilterNotIn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a1')), findsOneWidget);
    expect(find.byKey(const Key('guestRow-a3')), findsNothing);
    expect(find.byKey(const Key('guestRow-a5')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('check in a valid ticket: gate is "Organizer app", row becomes Checked in', (tester) async {
    final api = await openGuests(tester);
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(api.calls, ['checkin:a1:Organizer app']);
    expect(find.text('Aung Min is checked in'), findsOneWidget);
    expect(status('a1', 'Checked in'), findsOneWidget);
    expect(find.text('3 of 5 checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('already checked in on the server: informational message, not an error', (tester) async {
    final api = await openGuests(tester);
    await openRow(tester, 'a2');
    // Someone else checked this ticket in after the list was loaded.
    final i = api.attendeesList.indexWhere((a) => a['id'] == 'a2');
    api.attendeesList[i] = {...api.attendeesList[i], 'status': 'CHECKED_IN'};
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Already checked in at'), findsOneWidget);
    expect(find.textContaining('Gate A'), findsOneWidget);
    expect(find.byKey(const Key('guestError')), findsNothing);
    expect(status('a2', 'Checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no connection: message shown, row stays Not in, retry works', (tester) async {
    final api = await openGuests(tester, setup: (a) => a.failCheckIn = true);
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(find.text('Not checked in — no connection. Try again.'), findsOneWidget);
    api.failCheckIn = false;
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(find.text('Aung Min is checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('undo asks first, then the row is Not in again', (tester) async {
    final api = await openGuests(tester);
    await openRow(tester, 'a3');
    expect(find.byKey(const Key('guestCheckIn')), findsNothing);
    await tester.tap(find.byKey(const Key('guestUndo')));
    await tester.pumpAndSettle();
    expect(find.text('Undo the check-in for Hnin Si?'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(find.byKey(const Key('guestUndoConfirm')));
    await tester.pumpAndSettle();
    expect(api.calls, ['undo:a3']);
    expect(status('a3', 'Not in'), findsOneWidget);
    expect(find.text('1 of 5 checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finance sees the details but no Check in or Undo', (tester) async {
    await openGuests(tester, role: 'ORG_FINANCE');
    await openRow(tester, 'a1');
    expect(find.byKey(const Key('guestCheckIn')), findsNothing);
    expect(find.text('Aung Min'), findsWidgets);
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();
    await openRow(tester, 'a3');
    expect(find.byKey(const Key('guestUndo')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('outside the check-in window: no actions, explanation shown', (tester) async {
    await openGuests(tester, open: false);
    await openRow(tester, 'a1');
    expect(find.byKey(const Key('guestCheckIn')), findsNothing);
    expect(find.text('Check-in opens one day before the event'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openRow(tester, 'a3');
    expect(find.byKey(const Key('guestUndo')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Call only when there is a phone number', (tester) async {
    await openGuests(tester);
    await openRow(tester, 'a1');
    expect(find.byKey(const Key('guestCall')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openRow(tester, 'a6'); // complimentary guest, no holder
    expect(find.byKey(const Key('guestCall')), findsNothing);
    expect(find.byKey(const Key('guestPhone')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unknown status from a newer API renders as Cancelled', (tester) async {
    await openGuests(tester, setup: (a) => a.attendeesList.add({...a.attendeesList.first, 'id': 'a7', 'status': 'TRANSFERRED'}));
    expect(status('a7', 'Cancelled'), findsOneWidget);
    expect(find.text('2 of 5 checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('3,000 tickets: lazy list, search stays fast', (tester) async {
    await openGuests(tester, setup: (a) {
      a.attendeesList
        ..clear()
        ..addAll([for (var i = 0; i < 3000; i++) {'id': 'g$i', 'status': i % 3 == 0 ? 'CHECKED_IN' : 'VALID', 'createdAt': '2026-11-20T04:00:00.000Z', 'isComplimentary': false, 'holder': {'displayName': 'Guest ${i.toString().padLeft(4, '0')}', 'phone': '0977${i.toString().padLeft(6, '0')}'}, 'ticketType': {'name': 'Standing'}}]);
    });
    expect(find.text('1,000 of 3,000 checked in'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(40));
    await tester.enterText(find.byKey(const Key('guestSearch')), '0977002999');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-g2999')), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('telNumber strips spaces, dashes and brackets', () {
    expect(telNumber('09 912-345 67'), '0991234567');
    expect(telNumber('+95 (9) 912 345'), '+959912345');
  });

  testWidgets('equal names keep a stable order (created, then id)', (tester) async {
    await openGuests(tester, setup: (a) {
      a.attendeesList
        ..clear()
        ..addAll([
          for (final id in ['z2', 'z3', 'z1']) {...aRow(id), 'holder': {'displayName': 'Same Name', 'phone': null}},
        ]);
    });
    final ys = [for (final id in ['z1', 'z2', 'z3']) tester.getTopLeft(find.byKey(Key('guestRow-$id'))).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown refusal result shows the generic text, not the raw code', (tester) async {
    await openGuests(tester, setup: (a) => a.refuseWith = 'WRONG_EVENT');
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(find.text("Can't check in this ticket"), findsOneWidget);
    expect(find.textContaining('WRONG_EVENT'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unexpected error shows the generic message in the sheet', (tester) async {
    await openGuests(tester, setup: (a) => a.crashCheckIn = true);
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestError')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event not loaded: the Guests list still shows, with no actions', (tester) async {
    SharedPreferences.setMockInitialValues({'org_lang': 'en'});
    final sp = await SharedPreferences.getInstance();
    final api = FakeApi(MemoryTokenStore());
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(sp), apiProvider.overrideWithValue(api)],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: GuestsTab(k: (orgId: 'o1', eventId: 'e1'), canEdit: true, event: null)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a1')), findsOneWidget);
    await openRow(tester, 'a1');
    expect(find.byKey(const Key('guestCheckIn')), findsNothing);
    expect(find.text('Check-in opens one day before the event'), findsOneWidget);
  });

  OrgEvent liveEvent() => event('PUBLISHED', DateTime.now().subtract(const Duration(hours: 1)), DateTime.now().add(const Duration(hours: 3)));

  Future<(FakeApi, ProviderContainer)> pumpTab(WidgetTester tester, OrgEvent ev, {void Function(FakeApi)? setup}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'org_lang': 'en'});
    final sp = await SharedPreferences.getInstance();
    final api = FakeApi(MemoryTokenStore());
    setup?.call(api);
    await tester.pumpWidget(ProviderScope(
      overrides: [prefsProvider.overrideWithValue(sp), apiProvider.overrideWithValue(api)],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: GuestsTab(k: (orgId: 'o1', eventId: 'e1'), canEdit: true, event: ev)),
      ),
    ));
    await tester.pumpAndSettle();
    return (api, ProviderScope.containerOf(tester.element(find.byType(GuestsTab))));
  }

  testWidgets('a slow check-in cannot be dismissed; when it completes the row is Checked in and the message shows', (tester) async {
    final (api, _) = await pumpTab(tester, liveEvent());
    api.checkInGate = Completer<void>();
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute(); // the back button
    await tester.pump(const Duration(milliseconds: 300));
    await tester.fling(find.byKey(const Key('guestCheckIn')), const Offset(0, 600), 2000); // a swipe down
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('guestCheckIn')), findsOneWidget, reason: 'still open while the request runs');
    api.checkInGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestCheckIn')), findsNothing);
    expect(find.text('Aung Min is checked in'), findsOneWidget);
    expect(status('a1', 'Checked in'), findsOneWidget);
    expect(find.text('3 of 5 checked in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a slow check-in that fails shows the no-connection message', (tester) async {
    final (api, _) = await pumpTab(tester, liveEvent());
    api.checkInGate = Completer<void>();
    api.failCheckIn = true;
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('guestCheckIn')), findsOneWidget);
    api.checkInGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Not checked in — no connection. Try again.'), findsOneWidget);
    expect(status('a1', 'Not in'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('guestCheckIn'))).onPressed, isNotNull, reason: 'free to retry');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('check-in and undo also reload the guest tickets', (tester) async {
    final (api, c) = await pumpTab(tester, liveEvent());
    final k = (orgId: 'o1', eventId: 'e1');
    final sub = c.listen(guestTicketsProvider(k), (_, __) {});
    await c.read(guestTicketsProvider(k).future);
    final before = c.read(guestTicketsProvider(k));
    await openRow(tester, 'a1');
    await tester.tap(find.byKey(const Key('guestCheckIn')));
    await tester.pumpAndSettle();
    expect(identical(c.read(guestTicketsProvider(k)), before), isFalse, reason: 'reloaded after the check-in');
    final afterCheckIn = c.read(guestTicketsProvider(k));
    await openRow(tester, 'a3');
    await tester.tap(find.byKey(const Key('guestUndo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guestUndoConfirm')));
    await tester.pumpAndSettle();
    expect(identical(c.read(guestTicketsProvider(k)), afterCheckIn), isFalse, reason: 'reloaded after the undo');
    expect(api.calls, ['checkin:a1:Organizer app', 'undo:a3']);
    sub.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('searching a seat does not match phone numbers by its digits', (tester) async {
    await openGuests(tester, setup: (a) {
      a.attendeesList.add({...aRow('s1'), 'seatLabel': 'Balcony · A12', 'holder': {'displayName': 'Seat Holder', 'phone': '09770000000'}});
    });
    await tester.enterText(find.byKey(const Key('guestSearch')), 'A12');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-s1')), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, 1, reason: 'a1 and a2 have 12 in their phones but are not seat A12');
    await tester.enterText(find.byKey(const Key('guestSearch')), 'row c 12');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a2')), findsNothing);
    expect(find.byKey(const Key('guestRow-a1')), findsNothing);
    await tester.enterText(find.byKey(const Key('guestSearch')), '0991');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-a1')), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, 1);
    await tester.enterText(find.byKey(const Key('guestSearch')), '+95 (9) 912');
    await tester.pumpAndSettle();
    expect(find.text('No one matches'), findsOneWidget, reason: 'phone-like queries still use the digits');
    await tester.pumpWidget(const SizedBox());
  });

  test('checkInHasEnded: after the window, or not live although it has started', () {
    final start = DateTime.utc(2026, 12, 1, 12);
    final end = DateTime.utc(2026, 12, 1, 18);
    bool at(String s, DateTime now) => checkInHasEnded(event(s, start, end), now);
    expect(at('PUBLISHED', start.subtract(const Duration(days: 3))), isFalse, reason: 'not yet open');
    expect(at('PUBLISHED', end.add(const Duration(hours: 12))), isFalse);
    expect(at('PUBLISHED', end.add(const Duration(hours: 12, seconds: 1))), isTrue);
    expect(at('CANCELLED', start.add(const Duration(hours: 1))), isTrue);
    expect(at('COMPLETED', end), isTrue);
    expect(at('CANCELLED', start.subtract(const Duration(days: 3))), isFalse, reason: 'not started: the old text');
  });

  testWidgets('the closed explanation says Check-in has closed after the window or for a completed event', (tester) async {
    final now = DateTime.now();
    await pumpTab(tester, event('PUBLISHED', now.subtract(const Duration(days: 3)), now.subtract(const Duration(days: 2))));
    await openRow(tester, 'a1');
    expect(find.text('Check-in has closed'), findsOneWidget);
    expect(find.text('Check-in opens one day before the event'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester, event('COMPLETED', now.subtract(const Duration(hours: 5)), now.subtract(const Duration(hours: 1))));
    await openRow(tester, 'a1');
    expect(find.text('Check-in has closed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester, event('PUBLISHED', now.add(const Duration(days: 5)), now.add(const Duration(days: 5, hours: 3))));
    await openRow(tester, 'a1');
    expect(find.text('Check-in opens one day before the event'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / ((la > lb ? lb : la) + 0.05);
  }

  for (final dark in [false, true]) {
    testWidgets('the selected Not checked in chip is readable (${dark ? 'dark' : 'light'} theme)', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await openGuests(tester);
      await tester.tap(find.byKey(const Key('guestFilterNotIn')));
      await tester.pumpAndSettle();
      final chip = tester.widget<FilterChip>(find.byKey(const Key('guestFilterNotIn')));
      final ctx = tester.element(find.byKey(const Key('guestFilterNotIn')));
      final fill = Theme.of(ctx).chipTheme.selectedColor!;
      final label = chip.labelStyle!.color!;
      expect(contrast(label, fill), greaterThanOrEqualTo(4.5));
      expect(contrast(chip.checkmarkColor!, fill), greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the attendee sheet has no drag handle (it cannot be dragged away)', (tester) async {
    await openGuests(tester);
    await openRow(tester, 'a1');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle, isNot(true));
    await tester.pumpWidget(const SizedBox());
  });
}
