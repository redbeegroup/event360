import 'dart:async';
import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_app/app/format.dart';
import 'package:user_app/app/providers.dart';
import 'package:user_app/app/push.dart';
import 'package:user_app/l10n/app_localizations.dart';
import 'package:user_app/widgets/event_row.dart';
import 'package:user_app/main.dart';
import 'package:user_app/screens/checkout_screen.dart';
import 'package:user_app/screens/ticket_screen.dart';
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

  // ───── Reserved seating ─────
  static final seatedLayout = {
    'width': 300,
    'height': 220,
    'stage': {'x': 60, 'y': 5, 'w': 180, 'h': 30, 'label': 'Stage'},
    'sections': [
      {
        'key': 'A',
        'name': 'Stalls',
        'nameMy': 'ရှေ့ခန်း',
        'kind': 'SEATED',
        'x': 40,
        'y': 80,
        'rows': [
          for (final r in ['1', '2'])
            {
              'label': r,
              'seats': [for (var n = 1; n <= 5; n++) {'n': n}],
            },
        ],
      },
    ],
  };
  String seatStatus = 'AAAAAAAAAA'; // 2 rows x 5 seats of the Stalls type
  int seatLoads = 0;
  final bestCalls = <String>[];
  final seatOrders = <List<String>>[];
  final seatOrderKeys = <String>[];
  final seatPromoCodes = <String?>[];
  final promoSeatChecks = <List<String>>[];
  int? promoError; // checkPromo throws this status
  Completer<void>? promoGate; // checkPromo waits for this
  List<String>? takenOnNextOrder; // the next seated order fails with 409 naming these seats
  ApiException? nextOrderError; // the next order (seated or not) fails with this
  int stallsPrice = 20000; // the seat map's Stalls price (a poll can change it)
  String? seatTypesNow; // overrides the seat map's per-seat types (a poll can change them)
  Completer<void>? eventGate; // event() waits for this
  final cancelled = <String>[];
  List<Map<String, dynamic>> extraTickets = [];

  static Map<String, dynamic> seatedEventJson() => {
        ...eventJson('seated', free: false),
        'seating': {'seatMapVersionId': 'v1', 'venueName': 'National Theatre'},
        'ticketTypes': [
          {'id': 'tt-seat', 'name': 'Stalls', 'nameMy': 'ရှေ့ခန်း', 'priceMmk': 20000, 'quota': 10, 'remaining': 10, 'maxPerOrder': 3, 'seated': true, 'color': '#f2b632'},
        ],
      };

  /// Standing types only: one nearly gone, one plain, one sold out (a waitlist offer can sit on it).
  static Map<String, dynamic> mixedEventJson() => {
        ...eventJson('mixed', free: false),
        'description': 'Welcome the new year with a night of live music, street food and fireworks over the lake. Doors open at 6 PM, the show starts at 7:30 PM and the countdown is at midnight. Bring friends: groups of four or more save ten percent. Standing tickets are first come first served and the VIP deck has its own bar.',
        'ticketTypes': [
          {'id': 'tt-mix-a', 'name': 'Standing', 'nameMy': 'ရပ်ကြည့်', 'priceMmk': 5000, 'quota': 100, 'remaining': 8, 'maxPerOrder': 4, 'color': '#2563eb'},
          {'id': 'tt-mix-b', 'name': 'VIP deck', 'nameMy': null, 'priceMmk': 35000, 'quota': 100, 'remaining': 60, 'maxPerOrder': 2, 'color': '#c2410c'},
          {'id': 'tt-mix-c', 'name': 'Early bird', 'nameMy': null, 'priceMmk': 10000, 'quota': 50, 'remaining': 0, 'maxPerOrder': 2, 'color': '#16a34a'},
        ],
      };

  /// Seats on the map and standing tickets by quantity, both on sale.
  static Map<String, dynamic> bothEventJson() => {
        ...seatedEventJson(),
        'id': 'both',
        'ticketTypes': [
          {'id': 'tt-seat', 'name': 'Stalls', 'nameMy': 'ရှေ့ခန်း', 'priceMmk': 20000, 'quota': 10, 'remaining': 10, 'maxPerOrder': 3, 'seated': true, 'color': '#f2b632'},
          {'id': 'tt-stand', 'name': 'Standing', 'nameMy': null, 'priceMmk': 8000, 'quota': 50, 'remaining': 40, 'maxPerOrder': 4},
        ],
      };

  static Map<String, dynamic> twoTypeEventJson() => {
        ...seatedEventJson(),
        'id': 'seated2',
        'ticketTypes': [
          {'id': 'tt-seat', 'name': 'Stalls', 'nameMy': 'ရှေ့ခန်း', 'priceMmk': 20000, 'quota': 5, 'remaining': 5, 'maxPerOrder': 3, 'seated': true, 'color': '#f2b632'},
          {'id': 'tt-circle', 'name': 'Circle', 'nameMy': null, 'priceMmk': 30000, 'quota': 5, 'remaining': 5, 'maxPerOrder': 2, 'seated': true, 'color': '#3b6fd8'},
        ],
      };

  @override
  Future<SeatMapData> seatMap(String eventId) async {
    seatLoads++;
    final two = eventId == 'seated2';
    return SeatMapData.fromJson({
      'versionId': 'v1',
      'layout': seatedLayout,
      'types': [
        {'id': 'tt-seat', 'name': 'Stalls', 'nameMy': 'ရှေ့ခန်း', 'priceMmk': stallsPrice, 'color': '#f2b632'},
        if (two) {'id': 'tt-circle', 'name': 'Circle', 'nameMy': null, 'priceMmk': 30000, 'color': '#3b6fd8'},
      ],
      'seatTypes': seatTypesNow ?? (two ? '0000011111' : '0' * 10),
      'status': seatStatus,
    });
  }

  // ───── Waitlist ─────
  List<Map<String, dynamic>> waitlist = []; // /me/waitlist rows
  int waitlistLoads = 0;
  final waitlistJoins = <String>[];
  final waitlistLeaves = <String>[];
  final offerOrders = <String>[]; // 'event:type:qty:entry' for orders made from an offer
  final offerSeatOrders = <String>[]; // 'entry:seat,seat' for seated orders made from an offer
  final offerBest = <String?>[];
  ApiException? joinError;
  ApiException? leaveError;

  /// A /me/waitlist row. An offer carries its expiry, quantity and (seated types) seat keys.
  static Map<String, dynamic> waitlistRow(String id,
          {String status = 'WAITING', String event = 'soldout', String type = 'tt-soldout', int? position, int offeredQty = 0, Duration? left, List<String> seatKeys = const [], String? orderId, Duration? serverAhead}) =>
      {
        'id': id,
        if (serverAhead != null) 'serverNow': DateTime.now().toUtc().add(serverAhead).toIso8601String(),
        'ticketTypeId': type,
        'eventId': event,
        'status': status,
        'quantity': 2,
        'position': position,
        'offeredQty': offeredQty,
        'offerExpiresAt': left == null ? null : DateTime.now().toUtc().add(left).toIso8601String(),
        'seatKeys': seatKeys,
        'orderId': orderId,
        'event': {'id': event, 'slug': 'slug-$event', 'title': 'Yangon Food Fair $event', 'titleMy': null},
        'ticketType': {'id': type, 'name': 'General', 'nameMy': 'အထွေထွေ'},
      };

  @override
  Future<List<WaitlistEntry>> myWaitlist() async {
    waitlistLoads++;
    return waitlist.map(WaitlistEntry.fromJson).toList();
  }

  @override
  Future<WaitlistJoin> joinWaitlist(String ticketTypeId, int quantity) async {
    final err = joinError;
    if (err != null) throw err;
    waitlistJoins.add('$ticketTypeId:$quantity');
    waitlist = [...waitlist, waitlistRow('w-new', position: 3)];
    return WaitlistJoin(entryId: 'w-new', position: 3);
  }

  @override
  Future<void> leaveWaitlist(String ticketTypeId) async {
    final err = leaveError;
    if (err != null) throw err;
    waitlistLeaves.add(ticketTypeId);
    waitlist = [for (final w in waitlist) if (w['ticketTypeId'] != ticketTypeId) w];
  }

  @override
  Future<List<String>> bestSeats(String eventId, String ticketTypeId, int quantity, {String? waitlistEntryId}) async {
    offerBest.add(waitlistEntryId);
    bestCalls.add('$ticketTypeId:$quantity');
    return [for (var n = 1; n <= quantity; n++) 'A:2:$n'];
  }

  @override
  Future<void> cancelTicket(String ticketId) async => cancelled.add(ticketId);

  @override
  Future<Order> createOrder(String eventId, Map<String, int> quantities,
      {required String idempotencyKey, String channel = 'APP', String? promoCode, List<String> seats = const [], String? waitlistEntryId}) async {
    final err = nextOrderError;
    if (err != null) {
      nextOrderError = null;
      throw err;
    }
    if (seats.isNotEmpty) {
      final taken = takenOnNextOrder;
      if (taken != null) {
        takenOnNextOrder = null;
        seatStatus = [for (var i = 0; i < 10; i++) taken.contains('A:${i < 5 ? 1 : 2}:${i % 5 + 1}') ? 'T' : seatStatus[i]].join();
        throw ApiException(409, 'Some seats were just taken', takenSeats: taken);
      }
      seatOrders.add(seats);
      if (waitlistEntryId != null) offerSeatOrders.add('$waitlistEntryId:${seats.join(',')}');
      seatOrderKeys.add(idempotencyKey);
      seatPromoCodes.add(promoCode);
      final o = orderJson('ord-1', 'PENDING_PAYMENT', total: 20000 * seats.length, qty: seats.length);
      orders['ord-1'] = o;
      return Order.fromJson(o);
    }
    final e = quantities.entries.first;
    if (waitlistEntryId != null) offerOrders.add('$eventId:${e.key}:${e.value}:$waitlistEntryId');
    registered.add('$eventId:${e.key}:${e.value}${promoCode != null ? ':$promoCode' : ''}');
    if (eventId == 'e1') return Order.fromJson({...orderJson('free-1', 'CONFIRMED', total: 0, qty: e.value), 'ticketIds': ['t1']});
    final o = orderJson('ord-1', 'PENDING_PAYMENT', total: 5000 * e.value, qty: e.value);
    orders['ord-1'] = o;
    return Order.fromJson(o);
  }

  @override
  Future<Order> order(String id) async => Order.fromJson(orders[id]!);

  @override
  Future<PromoCheck> checkPromo(String eventId, String code, Map<String, int> quantities, {List<String> seats = const []}) async {
    if (seats.isNotEmpty) {
      promoSeatChecks.add(seats);
      if (promoGate != null) await promoGate!.future;
      if (promoError != null) throw ApiException(promoError, 'Too many attempts, try again in a minute');
      final sub = 20000 * seats.length;
      return code.toUpperCase() == 'SAVE20'
          ? PromoCheck(valid: true, discountMmk: sub ~/ 5, totalMmk: sub - sub ~/ 5)
          : code.toUpperCase() == 'USEDUP'
              ? PromoCheck(valid: false, reason: 'This code has been used up', reasonCode: 'USED_UP', discountMmk: 0, totalMmk: sub)
              : PromoCheck(valid: false, reason: 'This code has expired', reasonCode: 'EXPIRED', discountMmk: 0, totalMmk: sub);
    }
    final sub = 5000 * quantities.values.first;
    if (code.toUpperCase() == 'SAVE20' && groupTiers.isNotEmpty) {
      // Like the API: the larger of the group discount and the code wins; a tie goes to the group discount
      final tiers = [for (final g in groupTiers) GroupTier.fromJson(g)];
      final group = groupDiscountMmk(tiers, quantities.values.first, sub);
      final promo = sub ~/ 5;
      return group > 0 && group >= promo
          ? PromoCheck(valid: true, discountMmk: group, totalMmk: sub - group, discountSource: 'GROUP', promoApplied: false)
          : PromoCheck(valid: true, discountMmk: promo, totalMmk: sub - promo, discountSource: 'PROMO', promoApplied: true);
    }
    return code.toUpperCase() == 'SAVE20'
        ? PromoCheck(valid: true, discountMmk: sub ~/ 5, totalMmk: sub - sub ~/ 5)
        : PromoCheck(valid: false, reason: 'This code is not valid', discountMmk: 0, totalMmk: sub);
  }

  final transfers = <String>[];
  @override
  Future<String> transferTicket(String ticketId, String phone) async {
    if (phone == '0911') throw ApiException(400, 'Enter a valid Myanmar mobile number');
    transfers.add('$ticketId:$phone');
    transferred = true;
    return '+95979•••001';
  }
  bool transferred = false;

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

  /// When set, the unfiltered event list (Discover's "upcoming") returns these.
  List<Map<String, dynamic>>? homeEvents;
  final eventQueries = <String>[]; // 'category:city' of each filtered list call

  @override
  Future<EventPage> events({String? q, String? category, String? city, bool? free, DateTime? from, DateTime? to, int page = 1, int limit = 20}) async {
    if (category != null || city != null) eventQueries.add('$category:$city');
    final items = (free == null && category == null && city == null ? homeEvents : null) ?? [eventJson('e1'), eventJson('e2', free: false)];
    return EventPage.fromJson({'items': items, 'page': 1, 'limit': 20, 'total': items.length});
  }

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
  Future<EventSummary> event(String idOrSlug) async {
    if (eventGate != null) await eventGate!.future;
    return _event(idOrSlug);
  }

  /// Group discount tiers every event reports, and a scheduled next price for paid ticket types ({priceMmk, startsAt}).
  List<Map<String, dynamic>> groupTiers = [];
  Map<String, dynamic>? nextPriceJson;

  /// The current price of every paid ticket type (a price step took effect), when set.
  int? paidPriceMmk;

  EventSummary _event(String idOrSlug) {
    final j = idOrSlug == 'soldout'
        ? {
            ...eventJson('soldout', free: false),
            'ticketTypes': [
              {'id': 'tt-soldout', 'name': 'General', 'nameMy': 'အထွေထွေ', 'priceMmk': 5000, 'quota': 100, 'remaining': 0, 'maxPerOrder': 4},
            ],
          }
        : idOrSlug == 'mixed' ? mixedEventJson() : idOrSlug == 'both' ? bothEventJson() : idOrSlug == 'seated2' ? twoTypeEventJson() : idOrSlug == 'seated' ? seatedEventJson() : (idOrSlug == 'rich' ? richEventJson(idOrSlug) : eventJson(idOrSlug, free: idOrSlug != 'e2'));
    return EventSummary.fromJson({
      ...j,
      'groupDiscounts': groupTiers,
      if (nextPriceJson != null || paidPriceMmk != null)
        'ticketTypes': [
          for (final t in j['ticketTypes'] as List)
            (t as Map<String, dynamic>)['priceMmk'] == 0
                ? t
                : {...t, if (nextPriceJson != null) 'nextPrice': nextPriceJson, if (paidPriceMmk != null) 'priceMmk': paidPriceMmk},
        ],
    });
  }

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
        'canTransfer': true,
      }),
      ...extraTickets.map(MyTicket.fromApi),
    ].where((t) => !transferred).toList();
  }
}

