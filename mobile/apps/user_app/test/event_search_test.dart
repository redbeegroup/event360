import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_app/app/format.dart';
import 'package:user_app/screens/event_detail_screen.dart';
import 'package:user_app/screens/event_guide_screen.dart';

import 'event_guide_test.dart' hide main;

/// An event whose schedule is NOT in time order and whose first session has no id, so a wrong list index shows up.
Map<String, dynamic> searchableJson([String id = 'srch']) => eventJson(id, starts: const Duration(days: 3), extra: {
      'sessions': [
        {
          'id': 'q1',
          'title': 'Closing party',
          'titleMy': 'ပိတ်ပွဲ',
          'description': 'Dance until late',
          'descriptionMy': 'နောက်ကျသည်အထိ ကခုန်ပါ',
          'location': 'Rooftop',
          'startsAt': at(const Duration(days: 4)),
          'endsAt': at(const Duration(days: 4, hours: 3)),
        },
        {
          'id': null,
          'title': 'Welcome',
          'titleMy': null,
          'description': 'Doors and coffee',
          'location': 'Main hall',
          'startsAt': at(const Duration(days: 3)),
          'endsAt': at(const Duration(days: 3, hours: 1)),
        },
      ],
      'performers': [
        {'name': 'Nadi', 'nameMy': 'နဒီ', 'role': 'Headliner', 'roleMy': null, 'bio': 'Folk singer from Mandalay'},
        {'name': 'Kyaw', 'role': 'Host'},
      ],
      'faqs': [
        {'question': 'Can I bring kids?', 'answer': 'Yes, under 12 free', 'questionMy': 'ကလေးခေါ်လာနိုင်ပါသလား', 'answerMy': null},
      ],
      'dressCode': 'Smart casual',
      'parking': 'Free after 6 PM',
    });

void setUpSearchable(GuideApi a) {
  a.eventData['srch'] = searchableJson();
  a.tickets = [ticketJson('tk-srch', 'srch', starts: const Duration(days: 3))];
}

Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('eventSearchAction')));
  await tester.pumpAndSettle();
}

Future<void> typeQuery(WidgetTester tester, String q) async {
  await tester.enterText(find.byKey(const Key('eventSearchField')), q);
  await tester.pumpAndSettle();
}

