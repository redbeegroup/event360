import 'dart:async';
import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_app/app/format.dart';
import 'package:user_app/app/providers.dart';
import 'package:user_app/app/push.dart';
import 'package:user_app/main.dart';
import 'package:user_app/screens/checkout_screen.dart';
import 'package:user_app/screens/watch_screen.dart';

/// Fake API: canned events/tickets, no network.
class FakeApi extends Event360Api {
  FakeApi(this.store) : super(const AppConfig(app: Event360App.user, apiBaseUrl: 'http://fake'), store);
  final MemoryTokenStore store;
  bool offline = false;
  int? watchError; // e.g. 403
  bool takenOver = false;
  final heartbeats = <String>[];
  final registered = <String>[];
  List<PaymentMethod> methods = [];
  final orders = <String, Map<String, dynamic>>{};
  final paid = <String>[];
  final readIds = <List<String>>[];
  final devices = <String>[];
  List<Map<String, dynamic>> inbox = [
    {'id': 'n1', 'kind': 'event_changed', 'title': 'Event details changed', 'titleMy': null, 'body': 'Yangon Food Fair e1 is now Sat 16 Jan', 'bodyMy': null, 'link': '/event/e1', 'eventId': 'e1', 'readAt': null, 'createdAt': '2026-11-20T10:00:00.000Z'},
    {'id': 'n2', 'kind': 'announcement', 'title': 'Gates open at 4', 'titleMy': null, 'body': 'Bring your QR', 'bodyMy': null, 'link': '/event/e1', 'eventId': 'e1', 'readAt': null, 'createdAt': '2026-11-20T09:00:00.000Z'},
    {'id': 'n3', 'kind': 'ticket_confirmed', 'title': 'Your ticket is ready', 'titleMy': null, 'body': 'Show the QR', 'bodyMy': null, 'link': '/tickets', 'eventId': 'e1', 'readAt': '2026-11-19T09:00:00.000Z', 'createdAt': '2026-11-19T09:00:00.000Z'},
  ];

  @override
  Future<Inbox> notifications({DateTime? before, int limit = 30}) async =>
      Inbox.fromJson({'items': inbox, 'unread': inbox.where((n) => n['readAt'] == null).length});

  @override
  Future<void> markNotificationsRead([List<String> ids = const []]) async {
    readIds.add(ids);
    inbox = [for (final n in inbox) (ids.isEmpty || ids.contains(n['id'])) ? {...n, 'readAt': '2026-11-20T11:00:00.000Z'} : n];
  }

  @override
  Future<void> registerDevice(String pushToken, String platform, {String appId = 'user_app'}) async => devices.add('$platform:$pushToken');

  @override
  Future<void> removeDevice(String pushToken) async => devices.remove('android:$pushToken');

  static Map<String, dynamic> orderJson(String id, String status, {int total = 10000, int qty = 2, String? provider, Map<String, dynamic>? action, DateTime? expires}) => {
        'id': id,
        'status': status,
        'event': {'id': 'e2', 'title': 'Yangon Food Fair e2', 'titleMy': null},
        'items': [
          {'ticketTypeId': 'tt-e2', 'name': 'General', 'nameMy': null, 'quantity': qty, 'unitPriceMmk': total ~/ qty},
        ],
        'subtotalMmk': total,
        'totalMmk': total,
        'holdExpiresAt': (expires ?? DateTime.now().toUtc().add(const Duration(minutes: 10))).toIso8601String(),
        'payment': provider == null ? null : {'id': 'p1', 'provider': provider, 'status': 'PENDING', 'action': action},
        'ticketIds': status == 'PAID' ? ['t1', 't2'] : <String>[],
      };

  @override
  Future<List<PaymentMethod>> paymentMethods() async => methods;

  @override
  Future<Order> createOrder(String eventId, Map<String, int> quantities, {required String idempotencyKey, String channel = 'APP'}) async {
    final e = quantities.entries.first;
    registered.add('$eventId:${e.key}:${e.value}');
    if (eventId == 'e1') return Order.fromJson({...orderJson('free-1', 'CONFIRMED', total: 0, qty: e.value), 'ticketIds': ['t1']});
    final o = orderJson('ord-1', 'PENDING_PAYMENT', total: 5000 * e.value, qty: e.value);
    orders['ord-1'] = o;
    return Order.fromJson(o);
  }