/// A typical Android phone screen (412×915 logical pixels).
void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 2745);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Phone widths (dp) the Myanmar discounted totals must fit: the test font draws every Myanmar code point as a
/// full square, so these are harsher than a device.
final phoneWidths = ValueVariant<double>({360, 412});

/// Narrows the screen to the current [phoneWidths] value (pumpApp starts at 412 dp).
Future<void> phoneWidth(WidgetTester tester) async {
  tester.view.physicalSize = Size(phoneWidths.currentValue! * 3, 2745);
  await tester.pump();
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

late FakeApi pickerApi;

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
    expect(find.text('Popular'), findsOneWidget);
  });

  testWidgets('home lists events with free / price labels (English)', (tester) async {
    await pumpApp(tester);
    expect(find.text('Yangon Food Fair e1'), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('From 5,000 MMK'), findsWidgets);
  });

  testWidgets('tabs read Discover, Explore, Tickets, Account', (tester) async {
    await pumpApp(tester);
    for (final l in ['Discover', 'Explore', 'Tickets', 'Account']) {
      expect(find.text(l), findsOneWidget);
    }
    await tester.tap(find.text('Explore'));
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsWidgets);
  });

  testWidgets('tabs read the same four names in Myanmar', (tester) async {
    await pumpApp(tester, lang: 'my');
    for (final l in ['စူးစမ်းရန်', 'ရှာဖွေ', 'လက်မှတ်များ', 'အကောင့်']) {
      expect(find.text(l), findsOneWidget);
    }
  });

  Future<void> tallScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1236, 9000);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> withCover(String id, String startsAt, {bool seated = false}) => {
        ...FakeApi.eventJson(id),
        'coverImageUrl': 'http://fake/$id.jpg',
        'startsAt': startsAt,
        if (seated) 'seating': {'seatMapVersionId': 'v1', 'venueName': 'National Theatre'},
      };

  testWidgets('discover shows search pill, category chips, a featured event and popular rows', (tester) async {
    await pumpApp(tester, setup: (api) {
      api.homeEvents = [
        FakeApi.eventJson('plain'),
        withCover('later', '2027-03-01T10:00:00.000Z'),
        withCover('soon', '2027-02-01T10:00:00.000Z', seated: true),
      ];
    });
    await tallScreen(tester);
    expect(find.text('Find things to do'), findsOneWidget);
    expect(find.text('in Myanmar'), findsOneWidget);
    expect(find.byKey(const Key('discoverFilters')), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Lifestyle & Social'), findsOneWidget);
    expect(find.byType(FeaturedEventCard), findsWidgets);
    // the featured card is the soonest event with a cover
    final featured = tester.widgetList<FeaturedEventCard>(find.byType(FeaturedEventCard)).map((w) => w.event.id);
    expect(featured, contains('soon'));
    expect(find.text('RESERVED SEATING'), findsOneWidget);
    expect(find.text('Popular'), findsOneWidget);
    expect(find.byType(EventRow), findsWidgets);
  });

  testWidgets('featured event is not repeated in popular', (tester) async {
    await pumpApp(tester, setup: (api) {
      api.homeEvents = [FakeApi.eventJson('plain'), withCover('soon', '2027-02-01T10:00:00.000Z'), withCover('later', '2027-03-01T10:00:00.000Z')];
    });
    await tallScreen(tester);
    final rows = tester.widgetList<EventRow>(find.byType(EventRow)).map((w) => w.event.id).toList();
    expect(rows, isNot(contains('soon')));
    expect(rows, containsAll(['plain', 'later']));
  });

  testWidgets('tapping a category chip opens Explore filtered to it', (tester) async {
    final (api, _) = await pumpApp(tester);
    await tester.tap(find.text('Lifestyle & Social'));
    await tester.pumpAndSettle();
    expect(api.eventQueries, contains('lifestyle-social:null'));
    // the Explore chip for that category is the selected one
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lifestyle & Social'));
    expect(chip.selected, isTrue);
  });

  testWidgets('the city picked in Explore shows on the Discover search pill', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('discoverSearch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('City'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandalay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.text('in Mandalay'), findsOneWidget);
  });

  testWidgets('event row lays out with no cover image, a very long title and no venue at 360 dp in EN and MY', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final long = 'A very long event title that keeps going and going so that it has to wrap and then be cut off ' * 3;
    final longMy = 'ရန်ကုန်မြို့ကြီး၏ အလွန်ရှည်လျားသော ပွဲတော်ခေါင်းစဉ်တစ်ခုသည် ဆက်လက်ရှည်လျားနေပါသဖြင့် ' * 3;
    for (final lang in ['en', 'my']) {
      final json = {...FakeApi.eventJson('x', free: false), 'title': long, 'titleMy': longMy, 'venue': null, 'coverImageUrl': null};
      final e = EventSummary.fromJson(json);
      await tester.pumpWidget(ProviderScope(
        overrides: [langProvider.overrideWithValue(lang)],
        child: MaterialApp(
          theme: Event360Theme.light(locale: Locale(lang)),
          locale: Locale(lang),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [L10n.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: Scaffold(body: ListView(padding: const EdgeInsets.all(20), children: [EventRow(event: e), FeaturedEventCard(event: e)])),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: lang);
      expect(find.byType(EventRow), findsOneWidget);
    }
  });

  testWidgets('search pill grows with large text in Myanmar at 360 dp without overflow', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: Event360Theme.light(locale: const Locale('my')),
        locale: const Locale('my'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [L10n.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)), child: w!),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: DiscoverSearchPill(city: 'ရန်ကုန်မြို့ကြီး', onTap: () {}, onFilters: () {}))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DiscoverSearchPill)).height, greaterThanOrEqualTo(56));
  });

  testWidgets('Myanmar UI shows Myanmar titles', (tester) async {
    await pumpApp(tester, lang: 'my');
    expect(find.text('ရန်ကုန် စားသောက်ပွဲ e1'), findsWidgets);
    expect(find.text('ရေပန်းစား'), findsOneWidget);
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
    await tester.tap(find.text('Tickets'));
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
    await tester.tap(find.byKey(const Key('organizerLink')));
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
    await tester.ensureVisible(find.text('Keynote'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300)); // out from under the pinned top bar
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Tickets'));
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
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(api.devices, isEmpty);
    expect(sp.getString('push_token'), isNull);
  });

  testWidgets('promo code on the ticket sheet: wrong code explained, right code lowers the total and is sent', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sheetAddPromo'))); // the field opens from "Add promo code"
    await tester.pump();
    await tester.enterText(find.byKey(const Key('promoField')), 'nope');
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    expect(find.text('This code is not valid'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('promoField')), 'save20');
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    expect(find.text('Code applied: 2,000 MMK off'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '8,000 MMK');
    expect(tester.getRect(find.byKey(const Key('sheetTotal'))).width, closeTo(tester.getSize(find.byKey(const Key('sheetTotal'))).width, 0.5)); // not shrunk
    // Changing the quantity drops the applied code (must be re-checked)
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.textContaining('Code applied'), findsNothing);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheetSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.registered, ['e2:tt-e2:2:save20']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('price rise hint shows next price and date', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.nextPriceJson = {'priceMmk': 7000, 'startsAt': '2027-01-10T08:00:00.000Z'}; // 14:30 in Yangon
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('priceRise-tt-e2')), 300, scrollable: find.byType(Scrollable).first);
    final rise = tester.widget<Text>(find.byKey(const Key('priceRise-tt-e2'))).data!;
    expect(rise, startsWith('Price rises to 7,000 MMK on Sun, 10 Jan 2027 · 2:30')); // Yangon time (UTC+6:30), then AM/PM
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheetRise-tt-e2')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('price rise hint is in Myanmar and absent for free tickets', (tester) async {
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) => a.nextPriceJson = {'priceMmk': 7000, 'startsAt': '2027-01-10T08:00:00.000Z'});
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('priceRise-tt-e2')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('တွင် ဈေးနှုန်း'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e1'); // free
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('priceRise-tt-e1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('group discount line appears at the threshold and the hint below it', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.groupTiers = [
        {'minQuantity': 2, 'percentBp': 1000},
        {'minQuantity': 4, 'percentBp': 2000},
      ];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    // 1 ticket: below the first tier
    expect(find.text('Buy 2+ tickets to save 10%'), findsOneWidget);
    expect(find.byKey(const Key('groupDiscountLine')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '5,000 MMK');
    // 2 tickets: first tier reached; the hint now points at the next one
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('Group discount −1,000 MMK'), findsOneWidget);
    expect(find.text('Buy 4+ tickets to save 20%'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '9,000 MMK');
    // 4 tickets: the top tier, nothing left to hint
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('Group discount −4,000 MMK'), findsOneWidget);
    expect(find.byKey(const Key('groupDiscountHint')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '16,000 MMK');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('group discount rounds half up like the API', (tester) async {
    expect(groupDiscountMmk(const [GroupTier(minQuantity: 2, percentBp: 750)], 2, 10100), 758); // 757.5 → 758
    expect(groupDiscountMmk(const [GroupTier(minQuantity: 2, percentBp: 750)], 1, 10100), 0);
    expect(groupDiscountMmk(const [GroupTier(minQuantity: 2, percentBp: 1000), GroupTier(minQuantity: 5, percentBp: 500)], 6, 6000), 600); // best tier, not the highest count
  });

  testWidgets('group discount and promo: only the larger shows, labelled', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.groupTiers = [
        {'minQuantity': 2, 'percentBp': 1500},
        {'minQuantity': 3, 'percentBp': 3000},
      ];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    // 2 tickets: the code (20% = 2,000) beats the group discount (15% = 1,500)
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('Group discount −1,500 MMK'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheetAddPromo'))); // the field opens from "Add promo code"
    await tester.pump();
    await tester.enterText(find.byKey(const Key('promoField')), 'save20');
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    expect(find.text('Code applied: 2,000 MMK off'), findsOneWidget);
    expect(find.byKey(const Key('groupDiscountLine')), findsNothing);
    expect(find.byKey(const Key('promoLostNote')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '8,000 MMK');
    // 3 tickets: the group discount (30% = 4,500) beats the code (3,000): the code is not applied, and the sheet says so
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Code applied'), findsNothing);
    expect(find.text('Group discount −4,500 MMK'), findsOneWidget);
    expect(find.text("Your code isn't applied — the group discount is bigger"), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '10,500 MMK');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('send a ticket to someone: bad number shown, then the ticket leaves my list', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    await tester.tap(find.text('Tickets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yangon Food Fair e1').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('transfer')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('transfer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('transferPhone')), '0911');
    await tester.tap(find.byKey(const Key('transferConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid Myanmar mobile number'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('transferPhone')), '09790000001');
    await tester.tap(find.byKey(const Key('transferConfirm')));
    await tester.pumpAndSettle();
    expect(api.transfers, ['ticket-0001-abcd:09790000001']);
    expect(find.text('Ticket sent to +95979•••001'), findsOneWidget);
    expect(find.text('Yangon Food Fair e1'), findsNothing);
  });

  // ───── Reserved seating ─────

  /// Where a layout point is on screen right now (the map sits inside a zoomable viewer).
  Offset onScreen(WidgetTester tester, Offset layoutPoint) {
    final rect = tester.getRect(find.byKey(const Key('seatMap')));
    final k = rect.width / 300; // layout width
    return rect.topLeft + layoutPoint * k;
  }

  Future<void> openPicker(WidgetTester tester, {void Function(FakeApi)? setup, String lang = 'en', String event = 'seated'}) async {
    final (api, _) = await pumpApp(tester, signedIn: true, lang: lang, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      setup?.call(a);
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/$event');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseSeats')));
    await tester.pumpAndSettle();
    pickerApi = api;
  }

  Future<void> zoomIntoStalls(WidgetTester tester) async {
    expect(find.byKey(const Key('zoomHint')), findsOneWidget);
    await tester.tapAt(onScreen(tester, const Offset(88, 92))); // below the tap zoom: tapping a section zooms in
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zoomHint')), findsNothing);
  }

  Future<void> tapSeat(WidgetTester tester, int row, int n) async {
    await tester.tapAt(onScreen(tester, Offset(40.0 + (n - 1) * 24, 80.0 + (row - 1) * 24)));
    await tester.pump();
  }

  testWidgets('seat picker renders and selects up to maxPerOrder', (tester) async {
    await openPicker(tester);
    expect(find.text('Stalls · 20,000 MMK'), findsOneWidget); // legend
    expect(find.text('Tap a seat to select it'), findsOneWidget);
    await tapSeat(tester, 1, 1); // zoomed out: a tap on seats does nothing
    expect(find.text('Tap a seat to select it'), findsOneWidget);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 2);
    await tapSeat(tester, 1, 3);
    expect(find.byKey(const Key('chip-A:1:1')), findsOneWidget);
    expect(find.byKey(const Key('chip-A:1:3')), findsOneWidget);
    expect(find.text('3 seats · Total'), findsOneWidget);
    expect(find.byKey(const Key('seatTotal')), findsOneWidget);
    expect(find.text('60,000 MMK'), findsOneWidget);
    await tapSeat(tester, 2, 1); // the type allows 3 per order
    expect(find.text('You can choose up to 3 seats'), findsOneWidget);
    expect(find.byKey(const Key('chip-A:2:1')), findsNothing);
    await tapSeat(tester, 1, 2); // tapping a selected seat unselects it
    expect(find.byKey(const Key('chip-A:1:2')), findsNothing);
    expect(find.text('40,000 MMK'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with two ticket types the lower maxPerOrder caps the whole selection', (tester) async {
    await openPicker(tester, event: 'seated2'); // Stalls (row 1) allows 3, Circle (row 2) allows 2
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 2);
    await tapSeat(tester, 1, 3); // three Stalls seats are fine on their own
    expect(find.byKey(const Key('chip-A:1:3')), findsOneWidget);
    await tapSeat(tester, 1, 3); // back to two
    await tapSeat(tester, 2, 1); // adding a Circle seat makes the Circle limit (2) apply to the total
    expect(find.text('You can choose up to 2 seats'), findsOneWidget);
    expect(find.byKey(const Key('chip-A:2:1')), findsNothing);
    await tapSeat(tester, 1, 2); // unselect one Stalls seat, then one Circle seat fits
    await tapSeat(tester, 2, 1);
    expect(find.byKey(const Key('chip-A:2:1')), findsOneWidget);
    expect(find.text('2 seats · Total'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('continue sends the seats and opens checkout', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 4);
    await tapSeat(tester, 1, 5);
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(pickerApi.seatOrders, [
      ['A:1:4', 'A:1:5']
    ]);
    expect(find.text('Checkout'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('choosing the same seats again after leaving checkout makes a new order', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    Future<void> buy() async {
      await tapSeat(tester, 1, 4);
      await tapSeat(tester, 1, 5);
      await tester.tap(find.byKey(const Key('seatContinue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Checkout'), findsWidgets);
    }

    await buy();
    GoRouter.of(tester.element(find.text('Checkout').first)).pop(); // e.g. after cancelling the order there
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await buy();
    expect(pickerApi.seatOrders, [
      ['A:1:4', 'A:1:5'],
      ['A:1:4', 'A:1:5'],
    ]);
    expect(pickerApi.seatOrderKeys, hasLength(2));
    expect(pickerApi.seatOrderKeys[1], isNot(pickerApi.seatOrderKeys[0]));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('409 drops taken seats and refreshes', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 2);
    final loads = pickerApi.seatLoads;
    pickerApi.takenOnNextOrder = ['A:1:2'];
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Just taken: Stalls · Row 1 · Seat 2'), findsOneWidget);
    expect(find.byKey(const Key('chip-A:1:2')), findsNothing);
    expect(find.byKey(const Key('chip-A:1:1')), findsOneWidget); // the other seat is kept
    expect(pickerApi.seatLoads, greaterThan(loads)); // the map was refreshed
    expect(find.text('20,000 MMK'), findsOneWidget);
    // The taken seat can't be picked any more
    await tapSeat(tester, 1, 2);
    expect(find.text("That seat isn't available"), findsOneWidget);
    expect(find.byKey(const Key('chip-A:1:2')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> applyPromo(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(const Key('addPromo')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('promoField')), code);
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('seat picker bar: group discount counts the chosen seats', (tester) async {
    await openPicker(tester, setup: (a) => a.groupTiers = [
          {'minQuantity': 2, 'percentBp': 1000}
        ]);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    expect(find.text('Buy 2+ tickets to save 10%'), findsOneWidget);
    await tapSeat(tester, 1, 2);
    expect(find.text('Group discount −4,000 MMK'), findsOneWidget);
    expect(find.text('36,000 MMK'), findsOneWidget);
    expect(find.text('40,000 MMK'), findsOneWidget); // struck-through original
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seat picker bar: no discount line while a code is being checked, then the answer shows', (tester) async {
    await openPicker(tester, setup: (a) {
      a.groupTiers = [
        {'minQuantity': 2, 'percentBp': 1000}
      ];
      a.promoGate = Completer<void>();
    });
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 2);
    expect(find.text('Group discount −4,000 MMK'), findsOneWidget); // no code yet: the group discount shows
    await applyPromo(tester, 'save20'); // the check is now pending
    expect(find.byKey(const Key('promoCheckingNote')), findsOneWidget);
    expect(find.byKey(const Key('groupDiscountLine')), findsNothing);
    expect(find.byKey(const Key('groupDiscountHint')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('seatTotal'))).data, '40,000 MMK'); // plain total, no strike-through
    expect(tester.widget<FilledButton>(find.byKey(const Key('seatContinue'))).onPressed, isNull);
    pickerApi.promoGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('promoCheckingNote')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('seatTotal'))).data, isNot('40,000 MMK'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seat picker applies promo and sends it with the order', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 4);
    await tapSeat(tester, 1, 5);
    await applyPromo(tester, 'save20');
    expect(pickerApi.promoSeatChecks, [
      ['A:1:4', 'A:1:5']
    ]);
    expect(find.text('Code applied: 8,000 MMK off'), findsOneWidget);
    expect(find.text('32,000 MMK'), findsOneWidget); // discounted total
    expect(find.text('40,000 MMK'), findsOneWidget); // struck-through original
    // there is room on a phone: the total is not shrunk to fit
    expect(tester.getRect(find.byKey(const Key('seatTotal'))).width, closeTo(tester.getSize(find.byKey(const Key('seatTotal'))).width, 0.5));
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(pickerApi.seatPromoCodes, ['save20']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing seats re-checks promo', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'SAVE20');
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    await tapSeat(tester, 1, 2);
    expect(find.textContaining('Code applied'), findsNothing); // old discount hidden until the check returns
    expect(find.text('40,000 MMK'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pickerApi.promoSeatChecks, hasLength(1)); // debounced
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(pickerApi.promoSeatChecks, [
      ['A:1:1'],
      ['A:1:1', 'A:1:2']
    ]);
    expect(find.text('Code applied: 8,000 MMK off'), findsOneWidget);
    expect(find.text('32,000 MMK'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 409 that drops seats re-checks promo', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 2);
    await applyPromo(tester, 'SAVE20');
    pickerApi.takenOnNextOrder = ['A:1:2'];
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(pickerApi.promoSeatChecks.last, ['A:1:1']);
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('promo rejection is localized from reasonCode (Myanmar), never raw API English', (tester) async {
    await openPicker(tester, lang: 'my');
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'USEDUP');
    expect(find.text('ဤကုဒ်ကို အသုံးပြုမှု ပြည့်သွားပါပြီ'), findsOneWidget);
    expect(find.text('This code has been used up'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a code used up at order time is shown in Myanmar and drops the discount; other order errors keep the API message', (tester) async {
    const usedUpMy = 'ဤကုဒ်ကို အသုံးပြုမှု ပြည့်သွားပါပြီ';
    String total() => tester.widget<Text>(find.byKey(const Key('seatTotal'))).data!;
    Future<void> tapContinue() async {
      await tester.tap(find.byKey(const Key('seatContinue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    await openPicker(tester, lang: 'my');
    await phoneWidth(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    final full = total();
    await applyPromo(tester, 'SAVE20');
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsOneWidget); // applied
    expect(total(), isNot(full));
    // Any other error keeps the API message and the discount
    pickerApi.nextOrderError = ApiException(409, 'Sales for Stalls have closed');
    await tapContinue();
    expect(find.text('Sales for Stalls have closed'), findsOneWidget);
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsOneWidget);
    // Used up at order time (400): our Myanmar text, and the code is no longer applied
    pickerApi.nextOrderError = ApiException(400, 'This code has been used up', reasonCode: 'USED_UP');
    await tapContinue();
    expect(find.text(usedUpMy), findsOneWidget);
    expect(find.text('This code has been used up'), findsNothing);
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsNothing);
    expect(total(), full);
    // Applied again, then used up while the order is saved (409): the same
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsOneWidget);
    pickerApi.nextOrderError = ApiException(409, 'This code has been used up', reasonCode: 'USED_UP');
    await tapContinue();
    expect(find.text(usedUpMy), findsOneWidget);
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsNothing);
    expect(total(), full);
    // Continuing now buys at full price without the code
    await tapContinue();
    await tester.pump(const Duration(milliseconds: 600));
    expect(pickerApi.seatPromoCodes, [null]);
    await tester.pumpWidget(const SizedBox());
  }, variant: phoneWidths);

  testWidgets('ticket sheet: a code used up at order time is shown in Myanmar and drops the discount', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    await phoneWidth(tester);
    String total() => tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data!;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    final full = total();
    await tester.tap(find.byKey(const Key('sheetAddPromo'))); // the field opens from "Add promo code"
    await tester.pump();
    await tester.enterText(find.byKey(const Key('promoField')), 'save20');
    await tester.tap(find.byKey(const Key('promoApply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsOneWidget);
    expect(total(), isNot(full));
    api.nextOrderError = ApiException(400, 'This code has been used up', reasonCode: 'USED_UP');
    await tester.tap(find.byKey(const Key('sheetSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ဤကုဒ်ကို အသုံးပြုမှု ပြည့်သွားပါပြီ'), findsOneWidget);
    expect(find.text('This code has been used up'), findsNothing);
    expect(find.textContaining('ကုဒ်သုံးပြီး'), findsNothing);
    expect(total(), full);
    // Submitting now orders at full price without the code
    await tester.tap(find.byKey(const Key('sheetSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.registered, ['e2:tt-e2:2']);
    await tester.pumpWidget(const SizedBox());
  }, variant: phoneWidths);

  testWidgets('invalid promo shows reason', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'NOPE');
    expect(find.text('This code has expired'), findsOneWidget);
    expect(find.byKey(const Key('seatTotal')), findsOneWidget);
    expect(find.text('20,000 MMK'), findsOneWidget);
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(pickerApi.seatPromoCodes, [null]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing the promo clears the discount', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'SAVE20');
    await tester.tap(find.byKey(const Key('promoRemove')));
    await tester.pump();
    expect(find.textContaining('Code applied'), findsNothing);
    expect(find.byKey(const Key('addPromo')), findsOneWidget);
    await tapSeat(tester, 1, 2);
    await tester.pump(const Duration(milliseconds: 400));
    expect(pickerApi.promoSeatChecks, hasLength(1)); // no re-check without a code
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed promo check (429) keeps the code and blocks Continue until a re-check succeeds', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'SAVE20');
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    pickerApi.promoError = 429;
    await tapSeat(tester, 1, 2);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Too many attempts, try again in a minute'), findsOneWidget);
    expect(find.textContaining('Code applied'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('seatContinue'))).onPressed, isNull);
    expect(pickerApi.seatPromoCodes, isEmpty);
    pickerApi.promoError = null;
    await tester.tap(find.byKey(const Key('promoApply'))); // the code is kept: retry
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Code applied: 8,000 MMK off'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('seatContinue'))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a poll that takes a selected seat re-checks the promo with the remaining seats', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 3);
    await applyPromo(tester, 'SAVE20');
    pickerApi.seatStatus = 'AATAAAAAAA';
    await tester.pump(const Duration(seconds: 5)); // next poll
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(pickerApi.promoSeatChecks.last, ['A:1:1']);
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a poll that changes a selected seat\'s price or type re-checks the promo', (tester) async {
    await openPicker(tester, event: 'seated2');
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'SAVE20');
    expect(pickerApi.promoSeatChecks, hasLength(1));
    Future<void> nextPoll() async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    await nextPoll(); // nothing changed: no re-check
    expect(pickerApi.promoSeatChecks, hasLength(1));
    pickerApi.stallsPrice = 25000; // the seat's type is repriced
    await nextPoll();
    expect(pickerApi.promoSeatChecks, [
      ['A:1:1'],
      ['A:1:1'],
    ]);
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    pickerApi.seatTypesNow = '1000011111'; // the seat is now sold as Circle
    await nextPoll();
    expect(pickerApi.promoSeatChecks, hasLength(3));
    expect(pickerApi.promoSeatChecks.last, ['A:1:1']);
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a code applied before the event loads is checked once it does', (tester) async {
    final gate = Completer<void>();
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    api.eventGate = gate;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await applyPromo(tester, 'SAVE20');
    expect(api.promoSeatChecks, isEmpty); // no event yet
    expect(find.textContaining('Code applied'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('seatContinue'))).onPressed, isNull);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.promoSeatChecks, [
      ['A:1:1']
    ]);
    expect(find.text('Code applied: 4,000 MMK off'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('seatContinue'))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a seat taken by someone else while browsing leaves the selection', (tester) async {
    await openPicker(tester);
    await zoomIntoStalls(tester);
    await tapSeat(tester, 1, 1);
    await tapSeat(tester, 1, 3);
    pickerApi.seatStatus = 'AATAAAAAAA';
    await tester.pump(const Duration(seconds: 5)); // next poll
    await tester.pump();
    expect(find.byKey(const Key('chip-A:1:3')), findsNothing);
    expect(find.byKey(const Key('chip-A:1:1')), findsOneWidget);
    expect(find.byKey(const Key('seatNotice')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('best available fills selection', (tester) async {
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('bestAvailable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bestQty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bestPlus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bestPlus'))); // capped at the type's 3 per order
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bestFind')));
    await tester.pumpAndSettle();
    expect(pickerApi.bestCalls, ['tt-seat:3']);
    expect(find.byKey(const Key('chip-A:2:1')), findsOneWidget);
    expect(find.byKey(const Key('chip-A:2:3')), findsOneWidget);
    expect(find.text('60,000 MMK'), findsOneWidget);
    expect(find.byKey(const Key('zoomHint')), findsNothing); // zoomed to the chosen seats
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('availability is polled every 5 s while open, and stops in the background and when closed', (tester) async {
    await openPicker(tester);
    pickerApi.seatStatus = 'AAAAAAAAAA';
    var n = pickerApi.seatLoads;
    await tester.pump(const Duration(seconds: 5));
    expect(pickerApi.seatLoads, n + 1);
    await tester.pump(const Duration(seconds: 5));
    expect(pickerApi.seatLoads, n + 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    n = pickerApi.seatLoads;
    await tester.pump(const Duration(seconds: 20));
    expect(pickerApi.seatLoads, n); // backgrounded: no polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(pickerApi.seatLoads, n + 1); // refreshed on return
    await tester.pump(const Duration(seconds: 5));
    expect(pickerApi.seatLoads, n + 2);

    GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
    n = pickerApi.seatLoads;
    await tester.pump(const Duration(seconds: 20));
    expect(pickerApi.seatLoads, n); // closed: no polling
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event page: seated events offer "Choose seats" instead of the quantity sheet', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chooseSeats')), findsOneWidget);
    expect(find.byKey(const Key('getTickets')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  final seatTicket = {
    'id': 'ticket-seat-0001',
    'status': 'VALID',
    'ticketType': {'name': 'Stalls', 'nameMy': 'ရှေ့ခန်း'},
    'event': {
      'id': 'seated',
      'title': 'Opera Night',
      'titleMy': null,
      'startsAt': '2099-01-15T10:30:00.000Z',
      'endsAt': '2099-01-15T15:30:00.000Z',
      'venue': {'name': 'National Theatre', 'city': 'Yangon'},
      'coverImageUrl': null,
      'organization': 'Yangon Live',
    },
    'qr': 'eyJ0aWQiOiJ0In0.c2ln',
    'seatKey': 'A:1:1',
    'seatLabel': 'Stalls · Row 1 · Seat 1',
    'seatLabelMy': 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1',
    'isComplimentary': false,
    'canCancel': true,
    'canTransfer': false,
  };
  final compTicket = {
    ...seatTicket,
    'id': 'ticket-comp-0002',
    'event': {...(seatTicket['event'] as Map<String, dynamic>), 'title': 'Gala Dinner'},
    'seatKey': 'A:2:2',
    'seatLabel': 'Stalls · Row 2 · Seat 2',
    'seatLabelMy': 'ရှေ့ခန်း · အတန်း 2 · ခုံ 2',
    'isComplimentary': true,
    'compLabel': 'Press',
    'canCancel': false,
  };

  testWidgets('ticket shows seat label and complimentary', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [seatTicket, compTicket]);
    await tester.tap(find.text('Tickets'));
    await tester.pumpAndSettle();
    expect(find.text('Stalls · Row 1 · Seat 1'), findsOneWidget);
    expect(find.text('Complimentary · Press'), findsOneWidget);
    await tester.tap(find.text('Gala Dinner'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ticketSeat'))).data, 'Stalls · Row 2 · Seat 2');
    expect(find.byKey(const Key('ticketComp')), findsOneWidget);
    expect(find.text('COMPLIMENTARY · PRESS'), findsOneWidget); // the badge is uppercase in English
    expect(find.byKey(const Key('transfer')), findsNothing); // comps can't be transferred
  });

  testWidgets('ticket shows the Myanmar seat label when the app is in Myanmar', (tester) async {
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) => a.extraTickets = [seatTicket]);
    await tester.tap(find.byIcon(Icons.confirmation_number_outlined));
    await tester.pumpAndSettle();
    expect(find.text('ရှေ့ခန်း · အတန်း 1 · ခုံ 1'), findsOneWidget);
    expect(find.text('Stalls · Row 1 · Seat 1'), findsNothing);
  });

  testWidgets('cancel button only when canCancel', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [seatTicket, compTicket]);
    await tester.tap(find.text('Tickets'));
    await tester.pumpAndSettle();
    // A comp ticket and the plain default ticket can't be cancelled
    await tester.tap(find.text('Gala Dinner'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancelTicket')), findsNothing);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yangon Food Fair e1').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancelTicket')), findsNothing);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Opera Night'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('cancelTicket')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('cancelTicket')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ticket?'), findsOneWidget);
    await tester.tap(find.text('Keep ticket'));
    await tester.pumpAndSettle();
    expect(api.cancelled, isEmpty);
    await tester.tap(find.byKey(const Key('cancelTicket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelTicketConfirm')));
    await tester.pumpAndSettle();
    expect(api.cancelled, ['ticket-seat-0001']);
    expect(find.text('Ticket cancelled'), findsOneWidget);
  });

  // ───── Waitlist ─────

  Future<void> openEvent(WidgetTester tester, String id) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/$id');
    await tester.pumpAndSettle();
  }

  testWidgets('join waitlist on sold-out type shows position', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    await openEvent(tester, 'soldout');
    final join = find.byKey(const Key('joinWaitlist-tt-soldout'));
    await tester.scrollUntilVisible(join, 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Join waitlist'), findsNWidgets(2)); // the ticket row and the bottom bar
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(find.text('Join the waitlist'), findsOneWidget);
    await tester.tap(find.byKey(const Key('waitPlus')));
    await tester.tap(find.byKey(const Key('waitPlus')));
    await tester.pump();
    expect(find.byKey(const Key('waitQty')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('waitQty'))).data, '3');
    await tester.tap(find.byKey(const Key('waitSubmit')));
    await tester.pumpAndSettle();
    expect(api.waitlistJoins, ['tt-soldout:3']);
    expect(find.text("You're #3 in line"), findsOneWidget);
    expect(find.byKey(const Key('joinWaitlist-tt-soldout')), findsNothing);
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('quantity picker stops at maxPerOrder and a 409 is shown from its reasonCode', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.joinError = ApiException(409, 'You are already on this waitlist', reasonCode: 'ALREADY_WAITING'));
    await openEvent(tester, 'soldout');
    final join = find.byKey(const Key('joinWaitlist-tt-soldout'));
    await tester.scrollUntilVisible(join, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(join);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('waitPlus')), warnIfMissed: false);
      await tester.pump();
    }
    expect(tester.widget<Text>(find.byKey(const Key('waitQty'))).data, '4'); // the type's maxPerOrder
    await tester.tap(find.byKey(const Key('waitSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('You are already on this waitlist'), findsOneWidget);
    expect(api.waitlistJoins, isEmpty);
  });

  testWidgets('a join refused while the offer checkout is unpaid says so, in English and Myanmar', (tester) async {
    for (final (lang, text) in [('en', 'Finish or cancel the checkout from your waitlist offer first'), ('my', 'သင့်စောင့်ဆိုင်းစာရင်း ကမ်းလှမ်းချက်မှ ငွေပေးချေမှုကို အရင် ပြီးဆုံးပါ သို့မဟုတ် ပယ်ဖျက်ပါ')]) {
      final (api, _) = await pumpApp(tester, signedIn: true, lang: lang, setup: (a) => a.joinError = ApiException(409, 'Finish or cancel the checkout from your waitlist offer first', reasonCode: 'CHECKOUT_PENDING'));
      await openEvent(tester, 'soldout');
      final join = find.byKey(const Key('joinWaitlist-tt-soldout'));
      await tester.scrollUntilVisible(join, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(join);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('waitSubmit')));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(api.waitlistJoins, isEmpty);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('leave waitlist', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.waitlist = [FakeApi.waitlistRow('w1', position: 2)]);
    await openEvent(tester, 'soldout');
    await tester.scrollUntilVisible(find.byKey(const Key('waitlistPosition-tt-soldout')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text("You're #2 in line"), findsOneWidget);
    await tester.tap(find.byKey(const Key('leaveWaitlist-tt-soldout')));
    await tester.pumpAndSettle();
    expect(api.waitlistLeaves, ['tt-soldout']);
    expect(find.text("You're #2 in line"), findsNothing);
    expect(find.byKey(const Key('joinWaitlist-tt-soldout')), findsOneWidget); // can join again
  });

  testWidgets('signed out: Join waitlist asks to sign in first', (tester) async {
    await pumpApp(tester);
    await openEvent(tester, 'soldout');
    final join = find.byKey(const Key('joinWaitlist-tt-soldout'));
    await tester.scrollUntilVisible(join, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(find.text('Join the waitlist'), findsNothing);
    expect(find.byType(TextField), findsWidgets); // the login screen
  });

  testWidgets('offer banner shows countdown and opens checkout with waitlistEntryId', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 2, left: const Duration(minutes: 23, seconds: 41, milliseconds: 900))];
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tickets are waiting for you — 23:41 left'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offerBanner')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your reserved tickets'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('offerQty'))).data, '2');
    await tester.tap(find.byKey(const Key('offerMinus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('offerSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.offerOrders, ['e2:tt-e2:1:w1']);
    expect(find.text('Checkout'), findsWidgets); // checkout opened for the new order
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offer sheet total: the current price from a fresh event fetch, less the group discount estimate', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.groupTiers = [{'minQuantity': 2, 'percentBp': 1000}];
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900))];
    });
    Future<void> openSheet() async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('offerBanner')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await openSheet();
    expect(find.text('Estimated total'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('offerTotal'))).data, '9,000 MMK'); // 2 × 5,000 − 10%
    expect(find.text('Group discount −1,000 MMK'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offerMinus')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('offerTotal'))).data, '5,000 MMK');
    expect(find.byKey(const Key('groupDiscountLine')), findsNothing);
    expect(find.byKey(const Key('groupDiscountHint')), findsOneWidget); // buy 2+ to save 10%

    // A price step takes effect while the app has the event cached: the sheet fetches it again
    await tester.tapAt(const Offset(20, 20)); // close the sheet
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    api.paidPriceMmk = 6000;
    await openSheet();
    expect(tester.widget<Text>(find.byKey(const Key('offerTotal'))).data, '10,800 MMK'); // 2 × 6,000 − 10%
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reopened offer (it still carries the cancelled order id) is still "buy now"', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 1, left: const Duration(minutes: 5, milliseconds: 900), orderId: 'old-cancelled-order')];
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tickets are waiting for you — 05:00 left'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offerBanner')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('offerSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.offerOrders, ['e2:tt-e2:1:w1']); // a new order from the offer, not the old order's checkout
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('banner also shows on My Tickets, in Myanmar, and not for WAITING or ended offers', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) {
      a.waitlist = [
        FakeApi.waitlistRow('w0', position: 4),
        FakeApi.waitlistRow('w9', status: 'EXPIRED', event: 'e2', type: 'tt-e2'),
        FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 2, left: const Duration(minutes: 10, milliseconds: 900)),
      ];
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('သင့်အတွက် လက်မှတ်များ စောင့်နေသည် — 10:00 ကျန်သည်'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/tickets');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('offerBanner')), findsOneWidget);
    expect(api.waitlistLoads, 1); // one shared list
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no banner and no polling when the buyer has no active entry', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true);
    expect(find.byKey(const Key('offerBanner')), findsNothing);
    final n = api.waitlistLoads;
    await tester.pump(const Duration(seconds: 65));
    expect(api.waitlistLoads, n);
  });

  testWidgets('waitlist refreshes when the app resumes and every 30 s while in line', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 2, left: const Duration(minutes: 20))];
    });
    await tester.pump(const Duration(milliseconds: 100));
    var n = api.waitlistLoads;
    await tester.pump(const Duration(seconds: 30));
    expect(api.waitlistLoads, n + 1);
    await tester.pump(const Duration(seconds: 30));
    expect(api.waitlistLoads, n + 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    n = api.waitlistLoads;
    await tester.pump(const Duration(seconds: 90));
    expect(api.waitlistLoads, n); // backgrounded: no polling
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(api.waitlistLoads, n + 1); // refreshed on return
    await tester.pump(const Duration(seconds: 30));
    expect(api.waitlistLoads, n + 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seat picker preselects offered seats', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.seatStatus = 'ATTAAAAAAA'; // the public map shows the offered seats taken
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'seated', type: 'tt-seat', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900), seatKeys: ['A:1:2', 'A:1:3'])];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats?offer=w1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('chip-A:1:2')), findsOneWidget);
    expect(find.byKey(const Key('chip-A:1:3')), findsOneWidget);
    expect(find.text('2 seats · Total'), findsOneWidget);
    expect(find.text('40,000 MMK'), findsOneWidget);
    expect(find.text('Reserved for you · 20:00 left'), findsOneWidget);
    expect(find.text('Reserved for you'), findsOneWidget); // legend
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.offerSeatOrders, ['w1:A:1:2,A:1:3']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without the offer the same seats are taken, and best available sends the offer id', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.seatStatus = 'ATTAAAAAAA';
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'seated', type: 'tt-seat', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900), seatKeys: ['A:1:2', 'A:1:3'])];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats'); // opened without the offer
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('chip-A:1:2')), findsNothing);
    expect(find.text('Tap a seat to select it'), findsOneWidget);
    expect(api.offerBest, isEmpty);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pump(const Duration(milliseconds: 500));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats?offer=w1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('bestAvailable')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('bestFind')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.offerBest, ['w1']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('waitlist 409s are shown from reasonCode in Myanmar, never the API English; unknown codes get a generic line', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) => a.joinError = ApiException(409, 'You are already on this waitlist', reasonCode: 'ALREADY_WAITING'));
    await openEvent(tester, 'soldout');
    final join = find.byKey(const Key('joinWaitlist-tt-soldout'));
    await tester.scrollUntilVisible(join, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(join);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waitSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('သင်သည် ဤစောင့်ဆိုင်းစာရင်းတွင် ရှိပြီးသားဖြစ်သည်'), findsOneWidget);
    expect(find.text('You are already on this waitlist'), findsNothing);
    api.joinError = ApiException(409, 'Some brand new server sentence', reasonCode: 'SOMETHING_NEW');
    await tester.tap(find.byKey(const Key('waitSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('တစ်ခုခု မှားယွင်းသွားပါသည်။ ထပ်မံကြိုးစားပါ။'), findsOneWidget);
    expect(find.text('Some brand new server sentence'), findsNothing);
  });

  testWidgets('leaving a line that is already gone says so in Myanmar', (tester) async {
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) {
      a.waitlist = [FakeApi.waitlistRow('w1', position: 2)];
      a.leaveError = ApiException(404, 'You are not on this waitlist', reasonCode: 'NOT_WAITING');
    });
    await openEvent(tester, 'soldout');
    final leave = find.byKey(const Key('leaveWaitlist-tt-soldout'));
    await tester.scrollUntilVisible(leave, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(leave);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('သင်သည် ဤစောင့်ဆိုင်းစာရင်းတွင် မရှိပါ'), findsOneWidget);
    expect(find.text('You are not on this waitlist'), findsNothing);
  });

  testWidgets('offer sheet: a closed offer is explained in Myanmar', (tester) async {
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) {
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 2, left: const Duration(minutes: 10, milliseconds: 900))];
      a.nextOrderError = ApiException(409, 'This waitlist offer is no longer open', reasonCode: 'OFFER_CLOSED');
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('offerBanner')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('offerSubmit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ဤကမ်းလှမ်းချက် မရှိတော့ပါ'), findsOneWidget);
    expect(find.text('This waitlist offer is no longer open'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seat picker: a closed offer at order time is explained in Myanmar (not as a promo problem)', (tester) async {
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) {
      a.seatStatus = 'ATTAAAAAAA';
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'seated', type: 'tt-seat', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900), seatKeys: ['A:1:2', 'A:1:3'])];
      a.nextOrderError = ApiException(409, 'This waitlist offer is no longer open', reasonCode: 'OFFER_CLOSED');
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats?offer=w1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('seatContinue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('seatError')), findsOneWidget);
    expect(find.text('ဤကမ်းလှမ်းချက် မရှိတော့ပါ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offer countdown follows the server clock, not a wrong phone clock', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      // The phone's clock is an hour ahead of the server's: by the phone the offer ended 55 minutes ago
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'e2', type: 'tt-e2', offeredQty: 1, left: const Duration(minutes: -55), serverAhead: const Duration(hours: -1))];
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tickets are waiting for you — 04:59 left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('seat picker: no "offer ended" notice once the offer was purchased, but one when it just expired', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.seatStatus = 'ATTAAAAAAA';
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'seated', type: 'tt-seat', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900), seatKeys: ['A:1:2', 'A:1:3'])];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats?offer=w1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('chip-A:1:2')), findsOneWidget);
    api.waitlist = [FakeApi.waitlistRow('w1', status: 'PURCHASED', event: 'seated', type: 'tt-seat')]; // bought elsewhere
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('This offer has ended'), findsNothing);
    expect(find.byKey(const Key('seatNotice')), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final (api2, _) = await pumpApp(tester, signedIn: true, setup: (a) {
      a.seatStatus = 'ATTAAAAAAA';
      a.waitlist = [FakeApi.waitlistRow('w1', status: 'OFFERED', event: 'seated', type: 'tt-seat', offeredQty: 2, left: const Duration(minutes: 20, milliseconds: 900), seatKeys: ['A:1:2', 'A:1:3'])];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/seated/seats?offer=w1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    api2.waitlist = [FakeApi.waitlistRow('w1', status: 'EXPIRED', event: 'seated', type: 'tt-seat')];
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('seatNotice')), findsOneWidget);
    expect(find.text('This offer has ended'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the 30 s timer stops when the last active entry is gone', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.waitlist = [FakeApi.waitlistRow('w1', position: 2)]);
    await tester.pump(const Duration(milliseconds: 100));
    var n = api.waitlistLoads;
    await tester.pump(const Duration(seconds: 30));
    expect(api.waitlistLoads, n + 1);
    api.waitlist = [FakeApi.waitlistRow('w1', status: 'LEFT')];
    await tester.pump(const Duration(seconds: 30));
    n = api.waitlistLoads;
    await tester.pump(const Duration(seconds: 120));
    expect(api.waitlistLoads, n); // nothing active: no timer
    await tester.pumpWidget(const SizedBox());
  });

  // ───── Event page and ticket picker (visual refresh) ─────
  /// Buttons (of any kind) whose resolved background is the gold token: style set inline, by the theme, or by default.
  List<Element> goldButtons(WidgetTester tester, {Finder? within}) {
    final all = within == null ? find.bySubtype<ButtonStyleButton>() : find.descendant(of: within, matching: find.bySubtype<ButtonStyleButton>());
    return all.evaluate().where((el) {
      final b = el.widget as ButtonStyleButton;
      // Test-only: read the same theme and default styles the button itself resolves.
      // ignore: invalid_use_of_protected_member
      final style = (b.style ?? const ButtonStyle()).merge(b.themeStyleOf(el)).merge(b.defaultStyleOf(el)); // the widget's own style wins
      return style.backgroundColor?.resolve({}) == E360Colors.gold;
    }).toList();
  }

  testWidgets('event page shows the bottom bar with price range and the right action', (tester) async {
    final methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
    // (event, price line, action key, action label)
    for (final (id, price, key, label) in [
      ('seated', '20,000 MMK', 'chooseSeats', 'Choose seats'),
      ('e2', '5,000 MMK', 'getTickets', 'Get tickets'),
      ('e1', 'Free', 'getTickets', 'Register for free'),
      ('mixed', '5,000 – 35,000 MMK', 'getTickets', 'Get tickets'),
      ('soldout', '5,000 MMK', 'joinWaitlistBar', 'Join waitlist'),
    ]) {
      await pumpApp(tester, signedIn: true, setup: (a) => a.methods = methods);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/$id');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('barPrice'))).data, price, reason: id);
      expect(tester.widget<Text>(find.byKey(const Key('barDate'))).data, contains('15 Jan'), reason: id);
      final action = find.byKey(Key(key));
      expect(action, findsOneWidget, reason: id);
      expect(find.descendant(of: action, matching: find.text(label)), findsOneWidget, reason: id);
      expect(goldButtons(tester), hasLength(1), reason: '$id: the bar action is the only gold button');
      expect(goldButtons(tester, within: find.byType(PrimaryActionBar)), hasLength(1), reason: id);
      await tester.pumpWidget(const SizedBox());
    }
    // Paid tickets with no payment method yet: "on sale soon", no bar at all
    await pumpApp(tester, signedIn: true);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    expect(find.byType(PrimaryActionBar), findsNothing);
    // Already in line for the sold-out type: the waitlist row says so and the bar is gone
    await pumpApp(tester, signedIn: true, setup: (a) => a.waitlist = [FakeApi.waitlistRow('w1', position: 2)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/soldout');
    await tester.pumpAndSettle();
    expect(find.byType(PrimaryActionBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('good to know lists price rise and group discount when present, and is hidden when empty', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.nextPriceJson = {'priceMmk': 7000, 'startsAt': '2027-01-10T08:00:00.000Z'};
      a.groupTiers = [
        {'minQuantity': 4, 'percentBp': 2000},
        {'minQuantity': 2, 'percentBp': 1000},
      ];
    });
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e2');
    await tester.pumpAndSettle();
    expect(find.text('Good to know'), findsOneWidget);
    expect(find.text('Price rises soon'), findsOneWidget);
    expect(find.text('General goes to 7,000 MMK on Sun, 10 Jan'), findsOneWidget);
    expect(find.text('Group discount'), findsOneWidget);
    expect(find.text('2+ tickets: 10% off\n4+ tickets: 20% off'), findsOneWidget); // tiers in order
    // The rich fixture's refund policy shows too
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/rich');
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('goodToKnow')), matching: find.text('No refunds')), findsOneWidget);
    // Free event with nothing to add: no section
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn: true);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/e1');
    await tester.pumpAndSettle();
    expect(find.text('Good to know'), findsNothing);
    expect(find.byKey(const Key('goodToKnow')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ticket picker cards have steppers, scarcity line and sold-out badge with Join waitlist', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/mixed');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    // One card per type, steppers on the two on sale
    expect(find.byType(StepperButton), findsNWidgets(4));
    expect(find.bySemanticsLabel('One more Standing ticket'), findsOneWidget);
    expect(find.bySemanticsLabel('One fewer VIP deck ticket'), findsOneWidget);
    // Scarcity in amber only where few are left; the limit is always there
    expect(tester.widget<Text>(find.byKey(const Key('scarcity-tt-mix-a'))).data, '8 left · Up to 4 per person');
    expect(tester.widget<Text>(find.byKey(const Key('scarcity-tt-mix-b'))).data, 'Up to 2 per person');
    expect(tester.widget<Text>(find.byKey(const Key('scarcity-tt-mix-a'))).style?.color, E360Colors.amberInk);
    expect(tester.widget<Text>(find.byKey(const Key('scarcity-tt-mix-b'))).style?.color, isNot(E360Colors.amberInk));
    // Every card has the same 2 px border; only the selected one is navy, so nothing shifts
    final borders = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border?.top.width == 2);
    expect(borders, findsNWidgets(3));
    final navy = tester.widgetList<Container>(borders).where((c) => (c.decoration as BoxDecoration).border!.top.color == E360Colors.night);
    expect(navy, hasLength(1));
    expect(tester.widget<Text>(find.byKey(const Key('qty-tt-mix-a'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('qty-tt-mix-b'))).data, '0');
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '5,000 MMK');
    // + on another type moves the selection to it
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('qty-tt-mix-b'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('qty-tt-mix-a'))).data, '0');
    expect(tester.widget<Text>(find.byKey(const Key('sheetTotal'))).data, '35,000 MMK');
    expect(find.text('1 ticket · Total'), findsOneWidget);
    // Sold-out type: dark badge and the existing waitlist flow
    expect(find.text('SOLD OUT'), findsOneWidget);
    final join = find.byKey(const Key('sheet-joinWaitlist-tt-mix-c'));
    expect(join, findsOneWidget);
    expect(find.descendant(of: join, matching: find.text('Join waitlist')), findsOneWidget);
    await tester.tap(join);
    await tester.pumpAndSettle();
    expect(find.text('Join the waitlist'), findsOneWidget);
    await tester.tap(find.byKey(const Key('waitSubmit')));
    await tester.pumpAndSettle();
    expect(api.waitlistJoins, ['tt-mix-c:1']);
    // The gold "Continue to payment" is the sheet's action
    expect(find.descendant(of: find.byKey(const Key('sheetSubmit')), matching: find.text('Continue to payment')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only one gold button is on screen when an offer banner is visible', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) {
      a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
      a.waitlist = [FakeApi.waitlistRow('w9', status: 'OFFERED', event: 'mixed', type: 'tt-mix-c', offeredQty: 2, left: const Duration(minutes: 20))];
    });
    expect(find.byKey(const Key('offerBanner')), findsOneWidget); // the banner on Discover
    expect(goldButtons(tester), isEmpty);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/mixed');
    await tester.pumpAndSettle();
    final buy = find.byKey(const Key('buyOffer-tt-mix-c'));
    await tester.scrollUntilVisible(buy, 200, scrollable: find.byType(Scrollable).first);
    expect(buy, findsOneWidget);
    expect(find.byKey(const Key('getTickets')), findsOneWidget); // the bar is up
    expect(goldButtons(tester), hasLength(1));
    expect(goldButtons(tester, within: find.byType(PrimaryActionBar)), hasLength(1));
    expect(goldButtons(tester, within: find.byKey(const Key('buyOffer-tt-mix-c'))), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event page and ticket picker have no overflow at 360 and 412 dp in EN and MY', (tester) async {
    for (final lang in ['en', 'my']) {
      for (final id in ['mixed', 'seated2', 'rich']) {
        await pumpApp(tester, signedIn: true, lang: lang, setup: (a) {
          a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')];
          a.nextPriceJson = {'priceMmk': 700000, 'startsAt': '2027-01-10T08:00:00.000Z'};
          a.groupTiers = [
            {'minQuantity': 2, 'percentBp': 1000},
            {'minQuantity': 4, 'percentBp': 2000},
          ];
          a.waitlist = [FakeApi.waitlistRow('w9', status: 'OFFERED', event: 'mixed', type: 'tt-mix-c', offeredQty: 2, left: const Duration(minutes: 20))];
        });
        await phoneWidth(tester);
        GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/$id');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $id top');
        await tester.fling(find.byType(Scrollable).first, const Offset(0, -3000), 3000); // to the bottom
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $id scrolled');
        if (id == 'mixed') {
          await tester.tap(find.byKey(const Key('getTickets')));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.add).first);
          await tester.pump();
          await tester.tap(find.byKey(const Key('sheetAddPromo')));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$lang picker');
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  }, variant: phoneWidths);

  testWidgets('an event with seats and standing types shows exactly one gold button, in the bar', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/both');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chooseSeats')), findsOneWidget);
    final standing = find.byKey(const Key('getTickets'));
    expect(standing, findsOneWidget); // "Standing tickets", outlined, in the Tickets section
    expect(goldButtons(tester), hasLength(1));
    expect(goldButtons(tester, within: find.byType(PrimaryActionBar)), hasLength(1));
    expect(goldButtons(tester, within: standing), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the ticket picker open, exactly one gold button is visible in the sheet', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) => a.methods = [PaymentMethod(code: 'MOCK', label: 'Mock pay (test)')]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/mixed');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getTickets')));
    await tester.pumpAndSettle();
    expect(goldButtons(tester, within: find.byType(BottomSheet)), hasLength(1));
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.byKey(const Key('sheetSubmit'))), findsOneWidget); // and it is the sheet's action
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Read more expands the description', (tester) async {
    await pumpApp(tester, signedIn: true);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/event/mixed');
    await tester.pumpAndSettle();
    final text = find.textContaining('Welcome the new year');
    expect(tester.widget<Text>(text).maxLines, 4);
    expect(find.byKey(const Key('readMore')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('readMore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readMore')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(text).maxLines, isNull);
    expect(find.byKey(const Key('readMore')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // ───── Tickets and remaining screens (visual refresh) ─────
  Future<void> openTicket(WidgetTester tester, String title) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/tickets');
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  testWidgets('ticket screen shows the detail grid (date, time, venue, seat) and the QR on a navy background', (tester) async {
    await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [seatTicket]);
    await openTicket(tester, 'Opera Night');
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, E360Colors.night);
    final card = find.byKey(const Key('ticketCard'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.byType(QrImageView)), findsOneWidget);
    for (final label in ['Date', 'Time', 'Venue', 'Seat']) {
      expect(find.descendant(of: card, matching: find.text(label)), findsOneWidget, reason: label);
    }
    expect(find.descendant(of: card, matching: find.text('National Theatre, Yangon')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ticketSeat'))).data, 'Stalls · Row 1 · Seat 1');
    // The mockup's gold button is Directions, and it is the only one
    expect(goldButtons(tester), hasLength(1));
    expect(goldButtons(tester).single.widget.key, const Key('ticketDirections'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ticket screen has no overflow at 360 dp in EN and MY, with and without a seat', (tester) async {
    final longTicket = {
      ...seatTicket,
      'id': 'ticket-long-0003',
      'event': {...(seatTicket['event'] as Map<String, dynamic>), 'title': 'Yangon International New Year Countdown Gala Night with the Philharmonic Orchestra', 'titleMy': 'ရန်ကုန် နိုင်ငံတကာ နှစ်သစ်ကူး ဂါလာညနေ ဂီတပွဲတော်ကြီး'},
    };
    for (final lang in ['en', 'my']) {
      // seated, long title, and the plain default ticket (no seat)
      for (final id in ['ticket-seat-0001', 'ticket-long-0003', 'ticket-0001-abcd']) {
        await pumpApp(tester, signedIn: true, lang: lang, setup: (a) => a.extraTickets = [seatTicket, longTicket]);
        await phoneWidth(tester);
        GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/ticket/$id');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ticketCard')), findsOneWidget, reason: '$lang $id');
        expect(tester.takeException(), isNull, reason: '$lang $id');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $id scrolled');
        await tester.pumpWidget(const SizedBox());
      }
    }
  }, variant: phoneWidths);

  testWidgets('existing ticket behaviours still present', (tester) async {
    final (api, _) = await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [seatTicket, compTicket]);
    // Complimentary: the label and no cancel / transfer
    await openTicket(tester, 'Gala Dinner');
    expect(find.byKey(const Key('ticketComp')), findsOneWidget);
    expect(find.text('COMPLIMENTARY · PRESS'), findsOneWidget);
    expect(find.byKey(const Key('cancelTicket')), findsNothing);
    expect(find.byKey(const Key('transfer')), findsNothing);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
    // Cancelable: the cancel link asks first, then cancels
    await tester.tap(find.text('Opera Night'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticketComp')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('cancelTicket')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('cancelTicket')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ticket?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelTicketConfirm')));
    await tester.pumpAndSettle();
    expect(api.cancelled, ['ticket-seat-0001']);
    await tester.pumpWidget(const SizedBox());
    // Myanmar seat label
    await pumpApp(tester, signedIn: true, lang: 'my', setup: (a) => a.extraTickets = [seatTicket]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/ticket/ticket-seat-0001');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('ticketSeat'))).data, 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('login and language screens render with pill buttons', (tester) async {
    phoneScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(overrides: [prefsProvider.overrideWithValue(sp), apiProvider.overrideWithValue(FakeApi(MemoryTokenStore()))], child: const UserApp()));
    await tester.pumpAndSettle();
    expect(find.byType(E360Mark), findsOneWidget);
    expect(goldButtons(tester), hasLength(1));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).style?.shape?.resolve({}), isA<StadiumBorder>());
    await tester.pumpWidget(const SizedBox());

    await pumpApp(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/login');
    await tester.pumpAndSettle();
    expect(find.byType(E360Mark), findsOneWidget);
    expect(goldButtons(tester), hasLength(1));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).style?.shape?.resolve({}), isA<StadiumBorder>());
    await tester.pumpWidget(const SizedBox());
  });


  testWidgets('a ticket with no venue has no Directions button and Add to calendar is the gold one', (tester) async {
    final noVenue = {...seatTicket, 'id': 'ticket-nov-0004', 'event': {...(seatTicket['event'] as Map<String, dynamic>), 'venue': null}};
    await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [noVenue]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/ticket/ticket-nov-0004');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticketDirections')), findsNothing);
    expect(goldButtons(tester), hasLength(1));
    expect(goldButtons(tester).single.widget.key, const Key('addToCalendar'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a refunded ticket shows the void panel instead of the QR', (tester) async {
    final refunded = {...seatTicket, 'id': 'ticket-ref-0005', 'status': 'REFUNDED', 'canCancel': false};
    await pumpApp(tester, signedIn: true, setup: (a) => a.extraTickets = [refunded]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/ticket/ticket-ref-0005');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ticketVoid')), findsOneWidget);
    expect(find.text('This ticket was refunded.'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(goldButtons(tester), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test('the Directions link encodes the venue name and city', () {
    final uri = ticketDirectionsUri('Shwe Pyi Theatre', 'Yangon');
    expect(uri.toString(), 'https://www.google.com/maps/search/?api=1&query=Shwe%20Pyi%20Theatre%2C%20Yangon');
    expect(uri.queryParameters['query'], 'Shwe Pyi Theatre, Yangon');
  });
}
