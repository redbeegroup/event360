import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/screens/event/guests_tab.dart';

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
    expect(find.text('1000 of 3000 checked in'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(40));
    await tester.enterText(find.byKey(const Key('guestSearch')), '0977002999');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guestRow-g2999')), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
