import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_app/app/guide_providers.dart';
import 'package:user_app/app/providers.dart';

import 'event_guide_test.dart';

String location(Harness h) => GoRouter.of(h.tester.element(find.byType(Scaffold).first)).routerDelegate.currentConfiguration.last.matchedLocation;

Future<void> toTickets(Harness h) async {
  h.router.go('/tickets');
  await h.tester.pumpAndSettle();
}

/// Lets the background saver finish (it starts after a frame and awaits the fake API).
Future<void> saverDone(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> savedEvent(String id, {required Duration starts}) => eventJson(id, starts: starts);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  // The event starts 14:30 Yangon on 10 Dec (08:00 UTC) and runs 3 hours. Today opens at 00:00 Yangon = 9 Dec 17:30 UTC.
  void oneEvent(GuideApi a, {String status = 'VALID', String eventStatus = 'PUBLISHED'}) {
    a.eventData['e1'] = eventJson('e1', starts: Duration.zero);
    a.tickets = [ticketJson('tk1', 'e1', starts: Duration.zero, status: status, eventStatus: eventStatus)];
  }

  group('today card and banner', () {
    testWidgets('shows from midnight Yangon until the end, not before or after', (tester) async {
      final cases = <(Duration, bool)>[
        (const Duration(hours: -14, minutes: -31), false), // 17:29 UTC the day before
        (const Duration(hours: -14, minutes: -30), true), // 00:00 Yangon
        (const Duration(hours: 2, minutes: 59), true),
        (const Duration(hours: 3), false), // the end
        (const Duration(days: 1), false),
      ];
      for (final (offset, shown) in cases) {
        final h = await pumpGuide(tester, now: base.add(offset), setup: oneEvent);
        expect(find.byKey(const Key('homeTodayBanner')), shown ? findsOneWidget : findsNothing, reason: 'home at $offset');
        await toTickets(h);
        expect(find.byKey(const Key('todayCard-e1')), shown ? findsOneWidget : findsNothing, reason: 'tickets at $offset');
        await h.finish();
      }
    });

    testWidgets('two events today: a card each, earliest first; one banner for the earliest', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['late'] = eventJson('late', starts: const Duration(hours: 2));
        a.eventData['early'] = eventJson('early', starts: Duration.zero);
        a.tickets = [
          ticketJson('tk-late', 'late', starts: const Duration(hours: 2)),
          ticketJson('tk-early', 'early', starts: Duration.zero),
        ];
      });
      expect(find.byKey(const Key('homeTodayBanner')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('homeTodayBanner')), matching: find.text('Event early')), findsOneWidget);
      expect(find.text('Event late'), findsNothing);
      expect(goldButtons(tester), isEmpty);
      await toTickets(h);
      expect(find.byKey(const Key('todayCard-early')), findsOneWidget);
      expect(find.byKey(const Key('todayCard-late')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('todayCard-early'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('todayCard-late'))).dy));
      expect(tester.getTopLeft(find.byKey(const Key('todayCard-late'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('ticketGroup-early'))).dy));
      expect(find.text('Happening today'), findsNWidgets(2));
      expect(find.text('Open your guide'), findsNWidgets(2));
      await h.finish();
    });

    testWidgets('signed out: no banner and no card', (tester) async {
      final h = await pumpGuide(tester, signedIn: false, now: base, setup: oneEvent);
      expect(find.byKey(const Key('homeTodayBanner')), findsNothing);
      await toTickets(h);
      expect(find.byKey(const Key('todayCard-e1')), findsNothing);
      await h.finish();
    });

    testWidgets('only refunded tickets, or a cancelled event: no card', (tester) async {
      var h = await pumpGuide(tester, now: base, setup: (a) => oneEvent(a, status: 'REFUNDED'));
      expect(find.byKey(const Key('homeTodayBanner')), findsNothing);
      await toTickets(h);
      expect(find.byKey(const Key('todayCard-e1')), findsNothing);
      await h.finish();
      h = await pumpGuide(tester, now: base, setup: (a) => oneEvent(a, eventStatus: 'CANCELLED'));
      expect(find.byKey(const Key('homeTodayBanner')), findsNothing);
      await h.finish();
    });

    testWidgets('a checked-in ticket still shows the card; tapping the banner and the card opens the guide', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) => oneEvent(a, status: 'CHECKED_IN'));
      await tester.tap(find.byKey(const Key('homeTodayBanner')));
      await tester.pumpAndSettle();
      expect(location(h), '/event/e1/guide');
      await h.finish();
      final h2 = await pumpGuide(tester, now: base, setup: oneEvent);
      await toTickets(h2);
      await tester.tap(find.byKey(const Key('todayCard-e1')));
      await tester.pumpAndSettle();
      expect(location(h2), '/event/e1/guide');
      await h2.finish();
    });

    testWidgets('the banner does not move Discover for everyone else', (tester) async {
      final h = await pumpGuide(tester, now: base.add(const Duration(days: 30)), setup: oneEvent);
      final search = tester.getTopLeft(find.byType(TextField).evaluate().isEmpty ? find.byIcon(Icons.search).first : find.byType(TextField).first);
      await h.finish();
      final h2 = await pumpGuide(tester, now: base, setup: oneEvent);
      final searchWith = tester.getTopLeft(find.byType(TextField).evaluate().isEmpty ? find.byIcon(Icons.search).first : find.byType(TextField).first);
      expect(searchWith.dy, greaterThan(search.dy));
      await h2.finish();
    });
  });

  group('saving upcoming events', () {
    List<String> savedIds(Harness h) => h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)).map((k) => k.substring(EventCache.prefix.length)).toList()..sort();

    testWidgets('each upcoming event is fetched once and saved with its announcements', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        for (final id in ['a', 'b']) {
          a.eventData[id] = eventJson(id, starts: const Duration(days: 3));
        }
        a.announcementData['a'] = [announcement('n1', 'Gates open', const Duration(hours: 1))];
        a.tickets = [ticketJson('ta1', 'a', starts: const Duration(days: 3)), ticketJson('ta2', 'a', starts: const Duration(days: 3)), ticketJson('tb', 'b', starts: const Duration(days: 4))];
      });
      await saverDone(tester);
      expect(h.api.rawCalls, 2);
      expect(savedIds(h), ['a', 'b']);
      final cache = h.container.read(eventCacheProvider);
      expect(cache.read('a')!.announcements.single.title, 'Gates open');
      // Pull to refresh: both are fresh, nothing more is fetched.
      await h.container.read(myTicketsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await saverDone(tester);
      expect(h.api.rawCalls, 2);
      await h.finish();
    });

    testWidgets('an event saved within the hour is skipped; an older copy is refreshed', (tester) async {
      final h = await pumpGuide(tester, now: base, prefs: seedPrefs(saved: {
        'fresh': (savedEvent('fresh', starts: const Duration(days: 3)), const [], base.subtract(const Duration(minutes: 30))),
        'old': (savedEvent('old', starts: const Duration(days: 3)), const [], base.subtract(const Duration(hours: 2))),
      }), setup: (a) {
        a.eventData['fresh'] = eventJson('fresh', starts: const Duration(days: 3));
        a.eventData['old'] = eventJson('old', starts: const Duration(days: 3));
        a.tickets = [ticketJson('t1', 'fresh', starts: const Duration(days: 3)), ticketJson('t2', 'old', starts: const Duration(days: 3))];
      });
      await saverDone(tester);
      expect(h.api.rawCalls, 1);
      final cache = h.container.read(eventCacheProvider);
      expect(cache.read('old')!.savedAt, base);
      expect(cache.read('fresh')!.savedAt, base.subtract(const Duration(minutes: 30)));
      await h.finish();
    });

    testWidgets('never more than 10 events (the earliest ten)', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        for (var i = 1; i <= 12; i++) {
          a.eventData['ev$i'] = eventJson('ev$i', starts: Duration(days: i));
        }
        a.tickets = [for (var i = 12; i >= 1; i--) ticketJson('t$i', 'ev$i', starts: Duration(days: i))];
      });
      await saverDone(tester);
      expect(h.api.rawCalls, 10);
      expect(savedIds(h), hasLength(10));
      expect(savedIds(h), isNot(contains('ev11')));
      expect(savedIds(h), isNot(contains('ev12')));
      await h.finish();
    });

    testWidgets('prunes an event that ended 8 days ago, keeps one that ended 6 days ago', (tester) async {
      final h = await pumpGuide(tester, now: base, prefs: seedPrefs(saved: {
        'gone': (savedEvent('gone', starts: const Duration(days: -8, hours: -3)), const [], base.subtract(const Duration(days: 9))),
        'recent': (savedEvent('recent', starts: const Duration(days: -6, hours: -3)), const [], base.subtract(const Duration(days: 7))),
      }), setup: (a) {
        a.eventData['next'] = eventJson('next', starts: const Duration(days: 2));
        a.tickets = [
          ticketJson('t1', 'gone', starts: const Duration(days: -8, hours: -3)),
          ticketJson('t2', 'recent', starts: const Duration(days: -6, hours: -3)),
          ticketJson('t3', 'next', starts: const Duration(days: 2)),
        ];
      });
      await saverDone(tester);
      expect(savedIds(h), ['next', 'recent']);
      await h.finish();
    });

    testWidgets('a failing fetch does not stop the others; announcements 403 still saves the event', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['ok1'] = eventJson('ok1', starts: const Duration(days: 2));
        a.eventData['ok2'] = eventJson('ok2', starts: const Duration(days: 4));
        a.announcementsError = 403;
        // 'bad' has no event data: 404
        a.tickets = [ticketJson('t1', 'ok1', starts: const Duration(days: 2)), ticketJson('t0', 'bad', starts: const Duration(days: 3)), ticketJson('t2', 'ok2', starts: const Duration(days: 4))];
      });
      await saverDone(tester);
      expect(h.api.rawCalls, 3);
      expect(savedIds(h), ['ok1', 'ok2']);
      expect(h.container.read(eventCacheProvider).read('ok1')!.announcements, isEmpty);
      expect(find.byType(Scaffold), findsWidgets);
      await h.finish();
    });

    testWidgets('nothing is fetched when the tickets came from the offline cache', (tester) async {
      final h = await pumpGuide(tester, now: base, prefs: seedPrefs(tickets: [ticketJson('t1', 'a', starts: const Duration(days: 3))]), setup: (a) {
        a.offline = true;
        a.eventData['a'] = eventJson('a', starts: const Duration(days: 3));
      });
      await toTickets(h);
      await saverDone(tester);
      expect(h.api.rawCalls, 0);
      expect(savedIds(h), isEmpty);
      await h.finish();
    });

    testWidgets('nothing is fetched when signed out, and a refused ticket does not count', (tester) async {
      final h = await pumpGuide(tester, signedIn: false, now: base, setup: (a) {
        a.eventData['a'] = eventJson('a', starts: const Duration(days: 3));
        a.tickets = [ticketJson('t1', 'a', starts: const Duration(days: 3))];
      });
      await toTickets(h);
      await saverDone(tester);
      expect(h.api.rawCalls, 0);
      await h.finish();
      final h2 = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['a'] = eventJson('a', starts: const Duration(days: 3));
        a.tickets = [ticketJson('t1', 'a', starts: const Duration(days: 3), status: 'REFUNDED')];
      });
      await saverDone(tester);
      expect(h2.api.rawCalls, 0);
      await h2.finish();
    });
  });

  group('large text', () {
    for (final lang in ['en', 'my']) {
      for (final where in ['tickets', 'home']) {
        testWidgets('today card/banner on $where has no overflow at 390x844, scale 2.0, $lang', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final h = await pumpGuide(tester, lang: lang, now: base, setup: (a) {
            a.eventData['e1'] = eventJson('e1', starts: Duration.zero);
            a.eventData['e2'] = eventJson('e2', starts: const Duration(hours: 1));
            a.tickets = [ticketJson('tk1', 'e1', starts: Duration.zero), ticketJson('tk2', 'e2', starts: const Duration(hours: 1))];
          });
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          await tester.pumpAndSettle();
          if (where == 'tickets') await toTickets(h);
          expect(tester.takeException(), isNull);
          expect(find.byKey(Key(where == 'home' ? 'homeTodayBanner' : 'todayCard-e1')), findsOneWidget);
          await tester.fling(find.byType(Scrollable).first, const Offset(0, -2000), 3000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await h.finish();
        });
      }
    }
  });
}