  @override
  Future<Order> order(String id) async => Order.fromJson(orders[id]!);

  @override
  Future<Order> payOrder(String id, String provider, {String? returnUrl}) async {
    paid.add('$id:$provider');
    orders[id] = {...orders[id]!, 'payment': {'id': 'p1', 'provider': provider, 'status': 'PENDING', 'action': {'type': 'REDIRECT', 'url': 'https://pay.example/$id'}}};
    return Order.fromJson(orders[id]!);
  }

  @override
  Future<Order> cancelOrder(String id) async {
    orders[id] = {...orders[id]!, 'status': 'CANCELLED'};
    return Order.fromJson(orders[id]!);
  }

  @override
  Future<List<Order>> pendingOrders() async => orders.values.where((o) => o['status'] == 'PENDING_PAYMENT').map(Order.fromJson).toList();

  static Map<String, dynamic> eventJson(String id, {bool free = true}) => {
        'id': id,
        'slug': 'slug-$id',
        'status': 'PUBLISHED',
        'title': 'Yangon Food Fair $id',
        'titleMy': 'ရန်ကုန် စားသောက်ပွဲ $id',
        'summary': 'Street food',
        'summaryMy': 'လမ်းဘေးစာ',
        'coverImageUrl': null,
        'format': 'IN_PERSON',
        'isFree': free,
        'minPriceMmk': free ? 0 : 5000,
        'startsAt': '2027-01-15T10:30:00.000Z',
        'endsAt': '2027-01-15T15:30:00.000Z',
        'category': {'nameEn': 'Food & Beverage Fair', 'nameMy': null},
        'venue': {'name': 'Kandawgyi Park', 'city': 'Yangon'},
        'organization': {'name': 'Yangon Live', 'kycStatus': 'APPROVED'},
        'ticketTypes': [
          {'id': 'tt-$id', 'name': 'General', 'nameMy': 'အထွေထွေ', 'priceMmk': free ? 0 : 5000, 'quota': 100, 'remaining': 42, 'maxPerOrder': 4},
        ],
        'soldOut': false,
      };

  @override
  Future<List<Category>> categories() async => [Category.fromJson({'id': 'c1', 'slug': 'lifestyle-social', 'nameEn': 'Lifestyle & Social'})];

  @override
  Future<EventPage> events({String? q, String? category, String? city, bool? free, DateTime? from, DateTime? to, int page = 1, int limit = 20}) async =>
      EventPage.fromJson({'items': [eventJson('e1'), eventJson('e2', free: false)], 'page': 1, 'limit': 20, 'total': 2});

  static Map<String, dynamic> richEventJson(String id) => {
        ...eventJson(id),
        'organization': {'name': 'Yangon Live', 'slug': 'yangon-live', 'kycStatus': 'APPROVED'},
        'venue': {'name': 'Kandawgyi Park', 'city': 'Yangon', 'directions': 'Enter from Natmauk Rd', 'lat': 16.79, 'lng': 96.17},
        'ageMin': 18,
        'dressCode': 'Smart casual',
        'refundPolicy': 'No refunds',
        'sessions': [
          {'title': 'Doors open', 'startsAt': '2027-01-15T10:30:00.000Z', 'endsAt': '2027-01-15T11:00:00.000Z', 'location': 'Main gate'},
        ],
        'performers': [
          {'name': 'Chef Aung', 'role': 'Host', 'bio': 'Award-winning chef'},
        ],
        'faqs': [
          {'question': 'Can I bring kids?', 'answer': 'Yes, under 12 free'},
        ],
      };

  @override
  Future<EventSummary> event(String idOrSlug) async =>
      EventSummary.fromJson(idOrSlug == 'rich' ? richEventJson(idOrSlug) : eventJson(idOrSlug, free: idOrSlug != 'e2'));

  @override
  Future<OrganizerProfile> organizer(String slug) async => OrganizerProfile.fromJson({
        'name': 'Yangon Live',
        'slug': slug,
        'verified': true,
        'description': 'We run food festivals',
        'website': 'https://example.com',
        'events': [eventJson('e1')],
      });

