import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/providers.dart';
import 'package:organizer_app/app/push.dart';
import 'package:organizer_app/main.dart';
import 'package:organizer_app/screens/event_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _future = '2099-01-15T10:30:00.000Z';

class FakeApi extends Event360Api {
  FakeApi(this.store) : super(const AppConfig(app: Event360App.organizer, apiBaseUrl: 'http://fake'), store);
  final MemoryTokenStore store;
  String role = 'ORG_OWNER';
  final calls = <String>[];
  final devices = <String>[];
  final codes = <Map<String, dynamic>>[];
  final promos = <Map<String, dynamic>>[];
  final sent = <Map<String, dynamic>>[];
  int unread = 2;

  @override
  Future<void> passwordLogin(String email, String password) async {
    if (password != 'secret-123') throw ApiException(401, 'Wrong email or password');
    await store.save('a', 'r');
  }

  @override
  Future<List<OrgMembership>> myOrganizations() async => [
        OrgMembership.fromJson({'id': 'o1', 'name': 'Yangon Live', 'slug': 'yl', 'role': role, 'kycStatus': 'APPROVED'}),
        OrgMembership.fromJson({'id': 'o2', 'name': 'Mandalay Arts', 'slug': 'ma', 'role': 'ORG_OWNER', 'kycStatus': 'APPROVED'}),
      ];

  @override
  Future<List<OrgEvent>> orgEvents(String orgId) async => [
        OrgEvent.fromJson({'id': 'e1', 'slug': 'inya', 'title': 'Inya Lake Live $orgId', 'titleMy': null, 'status': 'PUBLISHED', 'startsAt': _future, 'endsAt': '2099-01-15T16:30:00.000Z', 'venue': {'name': 'Inya Lawn'}}),
        OrgEvent.fromJson({'id': 'e0', 'slug': 'old', 'title': 'Last year', 'titleMy': null, 'status': 'COMPLETED', 'startsAt': '2020-01-15T10:30:00.000Z', 'endsAt': '2020-01-15T16:30:00.000Z'}),
      ];

  @override
  Future<EventDashboard> eventDashboard(String orgId, String eventId) async => EventDashboard.fromJson({
        'totals': {'views': 120, 'orders': 9, 'ticketsSold': 13, 'capacity': 300, 'revenueMmk': 138000, 'discountMmk': 57000, 'checkedIn': 9, 'conversion': 7.5},
        'ticketTypes': [
          {'name': 'Standing', 'sold': 4, 'quota': 200, 'priceMmk': 0},
          {'name': 'VIP deck', 'sold': 3, 'quota': 20, 'priceMmk': 35000, 'seats': {'available': 11, 'held': 2, 'guest': 3, 'sold': 3, 'comp': 1}},
        ],
        'checkinsByGate': [],
        'daily': [],
      });

  @override
  Future<CrewStats> eventAttendance(String orgId, String eventId) async => CrewStats.fromJson({
        'registered': 13,
        'checkedIn': 9,
        'byTicketType': [],
        'byGate': [
          {'gate': 'Gate A', 'checkedIn': 5},
          {'gate': null, 'checkedIn': 4},
        ],
        'recent': [],
      });

  @override
  Future<List<RecentOrder>> recentOrders(String orgId, String eventId) async => [
        RecentOrder.fromJson({'id': 'r1', 'status': 'PAID', 'createdAt': '2026-11-20T04:00:00.000Z', 'totalMmk': 30000, 'quantity': 2, 'buyer': '0979•••123'}),
      ];

  @override
  Future<List<CrewCode>> crewCodes(String orgId, String eventId) async => codes.map(CrewCode.fromJson).toList();

  @override
  Future<CrewCode> createCrewCode(String orgId, String eventId, String label, {String? gate}) async {
    final c = {'id': 'c${codes.length}', 'label': label, 'gate': gate, 'expiresAt': _future, 'devices': 0, 'active': true};
    codes.add(c);
    return CrewCode.fromJson({...c, 'code': 'K7QM-4XRT', 'redeemUri': 'event360crew://redeem?code=K7QM-4XRT'});
  }

  @override
  Future<void> revokeCrewCode(String orgId, String eventId, String codeId) async {
    calls.add('revoke:$codeId');
    final i = codes.indexWhere((c) => c['id'] == codeId);
    codes[i] = {...codes[i], 'active': false, 'revokedAt': '2026-11-20T04:00:00.000Z'};
  }

  @override
  Future<Announcements> announcements(String orgId, String eventId) async => Announcements.fromJson({
        'items': sent.map((s) => {...s, 'id': 'a${sent.indexOf(s)}', 'recipients': 13, 'createdAt': '2026-11-20T04:00:00.000Z'}).toList(),
        'ticketHolders': 13,
        'remainingToday': 3 - sent.length,
      });

