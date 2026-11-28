import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'event_guide_test.dart' hide main;
import 'event_search_test.dart' show openSearch, typeQuery, setUpSearchable, hit;
import 'today_test.dart' show toTickets, location;

const _recording = {'id': 'a0000000-0000-0000-0000-000000000001', 'sessionId': null, 'title': 'Highlights', 'titleMy': null, 'durationSec': 125, 'availableUntil': null};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  final after = base.add(const Duration(days: 3));

  void ended(GuideApi a, {bool recordings = false}) {
    a.eventData['fest'] = festivalJson();
    a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
    if (recordings) a.streamData['fest'] = {'live': [], 'recordings': [_recording]};
  }

  group('ended guide', () {
    for (final recordings in [false, true]) {
      testWidgets('thank you sits under the status ${recordings ? 'with' : 'without'} recordings', (tester) async {
        final h = await pumpGuide(tester, now: after, setup: (a) => ended(a, recordings: recordings), route: '/event/fest/guide');
        expect(find.text('Thank you for coming'), findsOneWidget);
        final status = tester.getBottomLeft(find.byKey(const Key('guideStatus'))).dy;
        final thanks = tester.getTopLeft(find.byKey(const Key('guideThanks'))).dy;
        expect(thanks, greaterThanOrEqualTo(status));
        expect(thanks - status, lessThan(24), reason: 'directly under the status line');
        expect(thanks, lessThan(tester.getTopLeft(find.byKey(const Key('guideTickets'))).dy));
        expect(find.byKey(const Key('guideRecordings')), recordings ? findsOneWidget : findsNothing);
        expect(find.text('Highlights'), recordings ? findsOneWidget : findsNothing);
        await h.finish();
      });
    }

    testWidgets('Show ticket is an outline button once ended, gold before', (tester) async {
      final h = await pumpGuide(tester, now: after, setup: ended, route: '/event/fest/guide');
      expect(find.byKey(const Key('guideShowTicket')), findsOneWidget);
      expect(tester.widget(find.byKey(const Key('guideShowTicket'))), isA<OutlinedButton>());
      expect(find.descendant(of: find.byKey(const Key('guideList')), matching: find.byType(FilledButton)), findsNothing, reason: 'no gold button');
      await h.finish();
      final h2 = await pumpGuide(tester, now: base, setup: ended, route: '/event/fest/guide');
      expect(tester.widget(find.byKey(const Key('guideShowTicket'))), isA<FilledButton>());
      await h2.finish();
    });
  });

  group('status line digits', () {
    testWidgets('Myanmar numerals in Burmese, Latin in English', (tester) async {
      Future<String> status(String lang) async {
        final h = await pumpGuide(tester, lang: lang, now: base.subtract(const Duration(days: 3, minutes: 5)), setup: (a) {
          a.eventData['x'] = eventJson('x', starts: Duration.zero);
          a.tickets = [ticketJson('tk-x', 'x', starts: Duration.zero)];
        }, route: '/event/x/guide');
        final s = textOf(tester, 'guideStatus');
        await h.finish();
        return s;
      }

      expect(await status('en'), 'Starts in 3 days');
      final my = await status('my');
      expect(my, contains('၃'));
      expect(my, isNot(contains('3')));
    });
  });

  group('announcement cards', () {
    testWidgets('are as wide as the other cards', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [announcement('a1', 'Short news', const Duration(hours: 1), body: 'Hi')];
      }, route: '/event/concert/guide');
      final list = tester.getSize(find.byKey(const Key('guideList'))).width;
      final card = find.descendant(of: find.byKey(const Key('guideAnnouncements')), matching: find.byType(Material)).evaluate().map((e) => tester.getSize(find.byElementPredicate((x) => x == e)).width).reduce((a, b) => a > b ? a : b);
      expect(card, list - 40, reason: 'full width inside the 20 dp gutters');
      await h.finish();
    });
  });

  group('tickets tab', () {
    void two(GuideApi a) {
      a.eventData['gone'] = eventJson('gone', starts: const Duration(days: 5));
      a.eventData['next'] = eventJson('next', starts: const Duration(days: 6));
      a.tickets = [
        ticketJson('tk-gone', 'gone', starts: const Duration(days: 5), eventStatus: 'CANCELLED'),
        ticketJson('tk-next', 'next', starts: const Duration(days: 6)),
      ];
    }

    testWidgets('a cancelled event is labelled and listed under Past', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: two);
      await toTickets(h);
      expect(find.descendant(of: find.byKey(const Key('ticketGroup-gone')), matching: find.text('This event has been cancelled')), findsOneWidget);
      expect(find.byKey(const Key('groupCancelled-next')), findsNothing);
      final past = tester.getTopLeft(find.text('Past')).dy;
      expect(tester.getTopLeft(find.text('Upcoming')).dy, lessThan(tester.getTopLeft(find.byKey(const Key('ticketGroup-next'))).dy));
      expect(tester.getTopLeft(find.byKey(const Key('ticketGroup-next'))).dy, lessThan(past));
      expect(past, lessThan(tester.getTopLeft(find.byKey(const Key('ticketGroup-gone'))).dy));
      await h.finish();
    });

    testWidgets('the guide link sits in the header under the date, 48 dp, and opens the guide apart from the ticket', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: two);
      await toTickets(h);
      final link = find.byKey(const Key('groupGuideLink-next'));
      final header = find.byKey(const Key('ticketHeader-next'));
      expect(find.descendant(of: header, matching: link), findsOneWidget);
      expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
      final date = tester.getBottomLeft(find.descendant(of: header, matching: find.textContaining('Dec 2026').first)).dy;
      expect(tester.getTopLeft(link).dy, greaterThanOrEqualTo(date - 12));
      expect(tester.widget<InkWell>(header).onTap, isNotNull, reason: 'a single ticket: the header still opens it');
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(location(h), '/event/next/guide');
      await h.finish();
    });
  });

  group('home banner', () {
    testWidgets('+1 more with two events today, linking to Tickets', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['late'] = eventJson('late', starts: const Duration(hours: 2));
        a.eventData['early'] = eventJson('early', starts: Duration.zero);
        a.tickets = [ticketJson('tk-late', 'late', starts: const Duration(hours: 2)), ticketJson('tk-early', 'early', starts: Duration.zero)];
      });
      expect(find.text('+1 more'), findsOneWidget);
      await tester.tap(find.byKey(const Key('homeTodayMore')));
      await tester.pumpAndSettle();
      expect(location(h), '/tickets');
      await h.finish();
    });

    testWidgets('no "more" with one event today', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.eventData['e1'] = eventJson('e1', starts: Duration.zero);
        a.tickets = [ticketJson('tk1', 'e1', starts: Duration.zero)];
      });
      expect(find.byKey(const Key('homeTodayMore')), findsNothing);
      await h.finish();
    });
  });

  group('search results', () {
    testWidgets('a snippet that repeats the title is not shown', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'welcome');
      expect(find.descendant(of: hit('schedule', 1), matching: find.text('Welcome')), findsOneWidget, reason: 'the title only');
      await typeQuery(tester, 'doors');
      expect(find.descendant(of: hit('schedule', 1), matching: find.text('Welcome')), findsOneWidget);
      expect(find.descendant(of: hit('schedule', 1), matching: find.text('Doors and coffee')), findsOneWidget, reason: 'a different snippet stays');
      await h.finish();
    });
  });
}
