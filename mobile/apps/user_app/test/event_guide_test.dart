import 'dart:async';
import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_app/app/format.dart';
import 'package:user_app/app/guide_providers.dart';
import 'package:user_app/app/providers.dart';
import 'package:user_app/main.dart';
import 'package:user_app/screens/event_detail_screen.dart';
import 'package:user_app/screens/event_guide_screen.dart';
import 'package:user_app/screens/login_screen.dart';
import 'package:user_app/screens/ticket_screen.dart';

/// The pinned clock: 10 Dec 2026, 08:00 UTC (14:30 in Yangon).
final base = DateTime.utc(2026, 12, 10, 8);
String at(Duration d) => base.add(d).toIso8601String();

/// Fake API for the guide: canned events, announcements, streams and tickets; switchable failures; call counters.
class GuideApi extends Event360Api {
  GuideApi(this.tokensStore) : super(const AppConfig(app: Event360App.user, apiBaseUrl: 'http://fake'), tokensStore);
  final MemoryTokenStore tokensStore;

  /// Everything that needs the network fails with a network error.
  bool offline = false;

  /// Announcements fail with this status (403, 404, 500) when set.
  int? announcementsError;

  /// The event itself fails with this status (e.g. 503) when set.
  int? eventStatusError;
  final eventData = <String, Map<String, dynamic>>{};
  final announcementData = <String, List<Map<String, dynamic>>>{};
  final streamData = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> tickets = [];
  String meId = 'u1';
  Duration meDelay = Duration.zero;
  Completer<void>? ticketGate;

  /// One gate per ticket fetch, in call order (a fetch beyond the list is not held).
  final ticketGates = <Completer<void>>[];

  /// `me()` fails with this (a 401, or a network error for the offline start).
  ApiException? meError;
  Completer<void>? removeDeviceGate;
  int removeDeviceCalls = 0;
  int logoutCalls = 0;

  /// Runs right after the tokens are cleared by `logout()`.
  void Function()? afterLogout;
  Completer<void>? eventGate;
  int rawCalls = 0;
  int announcementCalls = 0;

  ApiException get _net => ApiException(null, 'Network error');

  @override
  Future<Map<String, dynamic>> eventRaw(String idOrSlug) async {
    rawCalls++;
    if (eventGate != null) await eventGate!.future;
    if (offline) throw _net;
    if (eventStatusError != null) throw ApiException(eventStatusError, 'server error');
    final e = eventData[idOrSlug] ?? eventData.values.where((j) => j['slug'] == idOrSlug).firstOrNull;
    if (e == null) throw ApiException(404, 'Not found');
    return e;
  }

  @override
  Future<List<EventAnnouncement>> eventAnnouncements(String eventId) async {
    announcementCalls++;
    if (offline) throw _net;
    if (announcementsError != null) throw ApiException(announcementsError, 'nope');
    if (!eventData.containsKey(eventId)) throw ApiException(404, 'Not found'); // the server knows ids, not slugs
    return (announcementData[eventId] ?? const []).map(EventAnnouncement.fromJson).toList();
  }

  @override
  Future<EventSummary> event(String idOrSlug) async => EventSummary.fromJson(await eventRaw(idOrSlug));

  @override
  Future<EventStreams> eventStreams(String idOrSlug) async {
    if (offline) throw _net;
    return EventStreams.fromJson(streamData[idOrSlug] ?? {'live': [], 'recordings': []});
  }

  @override
  Future<List<MyTicket>> myTickets() async {
    final queued = ticketGates.isEmpty ? null : ticketGates.removeAt(0);
    if (queued != null) await queued.future;
    if (ticketGate != null) await ticketGate!.future;
    if (offline) throw _net;
    return tickets.map(MyTicket.fromApi).toList();
  }

  @override
  Future<Me> me() async {
    if (meDelay > Duration.zero) await Future<void>.delayed(meDelay);
    if (meError != null) throw meError!;
    return Me(id: meId, phone: '+959790000001');
  }

  @override
  Future<void> removeDevice(String pushToken) async {
    removeDeviceCalls++;
    if (removeDeviceGate != null) await removeDeviceGate!.future;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    await super.logout();
    afterLogout?.call();
  }

  @override
  Future<String?> requestOtp(String phone) async => '123456';

  @override
  Future<void> verifyOtp(String phone, String code) async => tokensStore.save('a', 'r');

  // The pages behind the guide (Discover, the event page) need these to be quiet.
  @override
  Future<List<Category>> categories() async => [];
  @override
  Future<EventPage> events({String? q, String? category, String? city, bool? free, DateTime? from, DateTime? to, int page = 1, int limit = 20}) async =>
      EventPage(items: [], page: 1, total: 0, limit: 20);
  @override
  Future<List<PaymentMethod>> paymentMethods() async => [];
  @override
  Future<List<WaitlistEntry>> myWaitlist() async => [];
  @override
  Future<List<Order>> pendingOrders() async => [];
  @override
  Future<Inbox> notifications({DateTime? before, int limit = 30}) async => Inbox.fromJson({'items': [], 'unread': 0});
}

// ───── Fixtures ─────

