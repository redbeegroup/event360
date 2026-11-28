
import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_app/app/guide_providers.dart';
import 'package:user_app/app/providers.dart';
import 'package:user_app/screens/event_guide_screen.dart';

import 'event_guide_test.dart' hide main;

final concertTicket = ticketJson('tk-concert-1', 'concert');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  group('guide', () {
    testWidgets('a 401 from the announcements shows the event without them', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        setUpConcert(a);
        a.announcementsError = 401;
      }, route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsOneWidget);
      expect(find.byKey(const Key('guideStatus')), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await h.finish();
    });

    testWidgets('a server error on the event serves the saved copy, labelled', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: seedPrefs(tickets: [concertTicket], saved: {'concert': (eventJson('concert', starts: const Duration(days: 3)), const [], base)}),
        setup: (a) {
          a.tickets = [concertTicket];
          a.eventStatusError = 503;
        },
        route: '/event/concert/guide',
      );
      expect(find.byKey(const Key('guideSavedCopy')), findsOneWidget);
      expect(find.byKey(const Key('guideStatus')), findsOneWidget);
      await h.finish();
    });

    testWidgets('a server error with no saved copy is still an error', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        setUpConcert(a);
        a.eventStatusError = 503;
      }, route: '/event/concert/guide');
      expect(find.byKey(const Key('guideSavedCopy')), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await h.finish();
    });

    testWidgets('a saved copy dated after the phone clock moved back is refetched, not trusted', (tester) async {
      // Saved "in the future" (the clock was set back a day): the old check (difference < 1 h) would keep it for ever.
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: seedPrefs(tickets: [concertTicket], saved: {'concert': (eventJson('concert', starts: const Duration(days: 3)), const [], base.add(const Duration(days: 1)))}),
        setup: (a) => setUpConcert(a),
      );
      await tester.pumpAndSettle();
      expect(h.api.rawCalls, greaterThan(0));
      expect(h.container.read(eventCacheProvider).read('concert')!.savedAt, base);
      await h.finish();
    });
  });

  group('today events', () {
    testWidgets('notifies only when the set of today events changes, not every minute', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['e1'] = eventJson('e1', starts: Duration.zero);
        a.tickets = [ticketJson('tk1', 'e1', starts: Duration.zero)];
      });
      final seen = <List<MyTicket>>[];
      final sub = h.container.listen(todayEventsProvider, (_, next) => seen.add(next));
      addTearDown(sub.close);
      expect(sub.read().map((t) => t.eventId), ['e1']);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(minutes: 1));
      }
      expect(seen, isEmpty, reason: 'five recomputations, one unchanged list');
      h.now = () => base.add(const Duration(hours: 3, minutes: 1)); // the event is over
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(seen, hasLength(1));
      expect(seen.single, isEmpty);
      sub.close();
      await h.finish();
    });
  });
}