Finder hit(String group, int index) => find.byKey(Key('searchHit-$group-$index'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  group('the action', () {
    testWidgets('is on the guide and on the event page', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('eventSearchAction'))), findsOneWidget);
      await h.go('/event/srch');
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('eventSearchAction')), findsOneWidget);
      await h.finish();
    });

    testWidgets('is absent when there is nothing to search', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        a.eventData['bare'] = eventJson('bare', starts: const Duration(days: 2), extra: {'venue': null});
        a.tickets = [ticketJson('tk-bare', 'bare', starts: const Duration(days: 2))];
      }, route: '/event/bare/guide');
      expect(find.byType(EventGuideScreen), findsOneWidget);
      expect(find.byKey(const Key('eventSearchAction')), findsNothing);
      await h.go('/event/bare');
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('eventSearchAction')), findsNothing);
      await h.finish();
    });

    testWidgets('sits in the pinned bar once the cover has scrolled away, and the page keeps one gold button', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch');
      final gold = goldButtons(tester).length;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pinnedBar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('eventSearchActionPinned')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('eventSearchField')), findsOneWidget);
      expect(goldButtons(tester).length, gold);
      expect(gold, lessThanOrEqualTo(1));
      await h.finish();
    });
  });

  group('searching', () {
    testWidgets('finds each kind of item, grouped under section titles', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      expect(find.byKey(const Key('eventSearchResults')), findsNothing);

      await typeQuery(tester, 'rooftop'); // a session by its location
      expect(hit('schedule', 0), findsOneWidget);
      expect(find.byKey(const Key('searchGroup-schedule')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('searchGroup-schedule')), matching: find.text('Schedule')), findsOneWidget);

      await typeQuery(tester, 'headliner'); // a performer by role
      expect(hit('lineup', 0), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('searchGroup-lineup')), matching: find.text('Lineup')), findsOneWidget);

      await typeQuery(tester, 'under 12'); // an FAQ by a word of its answer
      expect(hit('faq', 0), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('searchGroup-faq')), matching: find.text('FAQ')), findsOneWidget);

      await typeQuery(tester, 'casual'); // a practical-info field, with its localized label
      expect(hit('info', 0), findsOneWidget);
      expect(find.descendant(of: hit('info', 0), matching: find.text('Dress code')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('searchGroup-info')), matching: find.text('Good to know')), findsOneWidget);

      await typeQuery(tester, 'free'); // two groups at once: FAQ and parking
      expect(hit('faq', 0), findsOneWidget);
      expect(hit('info', 2), findsOneWidget);
      await h.finish();
    });

    testWidgets('a Myanmar query finds a Myanmar title while the app is in English', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'ပိတ်ပွဲ');
      expect(hit('schedule', 0), findsOneWidget);
      expect(find.descendant(of: hit('schedule', 0), matching: find.text('Closing party')), findsOneWidget);
      await h.finish();
    });

    testWidgets('no results shows a message with the query', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'zzz');
      expect(find.byKey(const Key('eventSearchNoResults')), findsOneWidget);
      expect(find.text('Nothing found for “zzz”'), findsOneWidget);
      await h.finish();
    });

    testWidgets('results stay visible above the keyboard', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await typeQuery(tester, 'o');
      expect(hit('schedule', 0), findsOneWidget);
      final screenBottom = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getBottomLeft(find.byKey(const Key('eventSearchField'))).dy, lessThan(screenBottom - 300));
      expect(tester.getBottomLeft(find.byKey(const Key('eventSearchResults'))).dy, lessThanOrEqualTo(screenBottom - 300));
      expect(tester.getTopLeft(hit('schedule', 0)).dy, lessThan(screenBottom - 300));
      // No gold button in the sheet (the only button is the field's clear icon).
      final sheetButtons = find.descendant(of: find.byType(BottomSheet), matching: find.bySubtype<ButtonStyleButton>()).evaluate().toSet();
      expect(goldButtons(tester).where(sheetButtons.contains), isEmpty);
      await h.finish();
    });
  });

  group('opening a hit', () {
    testWidgets('a session opens its details, found by id even though the list is not in time order', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'dance');
      await tester.tap(hit('schedule', 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('eventSearchField')), findsNothing);
      final sheet = find.byKey(const Key('searchSessionSheet'));
      expect(find.descendant(of: sheet, matching: find.text('Closing party')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Rooftop')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Dance until late')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining(formatDay(DateTime.parse(at(const Duration(days: 4))), 'en'))), findsOneWidget);
      await h.finish();
    });

    testWidgets('a session without an id opens by its index', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'coffee');
      await tester.tap(hit('schedule', 1));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('searchSessionSheet'));
      expect(find.descendant(of: sheet, matching: find.text('Welcome')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Main hall')), findsOneWidget);
      await h.finish();
    });

    testWidgets('a performer opens the performer sheet', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'mandalay');
      await tester.tap(hit('lineup', 0));
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('Nadi'), findsOneWidget);
      expect(find.text('Headliner'), findsOneWidget);
      expect(find.text('Folk singer from Mandalay'), findsOneWidget);
      await h.finish();
    });

    testWidgets('an FAQ opens the question and the full answer', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'under 12');
      await tester.tap(hit('faq', 0));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('searchFaqSheet'));
      expect(find.descendant(of: sheet, matching: find.text('Can I bring kids?')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Yes, under 12 free')), findsOneWidget);
      await h.finish();
    });

    testWidgets('an info field opens its label and text', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, '6 pm');
      await tester.tap(hit('info', 2));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('searchInfoSheet'));
      expect(find.descendant(of: sheet, matching: find.text('Parking')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Free after 6 PM')), findsOneWidget);
      await h.finish();
    });

    testWidgets('works on the event page too', (tester) async {
      final h = await pumpGuide(tester, setup: setUpSearchable, route: '/event/srch');
      await openSearch(tester);
      await typeQuery(tester, 'nadi');
      await tester.tap(hit('lineup', 0));
      await tester.pumpAndSettle();
      expect(find.text('Folk singer from Mandalay'), findsOneWidget);
      await h.finish();
    });

    testWidgets('in Myanmar the sheets and labels are in Myanmar', (tester) async {
      final h = await pumpGuide(tester, lang: 'my', setup: setUpSearchable, route: '/event/srch/guide');
      await openSearch(tester);
      await typeQuery(tester, 'rooftop');
      expect(find.descendant(of: hit('schedule', 0), matching: find.text('ပိတ်ပွဲ')), findsOneWidget);
      await tester.tap(hit('schedule', 0));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('searchSessionSheet')), matching: find.text('နောက်ကျသည်အထိ ကခုန်ပါ')), findsOneWidget);
      await h.finish();
    });
  });

  testWidgets('works from the saved copy with the network failing', (tester) async {
    final h = await pumpGuide(
      tester,
      now: base,
      prefs: seedPrefs(
        tickets: [ticketJson('tk-srch', 'srch', starts: const Duration(days: 3))],
        saved: {'srch': (searchableJson(), const [], base)},
      ),
      setup: (a) => a.offline = true,
      route: '/event/srch/guide',
    );
    final calls = h.api.rawCalls;
    await openSearch(tester);
    await typeQuery(tester, 'under 12');
    await tester.tap(hit('faq', 0));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('searchFaqSheet')), matching: find.text('Yes, under 12 free')), findsOneWidget);
    expect(h.api.rawCalls, calls, reason: 'searching makes no request');
    await h.finish();
  });

  // ───── Large-text sweep: 390x844, text scale 2.0, EN and MY ─────
  for (final lang in ['en', 'my']) {
    for (final (name, query) in [('results', 'o'), ('no results', 'zzzzzz')]) {
      testWidgets('large text: search $name has no overflow at 390x844, scale 2.0, $lang', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final errors = <String>[];
        final h = await pumpGuide(tester, lang: lang, setup: setUpSearchable);
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toDiagnosticsNode().toStringDeep().split('\n').where((l) => l.contains('overflowed') || l.contains('/lib/')).take(6).join(' / '));
        try {
          await h.go('/event/srch/guide');
          await openSearch(tester);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
          addTearDown(tester.view.resetViewInsets);
          await typeQuery(tester, query);
          expect(errors, isEmpty, reason: 'results');
          if (query == 'o') {
            await tester.tap(hit('schedule', 0));
            await tester.pumpAndSettle();
            expect(errors, isEmpty, reason: 'session sheet');
          }
        } finally {
          FlutterError.onError = previous;
        }
        await h.finish();
      });
    }
  }
}