  @override
  Future<void> sendAnnouncement(String orgId, String eventId, {required String title, required String body, String? titleMy, String? bodyMy}) async =>
      sent.add({'title': title, 'body': body, 'titleMy': titleMy, 'bodyMy': bodyMy});

  @override
  Future<List<PromoCodeInfo>> promoCodes(String orgId, String eventId) async => promos.map(PromoCodeInfo.fromJson).toList();

  @override
  Future<void> createPromoCode(String orgId, String eventId, {required String code, required String kind, required int value, int? maxUses}) async {
    if (promos.any((p) => p['code'] == code.toUpperCase())) throw ApiException(409, 'This code already exists for the event');
    promos.add({'id': 'p${promos.length}', 'code': code.toUpperCase(), 'kind': kind, 'value': value, 'maxUses': maxUses, 'used': 0, 'isActive': true, 'orders': 0, 'discountGivenMmk': 0});
  }

  @override
  Future<void> setPromoActive(String orgId, String eventId, String promoId, bool active) async {
    final i = promos.indexWhere((p) => p['id'] == promoId);
    promos[i] = {...promos[i], 'isActive': active};
  }

  @override
  Future<Inbox> organizerNotifications() async => Inbox.fromJson({
        'items': [
          {'id': 'n1', 'kind': 'org_sold_out', 'title': 'Sold out 🎉', 'titleMy': null, 'body': 'All 20 VIP tickets are gone.', 'bodyMy': null, 'link': '/event/e1', 'eventId': 'e1', 'readAt': unread > 0 ? null : '2026-11-20T04:00:00.000Z', 'createdAt': '2026-11-20T04:00:00.000Z'},
          {'id': 'n2', 'kind': 'org_daily', 'title': 'Today’s sales', 'titleMy': null, 'body': '9 orders · 13 tickets', 'bodyMy': null, 'link': '/', 'eventId': null, 'readAt': unread > 1 ? null : '2026-11-20T04:00:00.000Z', 'createdAt': '2026-11-20T03:00:00.000Z'},
        ],
        'unread': unread,
      });

  @override
  Future<void> markOrganizerNotificationsRead([List<String> ids = const []]) async => unread = ids.isEmpty ? 0 : unread - ids.length;

  @override
  Future<void> registerDevice(String pushToken, String platform, {String appId = 'user_app'}) async => devices.add('$appId:$pushToken');

  @override
  Future<void> removeDevice(String pushToken) async => devices.removeWhere((d) => d.endsWith(':$pushToken'));
}

class FakePush implements PushClient {
  @override
  bool get supported => true;
  @override
  Future<String?> token() async => 'fcm-org-1';
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<void> get onForeground => const Stream.empty();
  @override
  Stream<String> get onOpenLink => const Stream.empty();
  @override
  Future<String?> initialLink() async => null;
  @override
  Future<void> deleteToken() async {}
}