  @override
  Future<EventStreams> eventStreams(String idOrSlug) async => EventStreams.fromJson(idOrSlug == 'rich'
      ? {
          'live': [
            {'channelId': 'c0000000-0000-0000-0000-000000000001', 'sessionId': 's1', 'title': 'Keynote', 'titleMy': null, 'startsAt': '2027-01-15T10:30:00.000Z', 'endsAt': '2027-01-15T11:30:00.000Z', 'isLive': true},
          ],
          'recordings': [
            {'id': 'a0000000-0000-0000-0000-000000000001', 'sessionId': null, 'title': 'Highlights', 'titleMy': null, 'durationSec': 125, 'availableUntil': '2027-02-15T10:30:00.000Z'},
          ],
        }
      : {'live': [], 'recordings': []});

  @override
  Future<WatchGrant> watchToken(String kind, String id) async {
    if (watchError != null) throw ApiException(watchError, 'nope');
    return WatchGrant(url: 'https://api.example/v1/play/t/TOKEN/$kind/$id/index.m3u8', sessionId: 'ps1', watermark: '•••• 0001', heartbeatSeconds: 30);
  }

  @override
  Future<void> watchHeartbeat(String sessionId) async {
    heartbeats.add(sessionId);
    if (takenOver) throw ApiException(409, 'Playing on another device');
  }

  @override
  Future<Me> me() async => Me(id: 'u1', phone: '+959790000001');

  @override
  Future<String?> requestOtp(String phone) async => '123456';

  @override
  Future<void> verifyOtp(String phone, String code) async => store.save('a', 'r');

  @override
  Future<List<String>> register(String eventId, String ticketTypeId, int quantity) async {
    registered.add('$eventId:$ticketTypeId:$quantity');
    return ['t1'];
  }

  @override
  Future<List<MyTicket>> myTickets() async {
    if (offline) throw ApiException(null, 'Network error');
    return [
      MyTicket.fromApi({
        'id': 'ticket-0001-abcd',
        'status': 'VALID',
        'ticketType': {'name': 'General', 'nameMy': 'အထွေထွေ'},
        'event': {
          'id': 'e1',
          'title': 'Yangon Food Fair e1',
          'titleMy': null,
          'startsAt': '2099-01-15T10:30:00.000Z',
          'endsAt': '2099-01-15T15:30:00.000Z',
          'venue': {'name': 'Kandawgyi Park', 'city': 'Yangon'},
          'coverImageUrl': null,
          'organization': 'Yangon Live',
        },
        'qr': 'eyJ0aWQiOiJ0In0.c2ln',
      }),
    ];
  }
}

/// A typical Android phone screen (412×915 logical pixels).
void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 2745);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final openedUrls = <String>[];

class FakePush implements PushClient {
  final links = StreamController<String>.broadcast();
  @override
  bool get supported => true;
  @override
  Future<String?> token() async => 'fcm-token-1';
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<void> get onForeground => const Stream.empty();
  @override
  Stream<String> get onOpenLink => links.stream;
  @override
  Future<String?> initialLink() async => null;
  @override
  Future<void> deleteToken() async {}
}

