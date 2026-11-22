import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/providers.dart';
import 'package:organizer_app/app/push.dart';
import 'package:organizer_app/l10n/app_localizations.dart';
import 'package:organizer_app/main.dart';
import 'package:organizer_app/screens/event_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _future = '2099-01-15T10:30:00.000Z';

Map<String, dynamic> _att(String id, String status, String? name, String? phone, {String? seat, String? guest, bool comp = false, String type = 'Standing'}) => {
      'id': id,
      'status': status,
      'createdAt': '2026-11-20T04:00:00.000Z',
      'seatLabel': seat,
      'seatLabelMy': null,
      'isComplimentary': comp,
      'guestName': guest,
      'holder': name == null ? null : {'displayName': name, 'phone': phone},
      'ticketType': {'name': type},
    };

/// 3 rows x 6 seats at 24-unit spacing; small enough that the whole map is already tappable (zoom >= 1.6) on a phone.
Map<String, dynamic> seatLayoutJson() => {
      'width': 200,
      'height': 140,
      'sections': [
        {
          'key': 'A',
          'name': 'Stalls',
          'kind': 'SEATED',
          'x': 30,
          'y': 30,
          'rows': [
            for (final r in ['1', '2', '3'])
              {
                'label': r,
                'seats': [for (var n = 1; n <= 6; n++) {'n': n}],
              },
          ],
        },
      ],
    };

Map<String, dynamic> _seat(String key, String status, {String? type = 't1', String? label}) => {'seatKey': key, 'status': status, 'ticketTypeId': type, 'holdLabel': label};

