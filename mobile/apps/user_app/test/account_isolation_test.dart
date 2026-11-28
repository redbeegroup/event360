import 'dart:async';
import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:user_app/app/guide_providers.dart';
import 'package:user_app/app/providers.dart';
import 'package:user_app/screens/event_guide_screen.dart';

import 'event_guide_test.dart' hide main;

/// The ticket cache as this build writes it.
String tagged(String owner, List<Map<String, dynamic>> tickets) =>
    jsonEncode({'owner': owner, 'tickets': tickets.map((j) => MyTicket.fromApi(j).toJson()).toList()});

final offlineError = ApiException(null, 'Network error');

Future<void> openTickets(Harness h) async {
  h.router.go('/tickets');
  await h.tester.pumpAndSettle();
}

/// Opens the one ticket of `/tickets` and checks that its QR code is there.
Future<void> expectQr(Harness h, String eventId) async {
  await h.tester.tap(find.byKey(Key('ticketHeader-$eventId')));
  await h.tester.pumpAndSettle();
  expect(find.text('Show this QR code at the entrance'), findsOneWidget);
}

String? ticketCache(Harness h) => h.prefs.getString(MyTicketsNotifier.cacheKey);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  final concertTicket = ticketJson('tk-concert-1', 'concert');

  group('account isolation', () {
    /// A header.payload.signature token whose `sub` is [userId] (what the server issues).
    String jwtFor(String userId) => 'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': userId}))).replaceAll('=', '')}.sig';

    /// A is signed in with tickets and saved events on the phone, then the session ends without Sign out (the refresh failed ambiguously).
    Future<Harness> endedSessionOfA(WidgetTester tester, {void Function(GuideApi)? setup}) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [announcement('a1', 'Gates open at 4', const Duration(hours: 1))];
        setup?.call(a);
      }, route: '/event/concert/guide');
      await tester.pumpAndSettle();
      expect(ticketCache(h), isNotNull);
      expect(h.container.read(eventCacheProvider).read('concert'), isNotNull);
      h.router.go('/');
      await tester.pumpAndSettle();
      await h.api.tokensStore.clear();
      h.container.invalidate(sessionProvider);
      await tester.pumpAndSettle();
      expect(h.container.read(sessionProvider).value, isNull);
      return h;
    }

    testWidgets('1: a session that ended on its own keeps A\'s copies hidden; A signing in again on bad data gets them back', (tester) async {
      final h = await endedSessionOfA(tester);
      // Hidden, not deleted.
      expect(ticketCache(h), isNotNull);
      expect(h.prefs.getString(SessionNotifier.userIdKey), 'u1');
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isNotEmpty);
      await openTickets(h);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      expect(find.text('Event concert'), findsNothing);

      // A signs in again; /auth/me and the ticket list both time out.
      h.api
        ..meError = offlineError
        ..offline = true;
      await h.api.tokensStore.save(jwtFor('u1'), 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      await openTickets(h);
      expect(find.text('Available offline'), findsOneWidget);
      await expectQr(h, 'concert');
      await h.finish();
    });

    testWidgets("2: B signing in after A's session ended on its own: A's copies are deleted first, B never sees them", (tester) async {
      final h = await endedSessionOfA(tester);
      h.api
        ..meError = offlineError // not even /auth/me answers: the token says who this is
        ..offline = true
        ..meId = 'u2';
      await h.api.tokensStore.save(jwtFor('u2'), 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(h.prefs.getString(SessionNotifier.userIdKey), 'u2');
      expect(ticketCache(h), isNull);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isEmpty);
      await openTickets(h);
      expect(find.text('Event concert'), findsNothing);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      expect(find.byKey(const Key('todayCard-concert')), findsNothing);
      expect(find.byKey(const Key('homeTodayBanner')), findsNothing);
      h.router.go('/event/concert/guide');
      await tester.pumpAndSettle();
      expect(find.byType(EventGuideScreen), findsNothing);
      expect(find.text('Gates open at 4'), findsNothing);
      await h.finish();
    });

    testWidgets('2b: B signing in online (/auth/me answers) deletes A\'s copies too', (tester) async {
      final h = await endedSessionOfA(tester);
      h.api
        ..offline = true
        ..meId = 'u2';
      await h.api.tokensStore.save('opaque', 'r'); // a token the app cannot read: /auth/me tells
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(ticketCache(h), isNull);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isEmpty);
      await openTickets(h);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      await h.finish();
    });

    testWidgets('5: after an explicit Sign out a second person sees nothing of the first', (tester) async {
      final h = await endedSessionOfA(tester);
      await h.api.tokensStore.save(jwtFor('u1'), 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      await h.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(ticketCache(h), isNull);
      expect(h.prefs.getString(SessionNotifier.userIdKey), isNull);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isEmpty);
      h.api
        ..meError = offlineError
        ..offline = true;
      await h.api.tokensStore.save(jwtFor('u2'), 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      await openTickets(h);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      await h.finish();
    });

    testWidgets('6: with no answer from /auth/me the token says whose cache it is', (tester) async {
      for (final (sub, shown) in [('u1', true), ('u9', false)]) {
        final h = await pumpGuide(
          tester,
          now: base,
          prefs: {MyTicketsNotifier.cacheKey: tagged('u1', [concertTicket])}, // no stored id
          setup: (a) {
            a.meError = offlineError;
            a.offline = true;
          },
        );
        await h.api.tokensStore.save(jwtFor(sub), 'r');
        await h.container.read(sessionProvider.notifier).signedIn();
        await tester.pumpAndSettle();
        await openTickets(h);
        expect(find.byKey(const Key('ticketGroup-concert')), shown ? findsOneWidget : findsNothing, reason: 'token of $sub');
        expect(ticketCache(h) != null, shown, reason: 'a different person: the copy is deleted');
        await h.finish();
      }
    });

    testWidgets('4: a cache tagged with an empty owner is accepted once as legacy and rewritten tagged', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: {MyTicketsNotifier.cacheKey: tagged('', [concertTicket]), SessionNotifier.userIdKey: 'u1'},
        setup: (a) {
          a.offline = true;
          a.tickets = [concertTicket];
        },
      );
      await openTickets(h);
      expect(find.text('Available offline'), findsOneWidget);
      await expectQr(h, 'concert');
      h.api.offline = false;
      await h.container.read(myTicketsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect((jsonDecode(ticketCache(h)!) as Map)['owner'], 'u1');
      await h.finish();
    });

    testWidgets('an unknown owner is never written as an empty tag', (tester) async {
      final h = await pumpGuide(tester, now: base, prefs: seedPrefs(tickets: [concertTicket]), setup: (a) {
        a.meError = offlineError;
        a.tickets = [concertTicket];
      });
      expect(h.container.read(sessionProvider).value?.id, '');
      await h.container.read(myTicketsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(jsonDecode(ticketCache(h)!), isA<List>());
      await h.finish();
    });

    testWidgets('no token at start: the copies stay on disk, hidden', (tester) async {
      final h = await pumpGuide(
        tester,
        signedIn: false,
        prefs: {
          ...seedPrefs(tickets: [concertTicket], saved: {'concert': (eventJson('concert', starts: const Duration(days: 3)), const [], base)}),
          SessionNotifier.userIdKey: 'u1',
        },
      );
      expect(ticketCache(h), isNotNull);
      expect(h.prefs.getString(SessionNotifier.userIdKey), 'u1');
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isNotEmpty);
      await openTickets(h);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      await h.finish();
    });

    testWidgets('someone else signs in on the same phone without a sign-out: the first account\'s copies go', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [];
      }, route: '/event/concert/guide');
      await tester.pumpAndSettle();
      expect(h.container.read(eventCacheProvider).read('concert'), isNotNull);
      h.router.go('/');
      await tester.pumpAndSettle();
      h.api
        ..tickets = []
        ..meId = 'u2';
      await h.api.tokensStore.save('b', 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(h.prefs.getString(SessionNotifier.userIdKey), 'u2');
      expect(h.container.read(eventCacheProvider).read('concert'), isNull);
      await h.finish();
    });

    testWidgets('a tagged cache that belongs to another owner is rejected, offline (c)', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: {MyTicketsNotifier.cacheKey: tagged('someone-else', [concertTicket]), SessionNotifier.userIdKey: 'u1'},
        setup: (a) {
          a.offline = true; // me() works (u1) but the ticket fetch has no signal
          a.tickets = [];
        },
      );
      await openTickets(h);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      expect(find.text('Available offline'), findsNothing);
      expect(h.container.read(myTicketsProvider).hasError, isTrue);
      await h.finish();
    });

    testWidgets('offline cold start for the same user: the tagged cache shows the tickets and the QR (e)', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: {MyTicketsNotifier.cacheKey: tagged('u1', [concertTicket]), SessionNotifier.userIdKey: 'u1'},
        setup: (a) {
          a.meError = offlineError; // no signal at all: the session itself falls back to the stored user
          a.offline = true;
        },
      );
      expect(h.container.read(sessionProvider).value?.id, 'u1');
      await openTickets(h);
      expect(find.text('Available offline'), findsOneWidget);
      expect(find.byKey(const Key('ticketGroup-concert')), findsOneWidget);
      await expectQr(h, 'concert');
      expect(ticketCache(h), tagged('u1', [concertTicket]), reason: 'reading does not rewrite the cache');
      await h.finish();
    });

    testWidgets('a legacy untagged list loads offline with the QR; one online fetch tags it (b)', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: seedPrefs(tickets: [concertTicket]), // what older builds wrote, and no stored user id
        setup: (a) {
          a.meError = offlineError;
          a.offline = true;
          a.tickets = [concertTicket];
        },
      );
      expect(h.container.read(sessionProvider).value?.id, '');
      await openTickets(h);
      expect(find.text('Available offline'), findsOneWidget);
      await expectQr(h, 'concert');
      expect(jsonDecode(ticketCache(h)!), isA<List>(), reason: 'still the legacy shape while offline');

      // The signal comes back and the app is started again online: the id is learned, the next fetch tags the cache.
      h.api
        ..meError = null
        ..offline = false;
      h.container.invalidate(sessionProvider);
      await tester.pumpAndSettle();
      final written = jsonDecode(ticketCache(h)!) as Map<String, dynamic>;
      expect(written['owner'], 'u1');
      expect((written['tickets'] as List).single['id'], 'tk-concert-1');
      await h.finish();
    });

    testWidgets('a legacy untagged list is also accepted for a user whose id is known', (tester) async {
      final h = await pumpGuide(
        tester,
        now: base,
        prefs: {...seedPrefs(tickets: [concertTicket]), SessionNotifier.userIdKey: 'u1'},
        setup: (a) {
          a.offline = true;
        },
      );
      await openTickets(h);
      expect(find.byKey(const Key('ticketGroup-concert')), findsOneWidget);
      h.api
        ..tickets = [concertTicket]
        ..offline = false;
      await h.container.read(myTicketsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect((jsonDecode(ticketCache(h)!) as Map)['owner'], 'u1', reason: 'rewritten tagged after the next online fetch');
      await h.finish();
    });

    testWidgets('an online load stores the user id and writes the tagged cache', (tester) async {
      final h = await pumpGuide(tester, now: base, setup: (a) => setUpConcert(a));
      expect(h.prefs.getString(SessionNotifier.userIdKey), 'u1');
      final written = jsonDecode(ticketCache(h)!) as Map<String, dynamic>;
      expect(written['owner'], 'u1');
      expect(written['tickets'], hasLength(1));
      await h.finish();
    });

    testWidgets('a ticket fetch that completes while sign-out is running leaves nothing on disk (d)', (tester) async {
      final gate = Completer<void>();
      final h = await pumpGuide(tester, now: base, prefs: {pushTokenKey: 'push-1'}, setup: (a) {
        setUpConcert(a);
        a.ticketGate = gate;
        // The answer arrives the moment the server logout is done: the session is still there for an instant.
        a.afterLogout = gate.complete;
      });
      await h.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(ticketCache(h), isNull);
      expect(h.prefs.getString(SessionNotifier.userIdKey), isNull);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isEmpty);
      expect(h.prefs.getString(pushTokenKey), isNull);
      await h.finish();
    });

    testWidgets('a stale failed ticket fetch after an account switch does not relabel the new list', (tester) async {
      final gateA = Completer<void>();
      final h = await pumpGuide(tester, now: base, setup: (a) {
        a.tickets = [concertTicket];
        a.offline = true;
        a.ticketGates.add(gateA); // A's fetch (the first) waits
      });
      final notifier = h.container.read(myTicketsProvider.notifier);
      expect(notifier.owner, isNull);
      h.api
        ..meId = 'u2'
        ..tickets = [];
      await h.api.tokensStore.save('b', 'r');
      await h.container.read(sessionProvider.notifier).signedIn();
      await tester.pumpAndSettle();
      expect(h.container.read(myTicketsProvider).value, isEmpty); // B: offline, no copy
      expect(notifier.owner, 'u2');
      gateA.complete(); // now A's fetch fails with a network error
      await tester.pumpAndSettle();
      expect(notifier.owner, 'u2');
      await h.finish();
    });
  });

  group('sign out', () {
    Future<Harness> pumpProfile(WidgetTester tester, {void Function(GuideApi)? setup}) async {
      final h = await pumpGuide(tester, now: base, prefs: {pushTokenKey: 'push-1'}, setup: (a) {
        setUpConcert(a);
        setup?.call(a);
      });
      h.router.go('/profile');
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('the button is busy while it runs and a second tap does nothing (f)', (tester) async {
      final gate = Completer<void>();
      final h = await pumpProfile(tester, setup: (a) => a.removeDeviceGate = gate);
      final button = find.widgetWithText(OutlinedButton, 'Sign out');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(find.byKey(const Key('signOutBusy')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      // The same sign-out asked for again (from elsewhere) joins the running one.
      final again = h.container.read(sessionProvider.notifier).signOut();
      await tester.pump();
      expect(h.api.removeDeviceCalls, 1);
      gate.complete();
      await again;
      await tester.pumpAndSettle();
      expect(h.api.removeDeviceCalls, 1);
      expect(h.api.logoutCalls, 1);
      expect(h.container.read(sessionProvider).value, isNull);
      expect(find.byKey(const Key('signOutBusy')), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
      await h.finish();
    });

    testWidgets('a dead network does not hold the sign-out beyond 5 seconds', (tester) async {
      final h = await pumpProfile(tester, setup: (a) => a.removeDeviceGate = Completer<void>()); // never answers
      final done = h.container.read(sessionProvider.notifier).signOut();
      var finished = false;
      unawaited(done.then((_) => finished = true));
      await tester.pump(const Duration(seconds: 4));
      expect(finished, isFalse);
      expect(h.container.read(sessionProvider).value, isNotNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(h.container.read(sessionProvider).value, isNull);
      expect(ticketCache(h), isNull);
      expect(h.prefs.getString(pushTokenKey), isNull);
      await h.finish();
    });
  });
}
