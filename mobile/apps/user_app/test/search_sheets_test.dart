import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_app/screens/event_detail_screen.dart';

import 'event_guide_test.dart' hide main;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  group('search and sheets', () {
    Map<String, dynamic> json() => eventJson('srch', starts: const Duration(days: 3), extra: {
          'sessions': [
            for (var i = 0; i < 300; i++) session('s$i', 'Workshop $i', Duration(days: 3, minutes: i), Duration(days: 3, minutes: i + 30)),
            // The same id twice (bad data): an id lookup would open the first one for the second one's hit.
            session('dup', 'Twin A', const Duration(days: 4), const Duration(days: 4, hours: 1)),
            session('dup', 'Twin B', const Duration(days: 4, hours: 2), const Duration(days: 4, hours: 3)),
          ],
          'performers': [
            {'name': '', 'nameMy': null, 'role': 'Mystery guest', 'bio': 'Unannounced'},
          ],
        });

    void setUp(GuideApi a) {
      a.eventData['srch'] = json();
      a.tickets = [ticketJson('tk-srch', 'srch', starts: const Duration(days: 3))];
    }

    Future<void> search(WidgetTester tester, String q) async {
      await tester.tap(find.byKey(const Key('eventSearchAction')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('eventSearchField')), q);
      await tester.pumpAndSettle();
    }

    testWidgets('results are built lazily', (tester) async {
      final h = await pumpGuide(tester, setup: setUp, route: '/event/srch/guide');
      await search(tester, 'workshop');
      expect(find.byKey(const Key('searchHit-schedule-0')), findsOneWidget);
      expect(find.byKey(const Key('searchHit-schedule-250')), findsNothing, reason: 'far below the fold: not built yet');
      await h.finish();
    });

    testWidgets('a hit opens the session at its index even when an id appears twice', (tester) async {
      final h = await pumpGuide(tester, setup: setUp, route: '/event/srch/guide');
      await search(tester, 'twin b');
      await tester.tap(find.byKey(const Key('searchHit-schedule-301')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('searchSessionSheet'));
      expect(find.descendant(of: sheet, matching: find.text('Twin B')), findsOneWidget);
      await h.finish();
    });

    for (final route in ['/event/srch/guide', '/event/srch']) {
      testWidgets('a performer without a name opens a sheet with a neutral avatar (from search, $route)', (tester) async {
        final h = await pumpGuide(tester, setup: setUp, route: route);
        await search(tester, 'mystery');
        await tester.tap(find.byKey(const Key('searchHit-lineup-0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Mystery guest'), findsWidgets);
        expect(find.descendant(of: find.byType(CircleAvatar), matching: find.byIcon(Icons.person_outline)), findsOneWidget);
        await h.finish();
      });
    }

    testWidgets('a performer without a name on the event page opens the sheet', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        a.eventData['srch'] = eventJson('srch', starts: const Duration(days: 3), extra: {
          'performers': [
            {'name': '', 'nameMy': null, 'role': 'Mystery guest', 'bio': 'Unannounced'},
          ],
        });
        a.tickets = [ticketJson('tk-srch', 'srch', starts: const Duration(days: 3))];
      }, route: '/event/srch');
      expect(find.byType(EventDetailScreen), findsOneWidget);
      final tile = find.text('Mystery guest');
      for (var i = 0; i < 30 && tile.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(tile, findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Unannounced'), findsOneWidget, reason: 'the sheet is open (the bio is only in the sheet)');
      await h.finish();
    });
  });
}