Future<(FakeApi, SharedPreferences)> pumpApp(WidgetTester tester, {String lang = 'en', bool signedIn = false, Map<String, Object> prefs = const {}, void Function(FakeApi)? setup, PushClient? push}) async {
  phoneScreen(tester);
  SharedPreferences.setMockInitialValues({'lang': lang, ...prefs});
  final sp = await SharedPreferences.getInstance();
  final store = MemoryTokenStore();
  if (signedIn) await store.save('a', 'r');
  final api = FakeApi(store);
  setup?.call(api);
  openedUrls.clear();
  await tester.pumpWidget(ProviderScope(overrides: [
    openPaymentUrlProvider.overrideWithValue((url) async => openedUrls.add(url)),
    pushProvider.overrideWithValue(push ?? const NoPush()),
    prefsProvider.overrideWithValue(sp),
    apiProvider.overrideWithValue(api),
    // No video plugin in tests: show the URL the real player would open
    playerViewProvider.overrideWithValue(({required url, required live, required resumeKey, required onEnded}) => Text('PLAYER $url')),
  ], child: const UserApp()));
  await tester.pumpAndSettle();
  return (api, sp);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  testWidgets('first run asks for the language', (tester) async {
    phoneScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(overrides: [prefsProvider.overrideWithValue(sp), apiProvider.overrideWithValue(FakeApi(MemoryTokenStore()))], child: const UserApp()));
    await tester.pumpAndSettle();
    expect(find.text('မြန်မာ'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(sp.getString('lang'), 'en');
    expect(find.text('Upcoming events'), findsOneWidget);
  });

  testWidgets('home lists events with free / price labels (English)', (tester) async {
    await pumpApp(tester);
    expect(find.text('Yangon Food Fair e1'), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('From 5,000 MMK'), findsWidgets);
  });

  testWidgets('Myanmar UI shows Myanmar titles', (tester) async {
    await pumpApp(tester, lang: 'my');
    expect(find.text('ရန်ကုန် စားသောက်ပွဲ e1'), findsWidgets);
    expect(find.text('လာမည့်ပွဲများ'), findsOneWidget);
  });

  testWidgets('register requires sign-in, then registers after phone login', (tester) async {
    final (api, _) = await pumpApp(tester);
    await tester.tap(find.text('Yangon Food Fair e1').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'5:00\sPM')), findsWidgets); // 10:30 UTC = 17:00 Myanmar time
    await tester.tap(find.text('Register for free'));
    await tester.pumpAndSettle();
    // Login screen
    await tester.enterText(find.byType(TextField), '0912');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('valid Myanmar mobile number'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '09790000001');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Test environment code: 123456'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    // Back on the event, now signed in → register sheet
    await tester.tap(find.text('Register for free'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await tester.pumpAndSettle();
    expect(api.registered, ['e1:tt-e1:2']);
    expect(find.textContaining("You're registered"), findsOneWidget);
  });

  testWidgets('tickets show a QR and stay available offline from the cache', (tester) async {
    final (api, sp) = await pumpApp(tester, signedIn: true);
    await tester.tap(find.text('My tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Yangon Food Fair e1'), findsOneWidget);
    expect(sp.getString(MyTicketsNotifier.cacheKey), isNotNull);
    final cached = jsonDecode(sp.getString(MyTicketsNotifier.cacheKey)!) as List;
    expect(cached.single['qr'], 'eyJ0aWQiOiJ0In0.c2ln');

    // Go offline and reload: the cached ticket and its QR still show.
    api.offline = true;
    await tester.drag(find.text('Yangon Food Fair e1'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Available offline'), findsOneWidget);
    await tester.tap(find.text('Yangon Food Fair e1'));
    await tester.pumpAndSettle();
    expect(find.text('Show this QR code at the entrance'), findsOneWidget);
  });

  test('Myanmar phone validation mirrors the API', () {
    for (final ok in ['09790000001', '09 790 000 001', '+959790000001', '959790000001']) {
      expect(isValidMyanmarPhone(ok), isTrue, reason: ok);
    }
    for (final bad in ['0912', '12345678', '+6591234567', '0912345678901']) {
      expect(isValidMyanmarPhone(bad), isFalse, reason: bad);
    }
  });

  test('event times are shown in Myanmar time regardless of device zone', () {
    // intl uses a narrow no-break space before AM/PM; normalize it for the comparison.
    expect(formatEventDate(DateTime.utc(2027, 1, 15, 10, 30), 'en').replaceAll('\u202f', ' '), 'Fri, 15 Jan 2027 · 5:00 PM');
  });

  testWidgets('event detail shows schedule, lineup, practical info, FAQ and organizer page', (tester) async {
    await pumpApp(tester);
    final router = tester.element(find.byType(Scaffold).first);
    GoRouter.of(router).push('/event/rich');
    await tester.pumpAndSettle();
    Future<void> see(Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      expect(f, findsWidgets);
    }

    await see(find.text('Doors open'));
    await see(find.text('Chef Aung'));
    await see(find.text('Smart casual'));
    await see(find.text('Enter from Natmauk Rd'));
    await see(find.text('Can I bring kids?'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300)); // clear the bottom button
    await tester.pumpAndSettle();
    await tester.tap(find.text('Can I bring kids?'));
    await tester.pumpAndSettle();
    expect(find.text('Yes, under 12 free'), findsOneWidget);
    await see(find.text('Refund policy'));

    await tester.fling(find.byType(Scrollable).first, const Offset(0, 3000), 3000); // back to the top
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yangon Live'));
    await tester.pumpAndSettle();
    expect(find.text('We run food festivals'), findsOneWidget);
    expect(find.text('Yangon Food Fair e1'), findsWidgets);
  });

  testWidgets('event page lists the live stream and recordings; ticket holders watch with a watermark', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/rich');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Keynote'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.textContaining('02:05'), findsOneWidget);
    await tester.tap(find.text('Keynote'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYER https://api.example/v1/play/t/TOKEN/live/c0000000-0000-0000-0000-000000000001/index.m3u8'), findsOneWidget);
    expect(find.text('•••• 0001'), findsOneWidget);
    // Heartbeat every 30 s; another device taking over stops playback here
    await tester.pump(const Duration(seconds: 31));
    expect(api.heartbeats, ['ps1']);
    api.takenOver = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.textContaining('another device'), findsOneWidget);
    expect(find.textContaining('PLAYER'), findsNothing);
  });

  testWidgets('without a ticket the watch screen explains why', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    api.watchError = 403;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/watch/vod/a0000000-0000-0000-0000-000000000001?title=Highlights');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('watchError')), findsOneWidget);
    expect(find.text('Register for this event to watch.'), findsOneWidget);
  });

  testWidgets('paid tickets: "available soon" until a payment method is enabled', (tester) async {
    await pumpApp(tester, signedIn: true);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Paid tickets will be available soon.'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Paid tickets will be available soon.'), findsOneWidget);
    expect(find.byKey(const Key('getTickets')), findsNothing);
  });

  testWidgets('buy paid tickets: hold → choose wallet → pay → tickets ready', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'KBZPAY', label: 'KBZPay'), PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    expect(find.text('Paid tickets will be available soon.'), findsNothing);
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('10,000 MMK'), findsWidgets); // 2 × 5,000
    await tester.tap(find.byKey(const Key('sheetSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.registered, ['e2:tt-e2:2']);
    expect(find.text('Checkout'), findsWidgets);
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.textContaining('Tickets held for 9:'), findsOneWidget);

    await tester.tap(find.byKey(const Key('method-MOCK')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.paid, ['ord-1:MOCK']);
    expect(openedUrls, ['https://pay.example/ord-1']);
    expect(find.text('Waiting for your payment…'), findsOneWidget);

    // The wallet confirms; the next poll shows the tickets
    api.orders['ord-1'] = {...api.orders['ord-1']!, 'status': 'PAID', 'ticketIds': ['t1', 't2']};
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byKey(const Key('paid')), findsOneWidget);
    expect(find.text('Payment received. Your tickets are ready.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose timers
  });

  testWidgets('expired hold explains what happens; pending orders offer "Continue payment"', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.orders['ord-1'] = FakeApi.orderJson('ord-1', 'PENDING_PAYMENT');
      a.orders['ord-2'] = FakeApi.orderJson('ord-2', 'EXPIRED', expires: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
    });
    await tester.tap(find.text('My tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('Continue payment'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/checkout/ord-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('expired')), findsOneWidget);
    expect(api.paid, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign-in opened from a link returns to the page that asked for it', (tester) async {
    await pumpApp(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/login?from=%2Fevent%2Fe1');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '09790000001');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Yangon Food Fair e1'), findsWidgets);
  });

  testWidgets('bell shows unread count; inbox opens the linked page and marks read', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    expect(find.descendant(of: find.byKey(const Key('inboxBell')), matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inboxBell')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Event details changed'), findsOneWidget);
    expect(find.text('Gates open at 4'), findsOneWidget);
    await tester.tap(find.text('Event details changed'));
    await tester.pumpAndSettle();
    expect(api.readIds, [
      ['n1'],
    ]);
    expect(find.text('Yangon Food Fair e1'), findsWidgets); // event page
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(api.readIds.last, isEmpty);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('signed out: no bell', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('inboxBell')), findsNothing);
  });

  testWidgets('push: device registered after sign-in; tapping a notification opens its page; sign-out removes it', (tester) async {
    final push = FakePush();
    final (api, sp) = await pumpApp(tester, signedIn: true, push: push);
    await tester.pumpAndSettle();
    expect(api.devices, ['android:fcm-token-1']);
    expect(sp.getString('push_token'), 'fcm-token-1');
    push.links.add('/event/e1');
    await tester.pumpAndSettle();
    expect(find.text('Yangon Food Fair e1'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(api.devices, isEmpty);
    expect(sp.getString('push_token'), isNull);
  });
}