Map<String, dynamic> eventJson(String id, {required Duration starts, Duration length = const Duration(hours: 3), Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'slug': 'slug-$id',
      'status': 'PUBLISHED',
      'title': 'Event $id',
      'titleMy': 'ပွဲ $id',
      'format': 'IN_PERSON',
      'isFree': true,
      'minPriceMmk': 0,
      'startsAt': at(starts),
      'endsAt': at(starts + length),
      'category': {'nameEn': 'Music', 'nameMy': null},
      'venue': {
        'name': 'Thuwunna Stadium',
        'city': 'Yangon',
        'address': 'Thuwunna Rd',
        'directions': 'Gate 3 is for ticket holders',
        'latitude': 16.8,
        'longitude': 96.15,
        'mapUrl': 'https://maps.example/venue',
      },
      'organization': {'name': 'Yangon Live', 'slug': 'yangon-live', 'kycStatus': 'APPROVED'},
      'ticketTypes': [
        {'id': 'tt-$id', 'name': 'General', 'nameMy': 'အထွေထွေ', 'priceMmk': 0, 'quota': 100, 'remaining': 50, 'maxPerOrder': 4},
      ],
      'soldOut': false,
      ...extra,
    };

Map<String, dynamic> ticketJson(String id, String eventId, {Duration starts = const Duration(days: 3), Duration length = const Duration(hours: 3), String status = 'VALID', String type = 'General', String eventStatus = 'PUBLISHED', Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'status': status,
      'ticketType': {'name': type, 'nameMy': null},
      'event': {
        'id': eventId,
        'slug': 'slug-$eventId',
        'status': eventStatus,
        'title': 'Event $eventId',
        'titleMy': null,
        'startsAt': at(starts),
        'endsAt': at(starts + length),
        'venue': {'name': 'Thuwunna Stadium', 'city': 'Yangon'},
        'coverImageUrl': null,
        'organization': 'Yangon Live',
      },
      'qr': status == 'VALID' ? 'eyJ0aWQiOiJ0In0.c2ln' : null,
      ...extra,
    };

Map<String, dynamic> session(String id, String title, Duration from, Duration to, {String? location}) =>
    {'id': id, 'title': title, 'titleMy': null, 'location': location, 'startsAt': at(from), 'endsAt': at(to)};

Map<String, dynamic> announcement(String id, String title, Duration ago, {String body = 'Gates open at four', String? bodyMy}) =>
    {'id': id, 'title': title, 'titleMy': null, 'body': body, 'bodyMy': bodyMy, 'createdAt': at(-ago)};

/// 3 days, 6 sessions (Thu 14:30 Yangon, Fri, Sat), practical info and FAQ.
Map<String, dynamic> festivalJson() => eventJson('fest', starts: Duration.zero, length: const Duration(hours: 52), extra: {
      'sessions': [
        session('s1', 'Opening', Duration.zero, const Duration(hours: 2), location: 'Main stage'),
        session('s2', 'Cooking show', const Duration(hours: 3), const Duration(hours: 5)),
        session('s3', 'Night market', const Duration(hours: 24), const Duration(hours: 28), location: 'Lake side'),
        session('s4', 'Chef talk', const Duration(hours: 30), const Duration(hours: 32), location: 'Tent B'),
        session('s5', 'Tasting', const Duration(hours: 33), const Duration(hours: 35)),
        session('s6', 'Finale', const Duration(hours: 48), const Duration(hours: 52)),
      ],
      'dressCode': 'Smart casual',
      'parking': 'Free after 6 PM',
      'faqs': [
        {'question': 'Can I bring kids?', 'answer': 'Yes, under 12 free'},
      ],
    });

/// A pinned time inside the festival: Chef talk is on, Tasting and Finale are next.
final festivalNow = base.add(const Duration(hours: 30, minutes: 30));

Map<String, dynamic> liveStream(String sessionId, {String title = 'Chef talk', bool live = true}) => {
      'live': [
        {'channelId': 'c0000000-0000-0000-0000-000000000001', 'sessionId': sessionId, 'title': title, 'titleMy': null, 'startsAt': at(const Duration(hours: 30)), 'endsAt': at(const Duration(hours: 32)), 'isLive': live},
      ],
      'recordings': [],
    };

// ───── Harness ─────

class Harness {
  Harness(this.tester, this.api, this.prefs, this.now, this.opened);
  final WidgetTester tester;
  final GuideApi api;
  final SharedPreferences prefs;
  DateTime Function() now;
  final List<Uri> opened;

  ProviderContainer get container => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  GoRouter get router => GoRouter.of(tester.element(find.byType(Scaffold).first));

  Future<void> go(String route) async {
    router.push(route);
    await tester.pumpAndSettle();
  }

  /// Tears the tree down so the guide's timers are cancelled.
  Future<void> finish() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }
}

/// Seeds the same prefs the app would hold after a successful online visit: the ticket list and saved events.
Map<String, Object> seedPrefs({List<Map<String, dynamic>> tickets = const [], Map<String, (Map<String, dynamic>, List<Map<String, dynamic>>, DateTime)> saved = const {}}) {
  final out = <String, Object>{};
  if (tickets.isNotEmpty) out[MyTicketsNotifier.cacheKey] = jsonEncode(tickets.map((j) => MyTicket.fromApi(j).toJson()).toList());
  for (final e in saved.entries) {
    out['${EventCache.prefix}${e.key}'] = jsonEncode({'savedAt': e.value.$3.toUtc().toIso8601String(), 'event': e.value.$1, 'announcements': e.value.$2});
  }
  return out;
}

Future<Harness> pumpGuide(
  WidgetTester tester, {
  bool signedIn = true,
  String lang = 'en',
  DateTime? now,
  Map<String, Object> prefs = const {},
  void Function(GuideApi)? setup,
  String? route,
  List<Override> Function(SharedPreferences prefs, DateTime Function() now)? extraOverrides,
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'lang': lang, ...prefs});
  final sp = await SharedPreferences.getInstance();
  final store = MemoryTokenStore();
  if (signedIn) await store.save('a', 'r');
  final api = GuideApi(store);
  setup?.call(api);
  final opened = <Uri>[];
  final h = Harness(tester, api, sp, () => now ?? base, opened);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(sp),
      apiProvider.overrideWithValue(api),
      nowProvider.overrideWithValue(() => h.now()),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
      ...?extraOverrides?.call(sp, () => h.now()),
    ],
    child: const UserApp(),
  ));
  await tester.pumpAndSettle();
  if (route != null) await h.go(route);
  return h;
}

/// Buttons whose resolved background is the gold token.
List<Element> goldButtons(WidgetTester tester) => find.bySubtype<ButtonStyleButton>().evaluate().where((el) {
      final b = el.widget as ButtonStyleButton;
      // Test-only: the same theme and default styles the button resolves itself.
      // ignore: invalid_use_of_protected_member
      final style = (b.style ?? const ButtonStyle()).merge(b.themeStyleOf(el)).merge(b.defaultStyleOf(el));
      return style.backgroundColor?.resolve({}) == E360Colors.gold;
    }).toList();