Map<String, dynamic> _guest(String id, String name, String seat, {String status = 'VALID', bool checkedIn = false}) => {
      'id': id,
      'guestName': name,
      'phone': '09•••567',
      'seatKey': seat,
      'seatLabel': 'Stalls · Row ${seat.split(':')[1]} · Seat ${seat.split(':')[2]}',
      'status': status,
      'checkedIn': checkedIn,
      'label': 'VIP',
    };

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

  /// When true the event is on now (inside the check-in window); otherwise it is in 2099.
  bool eventOpen = false;
  bool failCheckIn = false;
  bool crashCheckIn = false;
  String? refuseWith;
  /// Seat map: off for an event without one.
  bool hasMap = true;

  /// The next hold / release / issue flips this seat to SOLD and fails with [SeatsChanged].
  String? nextSeatsChanged;

  /// While set, the seating request waits for it (the Seats tab then shows up late).
  Completer<void>? seatingGate;

  /// The server rejects the phone number of the next issue with 400.
  bool rejectPhone = false;
  final seatRows = <Map<String, dynamic>>[
    _seat('A:1:1', 'AVAILABLE'),
    _seat('A:1:2', 'AVAILABLE'),
    _seat('A:1:3', 'AVAILABLE'),
    _seat('A:1:4', 'SOLD'),
    _seat('A:1:5', 'GUEST_HOLD', label: 'Sponsor'),
    _seat('A:1:6', 'GUEST_HOLD', label: 'Sponsor'),
    _seat('A:2:1', 'AVAILABLE'),
    _seat('A:2:2', 'AVAILABLE'),
    _seat('A:2:3', 'UNSOLD', type: null),
    _seat('A:2:4', 'GUEST_HOLD', label: 'Press'),
    _seat('A:2:5', 'GUEST_HOLD', type: null, label: 'Sponsor'),
    _seat('A:2:6', 'SOLD'),
    for (var n = 1; n <= 5; n++) _seat('A:3:$n', 'AVAILABLE'),
    _seat('A:3:6', 'SOLD'),
  ];
  final guestRows = <Map<String, dynamic>>[
    _guest('g1', 'Daw Mya', 'A:1:4'),
    _guest('g2', 'U Hla', 'A:3:6', checkedIn: true),
  ];
  final attendeesList = <Map<String, dynamic>>[
    _att('a1', 'VALID', 'Aung Min', '09 912 345 67', seat: 'Balcony · Row C · Seat 12'),
    _att('a2', 'VALID', 'Zaw Win', '09771111222'),
    _att('a3', 'CHECKED_IN', 'Hnin Si', '09881112222'),
    _att('a4', 'CHECKED_IN', 'Bo Bo', '09882223333'),
    _att('a5', 'VOID', 'Cherry', '09773334444'),
    _att('a6', 'VALID', null, null, guest: 'Daw Khin', comp: true, type: 'VIP deck'),
  ];

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
        OrgEvent.fromJson({
          'id': 'e1',
          'slug': 'inya',
          'title': 'Inya Lake Live $orgId',
          'titleMy': null,
          'status': 'PUBLISHED',
          'startsAt': eventOpen ? DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String() : _future,
          'endsAt': eventOpen ? DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String() : '2099-01-15T16:30:00.000Z',
          'venue': {'name': 'Inya Lawn'},
        }),
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
  Future<List<Attendee>> attendees(String orgId, String eventId) async => attendeesList.map(Attendee.fromJson).toList();

  final checkedInAt = DateTime.utc(2026, 11, 22, 10, 15);

  CrewTicket _crewTicket(Map<String, dynamic> row, {bool checkedIn = false}) => CrewTicket.fromJson({
        'id': row['id'],
        'code': 'CODE-${row['id']}',
        'status': row['status'],
        'holderName': (row['holder'] as Map?)?['displayName'] ?? row['guestName'] ?? '',
        'ticketType': {'name': 'Standing'},
        if (checkedIn) 'checkedIn': {'at': checkedInAt.toIso8601String(), 'gate': 'Gate A', 'by': 'Crew'},
      });

  @override
  Future<ScanOutcome> crewManualCheckin(String eventId, String ticketId, {String? gate, String? deviceId}) async {
    calls.add('checkin:$ticketId:$gate');
    if (failCheckIn) throw ApiException(null, 'No connection');
    if (crashCheckIn) throw StateError('boom');
    if (refuseWith != null) return ScanOutcome(result: refuseWith!);
    final i = attendeesList.indexWhere((a) => a['id'] == ticketId);
    final row = attendeesList[i];
    switch (row['status']) {
      case 'VALID':
        attendeesList[i] = {...row, 'status': 'CHECKED_IN'};
        return ScanOutcome(result: 'ACCEPTED', ticket: _crewTicket(attendeesList[i], checkedIn: true));
      case 'CHECKED_IN':
        return ScanOutcome(result: 'ALREADY_CHECKED_IN', ticket: _crewTicket(row, checkedIn: true));
      default:
        return ScanOutcome(result: row['status'] as String, ticket: _crewTicket(row));
    }
  }

  @override
  Future<CrewTicket> crewUndo(String eventId, String ticketId) async {
    calls.add('undo:$ticketId');
    final i = attendeesList.indexWhere((a) => a['id'] == ticketId);
    attendeesList[i] = {...attendeesList[i], 'status': 'VALID'};
    return _crewTicket(attendeesList[i]);
  }

  void _setSeat(String key, String status, {String? label}) {
    final i = seatRows.indexWhere((r) => r['seatKey'] == key);
    seatRows[i] = {...seatRows[i], 'status': status, 'holdLabel': label};
  }

  void _seatsConflict() {
    final key = nextSeatsChanged;
    if (key == null) return;
    nextSeatsChanged = null;
    _setSeat(key, 'SOLD');
    throw SeatsChanged('Some seats are no longer available', [key]);
  }

  @override
  Future<OrgSeating> orgSeating(String orgId, String eventId) async {
    await seatingGate?.future;
    int n(bool Function(Map<String, dynamic>) f) => seatRows.where(f).length;
    final comp = guestRows.where((g) => g['status'] == 'VALID').length;
    return OrgSeating.fromJson({
      'layout': hasMap ? seatLayoutJson() : null,
      'seats': hasMap ? seatRows : [],
      'colors': {'t1': '#2f6fed'},
      'counts': {
        't1': {
          'available': n((r) => r['status'] == 'AVAILABLE'),
          'held': 0,
          'offered': 0,
          'guest': n((r) => r['status'] == 'GUEST_HOLD'),
          'sold': n((r) => r['status'] == 'SOLD') - comp,
          'comp': comp,
        },
      },
    });
  }

  @override
  Future<List<GuestTicket>> guestTickets(String orgId, String eventId) async => guestRows.map(GuestTicket.fromJson).toList();

  @override
  Future<int> holdSeats(String orgId, String eventId, List<String> seats, String label) async {
    calls.add('hold:${seats.join(',')}:$label');
    _seatsConflict();
    for (final s in seats) {
      _setSeat(s, 'GUEST_HOLD', label: label);
    }
    return seats.length;
  }

  @override
  Future<int> releaseSeats(String orgId, String eventId, List<String> seats) async {
    calls.add('release:${seats.join(',')}');
    _seatsConflict();
    for (final s in seats) {
      _setSeat(s, 'AVAILABLE');
    }
    return seats.length;
  }

  @override
  Future<int> issueGuestTickets(String orgId, String eventId, List<String> seats, {required String guestName, required String phone, String? label}) async {
    calls.add('issue:${seats.join(',')}:$guestName:$phone:${label ?? ''}');
    _seatsConflict();
    if (rejectPhone) throw ApiException(400, 'Invalid phone number');
    for (final s in seats) {
      _setSeat(s, 'SOLD');
      guestRows.add({..._guest('g${guestRows.length + 1}', guestName, s), 'label': label});
    }
    return seats.length;
  }

  @override
  Future<void> revokeGuestTicket(String orgId, String eventId, String ticketId) async {
    calls.add('revokeGuest:$ticketId');
    final i = guestRows.indexWhere((g) => g['id'] == ticketId);
    if (guestRows[i]['checkedIn'] == true) throw ApiException(409, 'Already checked in');
    guestRows[i] = {...guestRows[i], 'status': 'VOID'};
    _setSeat(guestRows[i]['seatKey'] as String, 'GUEST_HOLD', label: 'Sponsor');
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

/// Taps a seat of the fixture map where it is drawn (the whole map is zoomed in enough to select).
Future<void> tapSeat(WidgetTester t, String key) async {
  final seat = SeatLayout.fromJson(seatLayoutJson()).seatByKey(key)!;
  final map = find.byKey(const Key('seatMap'));
  final tl = t.getTopLeft(map);
  final scale = (t.getBottomRight(map).dx - tl.dx) / 200;
  await t.tapAt(tl + seat.pos * scale);
  await t.pumpAndSettle();
}

Future<void> tapSeats(WidgetTester t, List<String> keys) async {
  for (final k in keys) {
    await tapSeat(t, k);
  }
}

/// Scrolls the Seats tab page by dragging its "Guest tickets" heading (a drag on the map would pan the map).
Future<void> scrollSeatsPage(WidgetTester t, [double dy = -400]) async {
  await t.drag(find.text(L10n.of(t.element(find.byType(Scaffold).first)).guestList), Offset(0, dy));
  await t.pumpAndSettle();
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

Future<FakeApi> pumpApp(WidgetTester tester, {bool signedIn = true, String role = 'ORG_OWNER', PushClient? push, String lang = 'en', Size size = const Size(1236, 2745), double dpr = 3, bool eventOpen = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'org_lang': lang});
  final sp = await SharedPreferences.getInstance();
  final store = MemoryTokenStore();
  if (signedIn) await store.save('a', 'r');
  final api = FakeApi(store)
    ..role = role
    ..eventOpen = eventOpen;
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
    await tester.ensureVisible(find.byKey(const Key('tabAnnounce')));
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
      for (final k in ['tabGuests', 'tabSeats', 'tabDoor', 'tabAnnounce', 'tabPromos']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $k');
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  // ───── Large-text sweep: every screen at 390x844, text scale 2.0, EN and MY ─────

  Future<void> scrollThrough(WidgetTester tester) async {
    final count = find.byType(Scrollable).evaluate().length;
    for (var i = 0; i < count; i++) {
      if (i >= find.byType(Scrollable).evaluate().length) break; // fields come and go while scrolling
      final f = find.byType(Scrollable).at(i);
      final horizontal = tester.state<ScrollableState>(f).axisDirection == AxisDirection.right;
      for (var k = 0; k < 10; k++) {
        await tester.drag(f, horizontal ? const Offset(-250, 0) : const Offset(0, -350), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The vertical scrollable of the open tab (not the tab pager, not a text field's own).
  Finder pageScroll() => find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;

  Future<void> openEvent(WidgetTester t) async {
    await t.tap(find.byKey(const Key('event-e1')));
    await t.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester t, String key) async {
    await openEvent(t);
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  Future<void> createCode(WidgetTester t) async {
    await openTab(t, 'tabDoor');
    await t.enterText(find.byKey(const Key('codeLabel')), 'Volunteers for the north side entrance');
    await t.enterText(find.byKey(const Key('codeGate')), 'Gate A');
    await t.scrollUntilVisible(find.byKey(const Key('createCode')), 200, scrollable: pageScroll());
    await t.tap(find.byKey(const Key('createCode')));
    await t.pumpAndSettle();
  }

  final sweepScreens = <String, ({bool signedIn, String role, Future<void> Function(WidgetTester)? then})>{
    'login': (signedIn: false, role: 'ORG_OWNER', then: null),
    'login, wrong password': (signedIn: false, role: 'ORG_OWNER', then: (t) async {
      await t.enterText(find.byKey(const Key('email')), 'owner@yl.test');
      await t.enterText(find.byKey(const Key('password')), 'nope');
      await t.tap(find.byKey(const Key('signIn')));
      await t.pumpAndSettle();
    }),
    'event list': (signedIn: true, role: 'ORG_OWNER', then: null),
    'organization picker': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await t.tap(find.byKey(const Key('orgPicker')));
      await t.pumpAndSettle();
    }),
    'event overview': (signedIn: true, role: 'ORG_OWNER', then: openEvent),
    'door tab': (signedIn: true, role: 'ORG_OWNER', then: (t) => openTab(t, 'tabDoor')),
    'door tab, view only': (signedIn: true, role: 'ORG_FINANCE', then: (t) => openTab(t, 'tabDoor')),
    'door tab, new code dialog': (signedIn: true, role: 'ORG_OWNER', then: createCode),
    'door tab, code list and revoke dialog': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await createCode(t);
      await t.tap(find.byType(FilledButton).last); // Done
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byType(OutlinedButton).last, 200, scrollable: pageScroll());
      await t.tap(find.byType(OutlinedButton).last, warnIfMissed: false);
      await t.pumpAndSettle();
    }),
    'guests tab, list': (signedIn: true, role: 'ORG_OWNER', then: (t) => openTab(t, 'tabGuests')),
    'guests tab, sheet with Check in': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabGuests');
      await t.tap(find.byKey(const Key('guestRow-a1')));
      await t.pumpAndSettle();
    }),
    'guests tab, sheet with Undo': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabGuests');
      await t.enterText(find.byKey(const Key('guestSearch')), 'hnin');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guestRow-a3')));
      await t.pumpAndSettle();
    }),
    'guests tab, search with no match': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabGuests');
      await t.enterText(find.byKey(const Key('guestSearch')), 'zzzz');
      await t.pumpAndSettle();
    }),
    'seats tab, map': (signedIn: true, role: 'ORG_OWNER', then: (t) => openTab(t, 'tabSeats')),
    'seats tab, view only': (signedIn: true, role: 'ORG_FINANCE', then: (t) => openTab(t, 'tabSeats')),
    'seats tab, guest list': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await scrollSeatsPage(t, -500);
    }),
    'seats tab, free seats selected': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:3:1', 'A:3:2']);
    }),
    'seats tab, held seats selected with Issue and Release': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:1:5', 'A:1:6']);
    }),
    'seats tab, held seat without ticket type': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:1:5', 'A:2:5']);
    }),
    'seats tab, mixed selection': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:3:1', 'A:1:5']);
    }),
    'seats tab, hold sheet': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:3:1', 'A:3:2']);
      await t.tap(find.byKey(const Key('seatsHold')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('holdSubmit'))); // label missing
      await t.pumpAndSettle();
    }),
    'seats tab, issue sheet with errors': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:1:5', 'A:1:6']);
      await t.tap(find.byKey(const Key('seatsIssue')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('guestPhone')), '123');
      await t.tap(find.byKey(const Key('issueSubmit')));
      await t.pumpAndSettle();
    }),
    'seats tab, issue confirm dialog': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:1:5', 'A:1:6']);
      await t.tap(find.byKey(const Key('seatsIssue')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('guestName')), 'Daw Aye Aye Khin');
      await t.enterText(find.byKey(const Key('guestPhone')), '09 123 456 789');
      await t.tap(find.byKey(const Key('issueSubmit')));
      await t.pumpAndSettle();
    }),
    'seats tab, release confirm dialog': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await tapSeats(t, ['A:1:5', 'A:1:6']);
      await t.tap(find.byKey(const Key('seatsRelease')));
      await t.pumpAndSettle();
    }),
    'seats tab, revoke confirm dialog': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabSeats');
      await scrollSeatsPage(t, -500);
      await t.tap(find.byKey(const Key('guestRevoke-g1')));
      await t.pumpAndSettle();
    }),
    'announce tab': (signedIn: true, role: 'ORG_OWNER', then: (t) => openTab(t, 'tabAnnounce')),
    'announce tab, confirm dialog': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabAnnounce');
      await t.enterText(find.byKey(const Key('annTitle')), 'Gates open at 4');
      await t.enterText(find.byKey(const Key('annBody')), 'Bring your QR code.');
      await t.scrollUntilVisible(find.byKey(const Key('sendAnnouncement')), 200, scrollable: pageScroll());
      await t.tap(find.byKey(const Key('sendAnnouncement')));
      await t.pumpAndSettle();
    }),
    'announce tab, after sending': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabAnnounce');
      await t.enterText(find.byKey(const Key('annTitle')), 'Gates open at 4');
      await t.enterText(find.byKey(const Key('annBody')), 'Bring your QR code.');
      await t.scrollUntilVisible(find.byKey(const Key('sendAnnouncement')), 200, scrollable: pageScroll());
      await t.tap(find.byKey(const Key('sendAnnouncement')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmSend')));
      await t.pumpAndSettle();
    }),
    'promos tab with a code and a duplicate error': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await openTab(t, 'tabPromos');
      for (var n = 0; n < 2; n++) {
        await t.enterText(find.byKey(const Key('promoCode')), 'EARLY20');
        await t.enterText(find.byKey(const Key('promoValue')), '20');
        await t.scrollUntilVisible(find.byKey(const Key('createPromo')), 200, scrollable: pageScroll());
        await t.tap(find.byKey(const Key('createPromo')));
        await t.pumpAndSettle();
      }
    }),
    'inbox': (signedIn: true, role: 'ORG_OWNER', then: (t) async {
      await t.tap(find.byKey(const Key('inboxBell')));
      await t.pumpAndSettle();
    }),
  };

  for (final lang in ['en', 'my']) {
    for (final entry in sweepScreens.entries) {
      testWidgets('large text: ${entry.key} has no overflow at 390x844, scale 2.0, $lang', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final errors = <String>[];
        void noErrors(String when) => expect(errors, isEmpty, reason: when);
        await pumpApp(tester, signedIn: entry.value.signedIn, role: entry.value.role, lang: lang, size: const Size(390 * 3, 844 * 3), eventOpen: true);
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toDiagnosticsNode().toStringDeep().split('\n').where((l) => l.contains('overflowed') || l.contains('file:///') && l.contains('/lib/')).take(6).join(' / '));
        try {
          await tester.pumpAndSettle();
          noErrors('opened');
          await entry.value.then?.call(tester);
          noErrors('after action');
          await scrollThrough(tester);
          noErrors('scrolled');
        } finally {
          FlutterError.onError = previous;
        }
        await tester.pumpWidget(const SizedBox()); // stop the refresh timer
      });
    }
  }
}