Future<FakeApi> pumpApp(WidgetTester tester, {bool signedIn = true, String role = 'ORG_OWNER', PushClient? push, String lang = 'en', Size size = const Size(1236, 2745), double dpr = 3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'org_lang': lang});
  final sp = await SharedPreferences.getInstance();
  final store = MemoryTokenStore();
  if (signedIn) await store.save('a', 'r');
  final api = FakeApi(store)..role = role;
  await tester.pumpWidget(ProviderScope(overrides: [
    prefsProvider.overrideWithValue(sp),
    apiProvider.overrideWithValue(api),
    pushProvider.overrideWithValue(push ?? const NoPush()),
  ], child: const OrganizerApp()));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  testWidgets('sign in with the portal account; wrong password explained', (tester) async {
    await pumpApp(tester, signedIn: false);
    expect(find.text('Sign in with your organizer account'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email')), 'owner@yl.test');
    await tester.enterText(find.byKey(const Key('password')), 'nope');
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong email or password'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('password')), 'secret-123');
    await tester.tap(find.byKey(const Key('signIn')));
    await tester.pumpAndSettle();
    expect(find.text('Inya Lake Live o1'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
  });

  testWidgets('switch organization; event overview shows sales, check-ins and recent orders', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('orgPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandalay Arts').last);
    await tester.pumpAndSettle();
    expect(find.text('Inya Lake Live o2'), findsOneWidget);
    await tester.tap(find.text('Inya Lake Live o2'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('sold'))).data, '13 / 300');
    expect(tester.widget<Text>(find.byKey(const Key('revenue'))).data, '138,000 MMK');
    expect(tester.widget<Text>(find.byKey(const Key('checkedIn'))).data, '9 / 13');
    expect(find.text('VIP deck'), findsOneWidget);
    expect(find.text('Gate A'), findsOneWidget);
    expect(find.text('No gate'), findsOneWidget);
    // Seat counts are tiles: label on top, the number below
    for (final (label, n) in [('Available', '11'), ('Held for guests', '3'), ('Complimentary', '1')]) {
      final tile = find.ancestor(of: find.text(label), matching: find.byType(StatTile));
      expect(tile, findsOneWidget, reason: label);
      expect(find.descendant(of: tile, matching: find.text(n)), findsOneWidget, reason: label);
    }
    await tester.scrollUntilVisible(find.text('2 × · 30,000 MMK'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('2 × · 30,000 MMK'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the refresh timer
  });

  testWidgets('door: create a crew code (QR shown once) and revoke it', (tester) async {
    final api = await pumpApp(tester);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tabDoor')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('codeLabel')), 'Volunteers');
    await tester.enterText(find.byKey(const Key('codeGate')), 'Gate A');
    await tester.tap(find.byKey(const Key('createCode')));
    await tester.pumpAndSettle();
    expect(find.text('Show this to your volunteers'), findsOneWidget);
    expect(find.text('K7QM-4XRT'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Volunteers · Gate A'), findsOneWidget);
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(api.calls, ['revoke:c0']);
    expect(find.text('Revoked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('announce to ticket holders after confirming', (tester) async {
    final api = await pumpApp(tester);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tabAnnounce')));
    await tester.pumpAndSettle();
    expect(find.text('13 ticket holders · 3 left today'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('annTitle')), 'Gates open at 4');
    await tester.enterText(find.byKey(const Key('annBody')), 'Bring your QR code.');
    await tester.tap(find.byKey(const Key('sendAnnouncement')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSend')));
    await tester.pumpAndSettle();
    expect(api.sent.single['title'], 'Gates open at 4');
    expect(find.text('13 ticket holders · 2 left today'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('promo codes: create, duplicate error, switch off', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tabPromos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tabPromos')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('promoCode')), 'early20');
    await tester.enterText(find.byKey(const Key('promoValue')), '20');
    await tester.tap(find.byKey(const Key('createPromo')));
    await tester.pumpAndSettle();
    expect(find.text('EARLY20 · 20%'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('promoCode')), 'EARLY20');
    await tester.enterText(find.byKey(const Key('promoValue')), '10');
    await tester.tap(find.byKey(const Key('createPromo')));
    await tester.pumpAndSettle();
    expect(find.text('This code already exists for the event'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.text('EARLY20 · 20% · Off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finance role: view only', (tester) async {
    await pumpApp(tester, role: 'ORG_FINANCE');
    await tester.tap(find.text('Inya Lake Live o1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tabDoor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createCode')), findsNothing);
    expect(find.text("View only: your role can't change this."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recent order badge shows a localized status, never the raw API value', (tester) async {
    for (final (lang, label) in [('en', 'Paid'), ('my', 'ငွေပေးချေပြီး')]) {
      await pumpApp(tester, lang: lang);
      await tester.tap(find.byKey(const Key('orgPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mandalay Arts').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inya Lake Live o2'));
      await tester.pumpAndSettle();
      final badge = find.byWidgetPredicate((w) => w is E360Badge && w.label == label, skipOffstage: false);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget, reason: lang);
      expect(find.byWidgetPredicate((w) => w is E360Badge && w.label == 'PAID', skipOffstage: false), findsNothing, reason: lang);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('inbox: unread badge, open the linked event, push registered as organizer app', (tester) async {
    final api = await pumpApp(tester, push: FakePush());
    expect(api.devices, ['organizer_app:fcm-org-1']);
    expect(find.descendant(of: find.byKey(const Key('inboxBell')), matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inboxBell')));
    await tester.pumpAndSettle();
    expect(find.text('Sold out 🎉'), findsOneWidget);
    await tester.tap(find.text('Sold out 🎉'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tabOverview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event list and overview have no overflow at 360 dp in EN and MY (tiles, seat counts, long amounts)', (tester) async {
    for (final lang in ['en', 'my']) {
      await pumpApp(tester, lang: lang, size: const Size(360, 780), dpr: 1);
      expect(find.byKey(const Key('event-e1')), findsOneWidget, reason: '$lang list');
      expect(tester.takeException(), isNull, reason: '$lang list');
      await tester.tap(find.byKey(const Key('event-e1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sold')), findsOneWidget, reason: '$lang overview');
      expect(find.byType(StatTile), findsNWidgets(9), reason: '$lang tiles: 4 totals + 5 seat counts');
      expect(tester.takeException(), isNull, reason: '$lang overview');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$lang overview scrolled');
      // Every other tab too
      for (final k in ['tabDoor', 'tabAnnounce', 'tabPromos']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $k');
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