/// Scrolls the guide until [f] is on screen.
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: find.descendant(of: find.byKey(const Key('guideList')), matching: find.byType(Scrollable)).first);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void setUpConcert(GuideApi a, {String id = 'concert', Map<String, dynamic> extra = const {}}) {
  a.eventData[id] = eventJson(id, starts: const Duration(days: 3), extra: {
    'sessions': [session('c1', 'Main show', const Duration(days: 3), const Duration(days: 3, hours: 3))],
    ...extra,
  });
  a.tickets = [ticketJson('tk-$id-1', id)];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  group('status line', () {
    Future<void> expectStatus(WidgetTester tester, Duration from, Duration length, String text, {String? status}) async {
      final h = await pumpGuide(tester, now: base.add(from), setup: (a) {
        a.eventData['x'] = eventJson('x', starts: Duration.zero, length: length, extra: {if (status != null) 'status': status});
        a.tickets = [ticketJson('tk-x', 'x', starts: Duration.zero, length: length, eventStatus: status ?? 'PUBLISHED')];
      }, route: '/event/x/guide');
      expect(textOf(tester, 'guideStatus'), text);
      await h.finish();
    }

    testWidgets('days, hours and minutes before the start', (tester) async {
      // The event starts at base; "now" is before it.
      await expectStatus(tester, const Duration(days: -3, minutes: -5), const Duration(hours: 3), 'Starts in 3 days');
      await expectStatus(tester, const Duration(hours: -5, minutes: -30), const Duration(hours: 3), 'Starts in 5 hours');
      await expectStatus(tester, const Duration(minutes: -20), const Duration(hours: 3), 'Starts in 20 minutes');
      await expectStatus(tester, const Duration(days: -1, minutes: -1), const Duration(hours: 3), 'Starts in 1 day');
    });

    testWidgets('on now, ended and cancelled', (tester) async {
      await expectStatus(tester, const Duration(hours: 1), const Duration(hours: 3), 'On now');
      await expectStatus(tester, const Duration(hours: 4), const Duration(hours: 3), 'Ended');
      await expectStatus(tester, const Duration(minutes: -20), const Duration(hours: 3), 'This event was cancelled', status: 'CANCELLED');
    });
  });

  group('sections', () {
    testWidgets('empty sections are absent', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        a.eventData['bare'] = eventJson('bare', starts: const Duration(days: 2));
        a.tickets = [ticketJson('tk-bare', 'bare', starts: const Duration(days: 2))];
      }, route: '/event/bare/guide');
      expect(find.byKey(const Key('guideStatus')), findsOneWidget);
      expect(find.byKey(const Key('guideTickets')), findsOneWidget);
      expect(find.byKey(const Key('guideVenue')), findsOneWidget);
      expect(find.byKey(const Key('guideNow')), findsNothing, reason: 'no sessions');
      expect(find.byKey(const Key('guideNext')), findsNothing);
      expect(find.byKey(const Key('guideNowNext')), findsNothing);
      expect(find.byKey(const Key('guideAnnouncements')), findsNothing, reason: 'no announcements');
      expect(find.byKey(const Key('guideInfo')), findsNothing, reason: 'no practical info and no FAQ');
      expect(find.byKey(const Key('guideThanks')), findsNothing);
      await h.finish();
    });

    testWidgets('a single-session concert has no now and next, and shows what it has', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a, extra: {'dressCode': 'Smart casual'});
        a.announcementData['concert'] = [announcement('a1', 'Gates open at 4', const Duration(hours: 1))];
      }, route: '/event/concert/guide');
      expect(find.byKey(const Key('guideNowNext')), findsNothing, reason: 'one session is not a schedule');
      expect(find.byKey(const Key('guideAnnouncements')), findsOneWidget);
      expect(find.text('Gates open at 4'), findsOneWidget);
      expect(find.byKey(const Key('guideInfo')), findsOneWidget);
      expect(find.text('Smart casual'), findsOneWidget);
      expect(find.text('Thuwunna Stadium'), findsOneWidget);
      expect(find.text('Gate 3 is for ticket holders'), findsOneWidget);
      await h.finish();
    });

    testWidgets('good to know shows the FAQ alone too', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a, extra: {
          'faqs': [
            {'question': 'Can I bring kids?', 'answer': 'Yes'},
          ],
        });
      }, route: '/event/concert/guide');
      expect(find.byKey(const Key('guideInfo')), findsOneWidget);
      expect(find.text('Can I bring kids?'), findsOneWidget);
      await h.finish();
    });
  });

  group('tickets', () {
    testWidgets('one ticket: a single gold Show ticket button opens the ticket', (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      expect(find.byKey(const Key('guideShowTicket')), findsOneWidget);
      expect(find.text('Show ticket'), findsOneWidget);
      expect(goldButtons(tester), hasLength(1));
      await tester.tap(find.byKey(const Key('guideShowTicket')));
      await tester.pumpAndSettle();
      expect(find.byType(TicketScreen), findsOneWidget);
      expect(tester.widget<TicketScreen>(find.byType(TicketScreen)).ticketId, 'tk-concert-1');
      await h.finish();
    });

    testWidgets('two tickets: rows with seats, one says checked in, no gold button', (tester) async {
      final checkedAt = base.add(const Duration(days: 3, minutes: 12));
      final h = await pumpGuide(tester, setup: (a) {
        a.eventData['gala'] = eventJson('gala', starts: const Duration(days: 3), extra: {
          'seating': {'seatMapVersionId': 'v1', 'venueName': 'National Theatre'},
        });
        a.tickets = [
          ticketJson('tk-gala-1', 'gala', type: 'Stalls', extra: {'seatKey': 'A:1:1', 'seatLabel': 'Stalls · Row 1 · Seat 1'}),
          ticketJson('tk-gala-2', 'gala', type: 'Stalls', status: 'CHECKED_IN', extra: {'seatKey': 'A:1:2', 'seatLabel': 'Stalls · Row 1 · Seat 2', 'checkedInAt': checkedAt.toIso8601String()}),
          ticketJson('tk-gala-3', 'gala', type: 'Stalls', status: 'REFUNDED', extra: {'seatLabel': 'Stalls · Row 9 · Seat 9'}),
        ];
      }, route: '/event/gala/guide');
      expect(find.byKey(const Key('guideTicket-tk-gala-1')), findsOneWidget);
      expect(find.byKey(const Key('guideTicket-tk-gala-2')), findsOneWidget);
      expect(find.byKey(const Key('guideTicket-tk-gala-3')), findsNothing, reason: 'a refunded ticket is not a way in');
      expect(find.text('Stalls · Row 1 · Seat 1'), findsOneWidget);
      expect(find.text('Stalls · Row 1 · Seat 2'), findsOneWidget);
      expect(textOf(tester, 'guideChecked-tk-gala-2'), 'Checked in at ${formatTime(checkedAt, 'en')}');
      expect(find.byKey(const Key('guideShowTicket')), findsNothing);
      expect(goldButtons(tester), isEmpty);
      await tester.tap(find.byKey(const Key('guideTicket-tk-gala-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<TicketScreen>(find.byType(TicketScreen)).ticketId, 'tk-gala-1');
      await h.finish();
    });
  });

  group('now and next', () {
    testWidgets('the festival at a pinned time: Chef talk is on with Watch, then Tasting and Finale', (tester) async {
      final h = await pumpGuide(tester, now: festivalNow, setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
        a.streamData['fest'] = liveStream('s4');
      }, route: '/event/fest/guide');
      final now = find.byKey(const Key('guideNow'));
      final next = find.byKey(const Key('guideNext'));
      expect(find.descendant(of: now, matching: find.text('Chef talk')), findsOneWidget);
      expect(find.descendant(of: now, matching: find.text('Opening')), findsNothing);
      expect(find.descendant(of: now, matching: find.text('Watch')), findsOneWidget);
      expect(find.descendant(of: next, matching: find.text('Tasting')), findsOneWidget);
      expect(find.descendant(of: next, matching: find.text('Finale')), findsOneWidget);
      expect(find.descendant(of: next, matching: find.byType(OutlinedButton)), findsNothing, reason: 'only a live session can be watched');
      expect(find.textContaining('Tent B'), findsOneWidget, reason: 'location shown');
      await tester.tap(find.byKey(const Key('guideWatch-s4')));
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsWidgets);
      expect(GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path, startsWith('/watch/live/'));
      await h.finish();
    });

    testWidgets('Full schedule lists every session grouped by day', (tester) async {
      final h = await pumpGuide(tester, now: festivalNow, setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      }, route: '/event/fest/guide');
      await reveal(tester, find.byKey(const Key('guideFullSchedule')));
      await tester.tap(find.byKey(const Key('guideFullSchedule')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('guideScheduleSheet'));
      for (final day in ['Thu, 10 Dec', 'Fri, 11 Dec', 'Sat, 12 Dec']) {
        expect(find.descendant(of: sheet, matching: find.text(day)), findsOneWidget, reason: day);
      }
      for (final s in ['Opening', 'Cooking show', 'Night market', 'Chef talk', 'Tasting', 'Finale']) {
        expect(find.descendant(of: sheet, matching: find.text(s)), findsOneWidget, reason: s);
      }
      await h.finish();
    });

    testWidgets('nothing live: no Watch button', (tester) async {
      final h = await pumpGuide(tester, now: festivalNow, setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
        a.streamData['fest'] = liveStream('s4', live: false);
      }, route: '/event/fest/guide');
      expect(find.text('Watch'), findsNothing);
      await h.finish();
    });
  });

  group('venue, online, cancelled, ended', () {
    testWidgets('Directions opens the venue map pin', (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      await reveal(tester, find.byKey(const Key('guideDirections')));
      await tester.tap(find.byKey(const Key('guideDirections')));
      await tester.pump();
      expect(h.opened.single.toString(), 'https://www.google.com/maps/search/?api=1&query=16.8,96.15');
      await h.finish();
    });

    test('directions fall back to the map link, then to a name search', () {
      final pin = Venue(name: 'A', city: 'Yangon', mapUrl: 'https://maps.example/a', latitude: 1.5, longitude: 2.5);
      expect(guideDirectionsUri(pin).toString(), contains('query=1.5,2.5'));
      final link = Venue(name: 'A', city: 'Yangon', mapUrl: 'https://maps.example/a');
      expect(guideDirectionsUri(link).toString(), 'https://maps.example/a');
      final name = Venue(name: 'Thuwunna Stadium', address: 'Thuwunna Rd', city: 'Yangon');
      expect(guideDirectionsUri(name).toString(), 'https://www.google.com/maps/search/?api=1&query=Thuwunna%20Stadium%2C%20Thuwunna%20Rd%2C%20Yangon');
    });

    testWidgets('online-only: Watch and no venue', (tester) async {
      final h = await pumpGuide(tester, now: base.add(const Duration(hours: 1)), setup: (a) {
        a.eventData['web'] = eventJson('web', starts: Duration.zero, extra: {'format': 'ONLINE', 'venue': null});
        a.tickets = [ticketJson('tk-web', 'web', starts: Duration.zero)];
        a.streamData['web'] = liveStream('w1', title: 'Keynote');
      }, route: '/event/web/guide');
      expect(find.byKey(const Key('guideVenue')), findsNothing);
      expect(find.byKey(const Key('guideWatchEntry')), findsOneWidget);
      expect(find.text('Keynote'), findsOneWidget);
      expect(find.byKey(const Key('guideWatch-w1')), findsOneWidget);
      await h.finish();
    });

    testWidgets('cancelled: only the header, tickets and announcements', (tester) async {
      final h = await pumpGuide(tester, now: base.subtract(const Duration(days: 1)), setup: (a) {
        a.eventData['gone'] = festivalJson()
          ..['id'] = 'gone'
          ..['status'] = 'CANCELLED';
        a.tickets = [ticketJson('tk-gone', 'gone', starts: Duration.zero, length: const Duration(hours: 52), eventStatus: 'CANCELLED')];
        a.announcementData['gone'] = [announcement('a1', 'Refunds are on the way', const Duration(hours: 2))];
      }, route: '/event/gone/guide');
      expect(textOf(tester, 'guideStatus'), 'This event was cancelled');
      expect(find.byKey(const Key('guideTickets')), findsOneWidget);
      expect(find.byKey(const Key('guideAnnouncements')), findsOneWidget);
      for (final k in ['guideNowNext', 'guideVenue', 'guideInfo', 'guideThanks', 'guideWatchEntry']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      await h.finish();
    });

    testWidgets('ended: thank you and the recording, no now and next', (tester) async {
      final h = await pumpGuide(tester, now: base.add(const Duration(days: 3)), setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
        a.streamData['fest'] = {
          'live': [],
          'recordings': [
            {'id': 'a0000000-0000-0000-0000-000000000001', 'sessionId': null, 'title': 'Highlights', 'titleMy': null, 'durationSec': 125, 'availableUntil': at(const Duration(days: 30))},
          ],
        };
      }, route: '/event/fest/guide');
      expect(textOf(tester, 'guideStatus'), 'Ended');
      expect(find.text('Thank you for coming'), findsOneWidget);
      expect(find.byKey(const Key('guideThanks')), findsOneWidget);
      expect(find.text('Highlights'), findsOneWidget);
      expect(find.byKey(const Key('guideNowNext')), findsNothing);
      expect(find.byKey(const Key('guideFullSchedule')), findsNothing);
      await h.finish();
    });
  });

  group('announcements', () {
    final long = List.filled(60, 'ကြေညာချက်အရှည်ကြီး').join(' ');

    testWidgets('three on the guide, clamped; See all lists all of them in full', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [
          for (var i = 1; i <= 5; i++) announcement('a$i', 'News $i', Duration(hours: i), body: 'Body $i ' * 80),
        ];
      }, route: '/event/concert/guide');
      expect(find.text('News 1'), findsOneWidget);
      expect(find.text('News 3'), findsOneWidget);
      expect(find.text('News 4'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('announcementBody-a1'))).maxLines, 3);
      await reveal(tester, find.byKey(const Key('guideSeeAllAnnouncements')));
      await tester.tap(find.byKey(const Key('guideSeeAllAnnouncements')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('guideAnnouncementsSheet'));
      expect(find.descendant(of: sheet, matching: find.text('News 1')), findsOneWidget);
      await tester.scrollUntilVisible(find.descendant(of: sheet, matching: find.text('News 5')), 200, scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)).first);
      final body = tester.widget<Text>(find.descendant(of: sheet, matching: find.byKey(const Key('announcementBody-a5'))));
      expect(body.maxLines, isNull, reason: 'the sheet wraps, it does not truncate');
      expect(body.overflow, isNot(TextOverflow.ellipsis));
      await h.finish();
    });

    testWidgets('a 500-character Myanmar body is wrapped in the sheet', (tester) async {
      final body500 = long.substring(0, 500);
      final h = await pumpGuide(tester, lang: 'my', setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [for (var i = 1; i <= 4; i++) announcement('a$i', 'News $i', Duration(hours: i), body: 'x', bodyMy: body500)];
      }, route: '/event/concert/guide');
      await reveal(tester, find.byKey(const Key('guideSeeAllAnnouncements')));
      await tester.tap(find.byKey(const Key('guideSeeAllAnnouncements')));
      await tester.pumpAndSettle();
      final text = find.descendant(of: find.byKey(const Key('guideAnnouncementsSheet')), matching: find.byKey(const Key('announcementBody-a1')));
      expect(tester.widget<Text>(text).data, body500);
      expect(tester.takeException(), isNull);
      await h.finish();
    });

    testWidgets('a 403 for announcements shows the guide without them', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementsError = 403;
      }, route: '/event/concert/guide');
      expect(find.byKey(const Key('guideStatus')), findsOneWidget);
      expect(find.byKey(const Key('guideAnnouncements')), findsNothing);
      expect(find.byKey(const Key('guideNeverSaved')), findsNothing);
      await h.finish();
    });

    testWidgets('another error shows the error state with Retry', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementsError = 500;
      }, route: '/event/concert/guide');
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const Key('guideStatus')), findsNothing);
      h.api.announcementsError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guideStatus')), findsOneWidget);
      await h.finish();
    });
  });

  group('access', () {
    testWidgets('no ticket at all: sent to the event page', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.tickets = [];
      }, route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsNothing);
      expect(find.byType(EventDetailScreen), findsOneWidget);
      await h.finish();
    });

    testWidgets('only a refunded ticket: sent to the event page', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.tickets = [ticketJson('tk-r', 'concert', status: 'REFUNDED')];
      }, route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsNothing);
      expect(find.byType(EventDetailScreen), findsOneWidget);
      await h.finish();
    });

    testWidgets('a ticket for another event does not open this guide', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.eventData['other'] = eventJson('other', starts: const Duration(days: 3));
        a.tickets = [ticketJson('tk-o', 'other')];
      }, route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsNothing);
      await h.finish();
    });

    testWidgets('signed out: sent to log in', (tester) async {
      final h = await pumpGuide(tester, signedIn: false, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      await h.finish();
    });

    testWidgets('a checked-in ticket opens the guide', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.tickets = [ticketJson('tk-in', 'concert', status: 'CHECKED_IN')];
      }, route: '/event/concert/guide');
      expect(find.byType(EventGuideScreen), findsOneWidget);
      expect(textOf(tester, 'guideChecked-tk-in'), 'Checked in');
      await h.finish();
    });
  });

  group('offline', () {
    final savedAt = base.subtract(const Duration(hours: 2));
    final festRaw = festivalJson();
    final festTickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
    final manyAnnouncements = [for (var i = 1; i <= 4; i++) announcement('a$i', 'News $i', Duration(hours: i + 3))];

    testWidgets('network failure with a saved copy: content, the label and the disabled actions', (tester) async {
      final h = await pumpGuide(
        tester,
        now: festivalNow,
        prefs: seedPrefs(tickets: festTickets, saved: {'fest': (festRaw, manyAnnouncements, savedAt)}),
        setup: (a) {
          a.offline = true;
          a.tickets = festTickets;
        },
        route: '/event/fest/guide',
      );
      expect(find.byKey(const Key('guideTitle')), findsOneWidget);
      expect(find.byKey(const Key('guideNow')), findsOneWidget, reason: 'now and next from the saved copy');
      expect(textOf(tester, 'guideSavedCopy'), 'Saved copy · updated ${formatEventDate(savedAt, 'en')}. Newer announcements may exist.');
      final directions = find.byKey(const Key('guideDirections'));
      await reveal(tester, directions);
      expect(tester.widget<OutlinedButton>(directions).onPressed, isNull);
      final seeAll = find.byKey(const Key('guideSeeAllAnnouncements'));
      await reveal(tester, seeAll);
      expect(tester.widget<TextButton>(seeAll).onPressed, isNull);
      expect(find.text('Needs a connection'), findsAtLeastNWidgets(2));
      expect(find.byKey(const Key('guideNeverSaved')), findsNothing);
      expect(find.text('Watch'), findsNothing, reason: 'no stream list offline');
      await h.finish();
    });

    testWidgets('online-only event offline: Watch is disabled and says so', (tester) async {
      final web = eventJson('web', starts: Duration.zero, extra: {'format': 'ONLINE', 'venue': null});
      final tickets = [ticketJson('tk-web', 'web', starts: Duration.zero)];
      final h = await pumpGuide(
        tester,
        now: base.add(const Duration(hours: 1)),
        prefs: seedPrefs(tickets: tickets, saved: {'web': (web, const [], savedAt)}),
        setup: (a) => a.offline = true,
        route: '/event/web/guide',
      );
      final watch = find.byKey(const Key('guideWatchOffline'));
      expect(watch, findsOneWidget);
      expect(tester.widget<OutlinedButton>(watch).onPressed, isNull);
      expect(find.text('Needs a connection'), findsOneWidget);
      await h.finish();
    });

    testWidgets('network failure and nothing saved: connect-once note, tickets still shown', (tester) async {
      final h = await pumpGuide(
        tester,
        prefs: seedPrefs(tickets: festTickets),
        setup: (a) => a.offline = true,
        route: '/event/fest/guide',
      );
      expect(find.byKey(const Key('guideNeverSaved')), findsOneWidget);
      expect(find.text('Connect once to save this event for offline use.'), findsOneWidget);
      expect(find.byKey(const Key('guideSavedCopy')), findsNothing);
      expect(find.byKey(const Key('guideShowTicket')), findsOneWidget);
      expect(find.byKey(const Key('guideVenue')), findsNothing);
      await h.finish();
    });

    testWidgets('a successful load writes the saved copy; sign-out clears it', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [announcement('a1', 'Gates open at 4', const Duration(hours: 1))];
      }, route: '/event/concert/guide');
      final cache = h.container.read(eventCacheProvider);
      final saved = cache.read('concert');
      expect(saved, isNotNull);
      expect(saved!.event['id'], 'concert');
      expect(saved.announcements.single.title, 'Gates open at 4');
      expect(saved.savedAt, base);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isNotEmpty);

      await h.container.read(sessionProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(h.container.read(eventCacheProvider).read('concert'), isNull);
      expect(h.prefs.getKeys().where((k) => k.startsWith(EventCache.prefix)), isEmpty);
      expect(h.prefs.getString(MyTicketsNotifier.cacheKey), isNull);
      expect(h.container.read(myTicketsProvider).value, isEmpty, reason: 'the ticket list reloads for the signed-out session');
      expect(find.byType(LoginScreen), findsOneWidget, reason: 'the open guide sends a signed-out viewer to log in');
      await h.finish();
    });

    testWidgets('a copy is kept when the network is back and then fails again (served with its own save time)', (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      expect(find.byKey(const Key('guideSavedCopy')), findsNothing);
      h.api.offline = true;
      h.now = () => base.add(const Duration(minutes: 5));
      await tester.pump(guideRefreshInterval);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guideSavedCopy')), findsOneWidget);
      expect(textOf(tester, 'guideSavedCopy'), contains(formatEventDate(base, 'en')));
      await h.finish();
    });
  });

  group('refetch', () {
    testWidgets('every five minutes while open, and not after the screen is closed', (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a));
      // The background saver fetched the event when the tickets loaded; count only what the open guide does.
      h.api.rawCalls = 0;
      h.api.announcementCalls = 0;
      await h.go('/event/concert/guide');
      const saver = 0;
      expect(h.api.rawCalls, saver + 1);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(h.api.rawCalls, saver + 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(h.api.rawCalls, saver + 2);
      expect(h.api.announcementCalls, saver + 2);
      await tester.pump(guideRefreshInterval);
      await tester.pumpAndSettle();
      expect(h.api.rawCalls, saver + 3);
      expect(find.byKey(const Key('guideStatus')), findsOneWidget, reason: 'content stays while refreshing');
      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(EventGuideScreen), findsNothing);
      await tester.pump(const Duration(minutes: 20));
      expect(h.api.rawCalls, saver + 3);
      await h.finish();
    });
  });

  group('fix round 1', () {
    for (final signOutFirst in [true, false]) {
    testWidgets("one user's tickets never reach the next session (${signOutFirst ? 'after sign-out' : 'signing straight in as someone else'})", (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      expect(find.byKey(const Key('guideShowTicket')), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      if (signOutFirst) {
        await h.container.read(sessionProvider.notifier).signOut();
        await tester.pumpAndSettle();
      }
      // User B signs in (slowly) and holds nothing for this event.
      h.api
        ..tickets = []
        ..meId = 'u2'
        ..meDelay = const Duration(milliseconds: 300);
      await h.api.tokensStore.save('b', 'r');
      final gate = Completer<void>(); // B's ticket list is slow too
      h.api.ticketGate = gate;
      final signedIn = h.container.read(sessionProvider.notifier).signedIn();
      h.router.push('/event/concert/guide');
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byKey(const Key('guideShowTicket')), findsNothing, reason: 'frame $i');
        expect(find.byKey(const Key('guideTicket-tk-concert-1')), findsNothing, reason: 'frame $i');
        expect(find.byKey(const Key('guideTickets')), findsNothing, reason: 'frame $i');
      }
      await signedIn;
      h.router.go('/tickets');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing, reason: "while B's list loads");
      expect(find.byKey(const Key('guideShowTicket')), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      h.router.push('/event/concert/guide');
      await tester.pumpAndSettle();
      expect(find.byType(EventGuideScreen), findsNothing);
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.byKey(const Key('ticketGroup-concert')), findsNothing);
      await h.finish();
    });
    }

    testWidgets('a ticket fetch in flight at sign-out does not rewrite the ticket cache', (tester) async {
      final gate = Completer<void>();
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.ticketGate = gate;
      });
      await h.container.read(sessionProvider.notifier).signOut();
      await tester.pump();
      expect(h.prefs.getString(MyTicketsNotifier.cacheKey), isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(h.prefs.getString(MyTicketsNotifier.cacheKey), isNull, reason: 'the late answer must not be saved for nobody');
      await h.finish();
    });

    testWidgets('opened by slug: announcements load, the copy is saved under the id and survives prune', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        setUpConcert(a);
        a.announcementData['concert'] = [announcement('a1', 'Gates open at 4', const Duration(hours: 1))];
      }, route: '/event/slug-concert/guide');
      expect(find.text('Gates open at 4'), findsOneWidget);
      final cache = h.container.read(eventCacheProvider);
      expect(cache.read('concert')!.announcements, hasLength(1));
      expect(cache.read('slug-concert'), isNull);
      await cache.prune(keepEventIds: {'concert'});
      expect(cache.read('concert'), isNotNull);
      await h.finish();
    });

    testWidgets('opened by slug while offline: the saved copy is found by its slug', (tester) async {
      final tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      final h = await pumpGuide(
        tester,
        now: festivalNow,
        prefs: seedPrefs(tickets: tickets, saved: {'fest': (festivalJson(), const [], base)}),
        setup: (a) => a.offline = true,
        route: '/event/slug-fest/guide',
      );
      expect(find.byKey(const Key('guideSavedCopy')), findsOneWidget);
      expect(find.byKey(const Key('guideNow')), findsOneWidget);
      await h.finish();
    });

    testWidgets('the refetch and the clock pause in the background and refresh once on resume', (tester) async {
      final h = await pumpGuide(tester, setup: (a) => setUpConcert(a), route: '/event/concert/guide');
      final calls = h.api.rawCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 20));
      expect(h.api.rawCalls, calls, reason: 'nothing ticks in the background');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.api.rawCalls, calls + 1, reason: 'one refresh on resume');
      await tester.pump(guideRefreshInterval);
      await tester.pumpAndSettle();
      expect(h.api.rawCalls, calls + 2, reason: 'the interval runs again');
      await h.finish();
    });

    testWidgets('a saved entry that is not an event counts as never saved and is removed', (tester) async {
      final tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      final h = await pumpGuide(
        tester,
        prefs: seedPrefs(tickets: tickets, saved: {'fest': ({'id': 'fest', 'slug': 'slug-fest', 'nonsense': true}, const [], base)}),
        setup: (a) => a.offline = true,
        route: '/event/fest/guide',
      );
      expect(find.byKey(const Key('guideNeverSaved')), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(h.prefs.getString('${EventCache.prefix}fest'), isNull);
      await h.finish();
    });

    testWidgets('an event that was removed shows a gone state with a back action, not Retry', (tester) async {
      final h = await pumpGuide(tester, setup: (a) {
        a.tickets = [ticketJson('tk-gone', 'gone')];
      }, route: '/event/gone/guide');
      expect(find.text('This event is no longer available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(EventGuideScreen), findsNothing);
      await h.finish();
    });

    testWidgets('offline, an event with online sessions shows Watch disabled in Now and next', (tester) async {
      final hybrid = {...festivalJson(), 'format': 'HYBRID'};
      final tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      final h = await pumpGuide(
        tester,
        now: festivalNow,
        prefs: seedPrefs(tickets: tickets, saved: {'fest': (hybrid, const [], base)}),
        setup: (a) => a.offline = true,
        route: '/event/fest/guide',
      );
      final watch = find.byKey(const Key('guideWatchOfflineSessions'));
      expect(watch, findsOneWidget);
      expect(tester.widget<OutlinedButton>(watch).onPressed, isNull);
      expect(find.descendant(of: find.byKey(const Key('guideNowNext')), matching: find.text('Needs a connection')), findsOneWidget);
      await h.finish();
    });

    testWidgets('online-only and live-soon but no stream yet: Watch is disabled with a note', (tester) async {
      final h = await pumpGuide(tester, now: base.add(const Duration(hours: 1)), setup: (a) {
        a.eventData['web'] = eventJson('web', starts: Duration.zero, extra: {'format': 'ONLINE', 'venue': null});
        a.tickets = [ticketJson('tk-web', 'web', starts: Duration.zero)];
      }, route: '/event/web/guide');
      final watch = find.byKey(const Key('guideWatchNotStarted'));
      expect(tester.widget<OutlinedButton>(watch).onPressed, isNull);
      expect(find.text('Stream not started yet'), findsOneWidget);
      await h.finish();
    });

    testWidgets('announcements 403 with a saved copy: stale announcements are not shown and are removed from the copy', (tester) async {
      final tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      final h = await pumpGuide(
        tester,
        now: festivalNow,
        prefs: seedPrefs(tickets: tickets, saved: {'fest': (festivalJson(), [announcement('old', 'Stale news', const Duration(hours: 5))], festivalNow)}),
        setup: (a) {
          a.eventData['fest'] = festivalJson();
          a.tickets = tickets;
          a.announcementsError = 403;
        },
        route: '/event/fest/guide',
      );
      expect(find.text('Stale news'), findsNothing);
      expect(find.byKey(const Key('guideAnnouncements')), findsNothing);
      expect(h.container.read(eventCacheProvider).read('fest')!.announcements, isEmpty);
      await h.finish();
    });

    testWidgets('the status line flips to On now when the clock passes the start, without a refresh', (tester) async {
      final h = await pumpGuide(tester, now: base.subtract(const Duration(seconds: 90)), setup: (a) {
        a.eventData['x'] = eventJson('x', starts: Duration.zero);
        a.tickets = [ticketJson('tk-x', 'x', starts: Duration.zero)];
      }, route: '/event/x/guide');
      expect(textOf(tester, 'guideStatus'), 'Starts in 1 minute');
      final calls = h.api.rawCalls;
      h.now = () => base.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(textOf(tester, 'guideStatus'), 'On now');
      expect(h.api.rawCalls, calls);
      await h.finish();
    });

    testWidgets('signed out: the deep link returns to the guide after signing in', (tester) async {
      final h = await pumpGuide(tester, signedIn: false, setup: (a) => setUpConcert(a));
      h.router.go('/event/concert/guide'); // a link opened cold: nothing underneath
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), '09790000001');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(EventGuideScreen), findsOneWidget);
      expect(find.byKey(const Key('guideShowTicket')), findsOneWidget);
      await h.finish();
    });
  });

  // ───── Large-text sweep: 390x844, text scale 2.0, EN and MY ─────

  Future<void> scrollThrough(WidgetTester tester) async {
    final count = find.byType(Scrollable).evaluate().length;
    for (var i = 0; i < count; i++) {
      if (i >= find.byType(Scrollable).evaluate().length) break;
      final f = find.byType(Scrollable).at(i);
      final horizontal = tester.state<ScrollableState>(f).axisDirection == AxisDirection.right;
      for (var k = 0; k < 10; k++) {
        await tester.drag(f, horizontal ? const Offset(-250, 0) : const Offset(0, -350), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  final longBody = 'ကြေညာချက်အရှည်ကြီး ' * 40;
  final sweep = <String, ({String route, DateTime now, Map<String, Object> Function() prefs, void Function(GuideApi) setup, Future<void> Function(WidgetTester)? then})>{
    'festival on now': (
      route: '/event/fest/guide',
      now: festivalNow,
      prefs: () => {},
      setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
        a.streamData['fest'] = liveStream('s4');
        a.announcementData['fest'] = [for (var i = 1; i <= 4; i++) announcement('a$i', 'A fairly long announcement title number $i for the guests', Duration(hours: i), body: 'Gates open at four and the long queue forms on the left side. ' * 6, bodyMy: longBody.substring(0, 480))];
      },
      then: (t) async {
        await reveal(t, find.byKey(const Key('guideSeeAllAnnouncements')));
        await t.tap(find.byKey(const Key('guideSeeAllAnnouncements')));
        await t.pumpAndSettle();
      },
    ),
    'festival full schedule': (
      route: '/event/fest/guide',
      now: festivalNow,
      prefs: () => {},
      setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
      },
      then: (t) async {
        await reveal(t, find.byKey(const Key('guideFullSchedule')));
        await t.tap(find.byKey(const Key('guideFullSchedule')));
        await t.pumpAndSettle();
      },
    ),
    'seated gala, two tickets': (
      route: '/event/gala/guide',
      now: base,
      prefs: () => {},
      setup: (a) {
        a.eventData['gala'] = eventJson('gala', starts: const Duration(days: 3), extra: {'seating': {'seatMapVersionId': 'v1', 'venueName': 'National Theatre'}, 'dressCode': 'Black tie', 'languages': 'Burmese and English'});
        a.tickets = [
          ticketJson('tk-gala-1', 'gala', type: 'Stalls', extra: {'seatKey': 'A:1:1', 'seatLabel': 'Stalls · Row 1 · Seat 1', 'seatLabelMy': 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1'}),
          ticketJson('tk-gala-2', 'gala', type: 'Stalls', status: 'CHECKED_IN', extra: {'seatKey': 'A:1:2', 'seatLabel': 'Stalls · Row 1 · Seat 2', 'seatLabelMy': 'ရှေ့ခန်း · အတန်း 1 · ခုံ 2', 'checkedInAt': at(const Duration(days: 3, minutes: 12))}),
        ];
      },
      then: null,
    ),
    'cancelled': (
      route: '/event/gone/guide',
      now: base,
      prefs: () => {},
      setup: (a) {
        a.eventData['gone'] = {...festivalJson(), 'id': 'gone', 'status': 'CANCELLED'};
        a.tickets = [ticketJson('tk-gone', 'gone', starts: Duration.zero, length: const Duration(hours: 52), eventStatus: 'CANCELLED')];
        a.announcementData['gone'] = [announcement('a1', 'Refunds', const Duration(hours: 1), body: 'Your refund will arrive within five working days. ' * 4)];
      },
      then: null,
    ),
    'ended with a recording': (
      route: '/event/fest/guide',
      now: base.add(const Duration(days: 3)),
      prefs: () => {},
      setup: (a) {
        a.eventData['fest'] = festivalJson();
        a.tickets = [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))];
        a.streamData['fest'] = {
          'live': [],
          'recordings': [
            {'id': 'a0000000-0000-0000-0000-000000000001', 'sessionId': null, 'title': 'Highlights from the whole festival weekend', 'titleMy': null, 'durationSec': 125, 'availableUntil': at(const Duration(days: 30))},
          ],
        };
      },
      then: null,
    ),
    'saved copy': (
      route: '/event/fest/guide',
      now: festivalNow,
      prefs: () => seedPrefs(
            tickets: [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))],
            saved: {'fest': (festivalJson(), [for (var i = 1; i <= 4; i++) announcement('a$i', 'News $i', Duration(hours: i + 3))], base)},
          ),
      setup: (a) => a.offline = true,
      then: null,
    ),
    'never saved': (
      route: '/event/fest/guide',
      now: festivalNow,
      prefs: () => seedPrefs(tickets: [ticketJson('tk-fest', 'fest', starts: Duration.zero, length: const Duration(hours: 52))]),
      setup: (a) => a.offline = true,
      then: null,
    ),
  };

  for (final lang in ['en', 'my']) {
    for (final entry in sweep.entries) {
      testWidgets('large text: guide, ${entry.key}, has no overflow at 390x844, scale 2.0, $lang', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = entry.value;
        final errors = <String>[];
        final h = await pumpGuide(tester, lang: lang, now: c.now, prefs: c.prefs(), setup: c.setup);
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toDiagnosticsNode().toStringDeep().split('\n').where((l) => l.contains('overflowed') || l.contains('/lib/') || l.contains('package:user_app')).take(6).join(' / '));
        try {
          await h.go(c.route);
          await tester.pump(const Duration(milliseconds: 600));
          expect(errors, isEmpty, reason: 'opened');
          expect(find.byType(EventGuideScreen), findsOneWidget);
          if (c.then != null) {
            await c.then!(tester);
            expect(errors, isEmpty, reason: 'after action');
          }
          await scrollThrough(tester);
          expect(errors, isEmpty, reason: 'scrolled');
        } finally {
          FlutterError.onError = previous;
        }
        await h.finish();
      });
    }
  }
}
