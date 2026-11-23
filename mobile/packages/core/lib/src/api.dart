import 'package:dio/dio.dart';

import 'app_config.dart';
import 'crew.dart';
import 'streams.dart';
import 'models.dart';
import 'notifications.dart';
import 'orders.dart';
import 'org.dart';
import 'token_store.dart';

/// Error with a user-presentable message from the API (`message` field) and the HTTP status.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.takenSeats = const [], this.reasonCode});
  final int? status;
  final String message;

  /// A machine-readable reason from the error body (e.g. a rejected promo code's `USED_UP`), for localized text.
  final String? reasonCode;

  /// Seat keys that were just taken (409 on a seated order).
  final List<String> takenSeats;

  bool get isRateLimited => status == 429;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Typed client for the Event 360 API. Adds the access token, refreshes it once on 401, and
/// converts errors to [ApiException].
class Event360Api {
  Event360Api(AppConfig config, this.tokens, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${config.apiBaseUrl}/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final access = await tokens.accessToken();
        if (access != null && options.extra['auth'] != false) options.headers['Authorization'] = 'Bearer $access';
        handler.next(options);
      },
      onError: (e, handler) async {
        final retried = e.requestOptions.extra['retried'] == true;
        if (e.response?.statusCode == 401 && !retried && e.requestOptions.extra['auth'] != false) {
          final out = await _refresh();
          if (out.ok) {
            final opts = e.requestOptions..extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${await tokens.accessToken()}';
            try {
              return handler.resolve(await _dio.fetch(opts));
            } on DioException catch (e2) {
              return handler.next(e2);
            }
          }
          if (out.failure != null) {
            // The refresh could not be done right now (no connection, timeout, server trouble): the session is still good.
            // The request fails with what went wrong, the tokens stay, and the next request refreshes again.
            final f = out.failure!;
            return handler.next(DioException(requestOptions: e.requestOptions, response: f.response, type: f.type, error: f.error, message: f.message));
          }
        }
        if (e.response?.statusCode == 401 && e.requestOptions.extra['auth'] != false) onSessionExpired?.call();
        handler.next(e);
      },
    ));
  }

  final Dio _dio;
  final TokenStore tokens;
  Future<_Refresh>? _refreshing;

  /// Called when a signed-in request still gets 401 after the token refresh (the session is over). The app signs the
  /// user out here, once, instead of every screen handling it. Requests that carry no session (sign-in, refresh) never call it.
  void Function()? onSessionExpired;

  /// One refresh at a time, shared by every request that needs it. Three outcomes: done; rejected (the server answered 400,
  /// 401 or 403: the refresh token is no good, the tokens are cleared and the session is over); or transient (anything else:
  /// no connection, timeout, a 5xx, an unreadable answer), which keeps the tokens.
  Future<_Refresh> _refresh() => _refreshing ??= () async {
        try {
          final rt = await tokens.refreshToken();
          if (rt == null) return const _Refresh.rejected();
          final r = await _dio.post<Map<String, dynamic>>('/auth/refresh',
              data: {'refreshToken': rt}, options: Options(extra: {'auth': false}));
          await tokens.save(r.data!['accessToken'] as String, r.data!['refreshToken'] as String);
          return const _Refresh.ok();
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 400 || code == 401 || code == 403) {
            await tokens.clear();
            return const _Refresh.rejected();
          }
          return _Refresh.transient(e);
        } catch (e) {
          return _Refresh.transient(DioException(requestOptions: RequestOptions(path: '/auth/refresh'), type: DioExceptionType.unknown, error: e));
        } finally {
          _refreshing = null;
        }
      }();

  Future<T> _call<T>(Future<Response<dynamic>> Function() send, T Function(dynamic data) parse) async {
    try {
      final r = await send();
      return parse(r.data);
    } on DioException catch (e) {
      final data = e.response?.data;
      var msg = 'Network error';
      if (data is Map && data['message'] != null) {
        final m = data['message'];
        msg = m is List ? m.join(', ') : m.toString();
      } else if (e.response != null) {
        msg = 'HTTP ${e.response!.statusCode}';
      }
      final taken = data is Map && data['takenSeats'] is List ? (data['takenSeats'] as List).whereType<String>().toList() : const <String>[];
      final reasonCode = data is Map && data['reasonCode'] is String ? data['reasonCode'] as String : null;
      throw ApiException(e.response?.statusCode, msg, takenSeats: taken, reasonCode: reasonCode);
    }
  }

  // ───── Catalog & events (public) ─────

  Future<List<Category>> categories() => _call(
        () => _dio.get('/categories', options: Options(extra: {'auth': false})),
        (d) => (d as List).map((c) => Category.fromJson(c as Map<String, dynamic>)).toList(),
      );

  Future<EventPage> events({String? q, String? category, String? city, bool? free, DateTime? from, DateTime? to, int page = 1, int limit = 20}) =>
      _call(
        () => _dio.get('/events', queryParameters: {
          if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          if (category != null) 'category': category,
          if (city != null && city.isNotEmpty) 'city': city,
          if (free != null) 'free': '$free',
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
          'page': page,
          'limit': limit,
        }, options: Options(extra: {'auth': false})),
        (d) => EventPage.fromJson(d as Map<String, dynamic>),
      );

  Future<EventSummary> event(String idOrSlug) => _call(
        () => _dio.get('/events/${Uri.encodeComponent(idOrSlug)}', options: Options(extra: {'auth': false})),
        (d) => EventSummary.fromJson(d as Map<String, dynamic>),
      );

  Future<OrganizerProfile> organizer(String slug) => _call(
        () => _dio.get('/organizers/${Uri.encodeComponent(slug)}', options: Options(extra: {'auth': false})),
        (d) => OrganizerProfile.fromJson(d as Map<String, dynamic>),
      );

  /// URL of the event's iCalendar file ("Add to calendar").
  Uri calendarUri(String eventId) => Uri.parse('${_dio.options.baseUrl}/events/$eventId/calendar.ics');

  // ───── Auth (phone OTP) ─────

  /// Returns the dev code when the server echoes it (dev environment only).
  Future<String?> requestOtp(String phone) => _call(
        () => _dio.post('/auth/otp/request', data: {'phone': phone}, options: Options(extra: {'auth': false})),
        (d) => (d as Map<String, dynamic>)['devCode'] as String?,
      );

  Future<void> verifyOtp(String phone, String code) async {
    final d = await _call(
      () => _dio.post('/auth/otp/verify', data: {'phone': phone, 'code': code}, options: Options(extra: {'auth': false})),
      (d) => d as Map<String, dynamic>,
    );
    await tokens.save(d['accessToken'] as String, d['refreshToken'] as String);
  }

  Future<Me> me() => _call(() => _dio.get('/auth/me'), (d) => Me.fromJson(d as Map<String, dynamic>));

  Future<void> logout() => tokens.clear();

  // ───── Registration & tickets ─────

  Future<List<String>> register(String eventId, String ticketTypeId, int quantity) => _call(
        () => _dio.post('/events/$eventId/registrations', data: {'ticketTypeId': ticketTypeId, 'quantity': quantity}),
        (d) => ((d as Map<String, dynamic>)['ticketIds'] as List).cast<String>(),
      );

  // ───── Waitlist ─────

  /// Joins the line of a sold-out ticket type for [quantity] tickets (1..maxPerOrder). 409 when it is not sold out, the
  /// line is closed or paused, the buyer is already in line, or the per-person limit is reached.
  Future<WaitlistJoin> joinWaitlist(String ticketTypeId, int quantity) => _call(
        () => _dio.post('/ticket-types/$ticketTypeId/waitlist', data: {'quantity': quantity}),
        (d) => WaitlistJoin.fromJson(d as Map<String, dynamic>),
      );

  Future<void> leaveWaitlist(String ticketTypeId) => _call(() => _dio.delete('/ticket-types/$ticketTypeId/waitlist'), (_) {});

  /// The buyer's entries: active ones (place in line, or a live offer with its expiry and seat keys) and recently ended ones.
  Future<List<WaitlistEntry>> myWaitlist() => _call(
        () => _dio.get('/me/waitlist'),
        (d) => (d as List).map((x) => WaitlistEntry.fromJson(x as Map<String, dynamic>)).toList(),
      );

  // ───── Notifications ─────

  Future<Inbox> notifications({DateTime? before, int limit = 30}) => _call(
        () => _dio.get('/me/notifications', queryParameters: {'limit': limit, if (before != null) 'before': before.toIso8601String()}),
        (d) => Inbox.fromJson(d as Map<String, dynamic>),
      );

  /// ids empty → mark everything read.
  Future<void> markNotificationsRead([List<String> ids = const []]) =>
      _call(() => _dio.post('/me/notifications/read', data: {if (ids.isNotEmpty) 'ids': ids}), (_) {});

  Future<void> registerDevice(String pushToken, String platform, {String appId = 'user_app'}) =>
      _call(() => _dio.post('/me/devices', data: {'pushToken': pushToken, 'platform': platform, 'appId': appId}), (_) {});

  Future<void> removeDevice(String pushToken) => _call(() => _dio.post('/me/devices/remove', data: {'pushToken': pushToken}), (_) {});

  // ───── Paid checkout ─────

  Future<List<PaymentMethod>> paymentMethods() => _call(
        () => _dio.get('/payments/methods', options: Options(extra: {'auth': false})),
        (d) => (d as List).map((x) => PaymentMethod.fromJson(x as Map<String, dynamic>)).toList(),
      );

  /// Creates an order (free → confirmed with tickets; paid → seats held for 10 minutes).
  ///
  /// [seats] (seated events) are seat keys; they are claimed all or none, and a 409 carries [ApiException.takenSeats].
  /// [waitlistEntryId] buys from the buyer's live waitlist offer (see [myWaitlist]); other types may be added from normal sale.
  Future<Order> createOrder(String eventId, Map<String, int> quantities,
          {required String idempotencyKey, String channel = 'APP', String? promoCode, List<String> seats = const [], String? waitlistEntryId}) =>
      _call(
        () => _dio.post('/events/$eventId/orders', data: {
          'items': [for (final e in quantities.entries) if (e.value > 0) {'ticketTypeId': e.key, 'quantity': e.value}],
          if (seats.isNotEmpty) 'seats': seats,
          'idempotencyKey': idempotencyKey,
          'channel': channel,
          if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
          if (waitlistEntryId != null) 'waitlistEntryId': waitlistEntryId,
        }),
        (d) => Order.fromJson(d as Map<String, dynamic>),
      );

  /// Seat map and live availability of a seated event (cheap to poll: the server caches it for 2 s).
  Future<SeatMapData> seatMap(String eventId) => _call(
        () => _dio.get('/events/$eventId/seats', options: Options(extra: {'auth': false})),
        (d) => SeatMapData.fromJson(d as Map<String, dynamic>),
      );

  /// Server-picked seats (adjacent where possible). Holds nothing. 409 'Not enough seats together' when none fit.
  /// With [waitlistEntryId] (the buyer's live offer) the seats reserved for them count as free; that call is signed in.
  Future<List<String>> bestSeats(String eventId, String ticketTypeId, int quantity, {String? waitlistEntryId}) => _call(
        () => _dio.post('/events/$eventId/seats/best',
            data: {'ticketTypeId': ticketTypeId, 'quantity': quantity, if (waitlistEntryId != null) 'waitlistEntryId': waitlistEntryId},
            options: waitlistEntryId == null ? Options(extra: {'auth': false}) : null),
        (d) => ((d as Map<String, dynamic>)['seats'] as List).cast<String>(),
      );

  /// Gives back one of the holder's free tickets before the event starts; its seat goes back on sale.
  Future<void> cancelTicket(String ticketId) => _call(() => _dio.post('/me/tickets/$ticketId/cancel'), (_) {});

  /// Previews a promo code. [seats] (seat keys of a seated order) count as one ticket of their own type each; [quantities] may then be empty.
  Future<PromoCheck> checkPromo(String eventId, String code, Map<String, int> quantities, {List<String> seats = const []}) => _call(
        () => _dio.post('/events/$eventId/promo-check', data: {
          'code': code,
          'items': [for (final e in quantities.entries) if (e.value > 0) {'ticketTypeId': e.key, 'quantity': e.value}],
          if (seats.isNotEmpty) 'seats': seats,
        }),
        (d) => PromoCheck.fromJson(d as Map<String, dynamic>),
      );

  /// Sends a ticket to another phone number; returns the masked number it went to.
  Future<String> transferTicket(String ticketId, String phone) =>
      _call(() => _dio.post('/me/tickets/$ticketId/transfer', data: {'phone': phone}), (d) => (d as Map<String, dynamic>)['to'] as String);

  Future<Order> order(String id) => _call(() => _dio.get('/orders/$id'), (d) => Order.fromJson(d as Map<String, dynamic>));

  Future<Order> payOrder(String id, String provider, {String? returnUrl}) => _call(
        () => _dio.post('/orders/$id/pay', data: {'provider': provider, if (returnUrl != null) 'returnUrl': returnUrl}),
        (d) => Order.fromJson(d as Map<String, dynamic>),
      );

  Future<Order> cancelOrder(String id) => _call(() => _dio.post('/orders/$id/cancel'), (d) => Order.fromJson(d as Map<String, dynamic>));

  Future<List<Order>> pendingOrders() => _call(
        () => _dio.get('/me/orders', queryParameters: {'pending': '1'}),
        (d) => (d as List).map((x) => Order.fromJson(x as Map<String, dynamic>)).toList(),
      );

  Future<List<MyTicket>> myTickets() => _call(
        () => _dio.get('/me/tickets'),
        (d) => (d as List).map((t) => MyTicket.fromApi(t as Map<String, dynamic>)).toList(),
      );

  Future<String> ticketPublicKey() => _call(
        () => _dio.get('/meta/ticket-public-key', options: Options(extra: {'auth': false})),
        (d) => (d as Map<String, dynamic>)['publicKey'] as String,
      );

  // ───── Crew (door check-in) ─────

  /// Portal-staff sign-in (invited crew, organizers).
  Future<void> passwordLogin(String email, String password) async {
    final d = await _call(
      () => _dio.post('/auth/password/login', data: {'email': email, 'password': password}, options: Options(extra: {'auth': false})),
      (d) => d as Map<String, dynamic>,
    );
    await tokens.save(d['accessToken'] as String, d['refreshToken'] as String);
  }

  /// Volunteer device: event code → a session scoped to one event (no refresh token).
  Future<CrewRedeem> crewRedeem(String code, String deviceName) async {
    final r = await _call(
      () => _dio.post('/crew/redeem', data: {'code': code, 'deviceName': deviceName}, options: Options(extra: {'auth': false})),
      (d) => CrewRedeem.fromJson(d as Map<String, dynamic>),
    );
    await tokens.save(r.accessToken, '');
    return r;
  }

  Future<List<CrewEvent>> crewEvents() =>
      _call(() => _dio.get('/crew/events'), (d) => (d as List).map((e) => CrewEvent.fromJson(e as Map<String, dynamic>)).toList());

  Future<CrewManifest> crewManifest(String eventId) =>
      _call(() => _dio.get('/crew/events/$eventId/manifest'), (d) => CrewManifest.fromJson(d as Map<String, dynamic>));

  Future<ScanOutcome> crewScan(String eventId, String qr, {String? gate, String? deviceId, DateTime? scannedAt}) => _call(
        () => _dio.post('/crew/events/$eventId/scan', data: {
          'qr': qr,
          if (gate != null && gate.isNotEmpty) 'gate': gate,
          if (deviceId != null) 'deviceId': deviceId,
          'scannedAt': (scannedAt ?? DateTime.now()).toUtc().toIso8601String(),
        }),
        (d) => ScanOutcome.fromJson(d as Map<String, dynamic>),
      );

  /// Uploads scans recorded offline. Each map: clientId, qr|ticketId, method, gate, deviceId, scannedAt.
  Future<List<ScanOutcome>> crewSync(String eventId, List<Map<String, dynamic>> scans) => _call(
        () => _dio.post('/crew/events/$eventId/sync', data: {'scans': scans}),
        (d) => ((d as Map<String, dynamic>)['results'] as List).map((r) => ScanOutcome.fromJson(r as Map<String, dynamic>)).toList(),
      );

  Future<List<CrewTicket>> crewSearch(String eventId, String q) => _call(
        () => _dio.get('/crew/events/$eventId/search', queryParameters: {'q': q}),
        (d) => (d as List).map((t) => CrewTicket.fromJson(t as Map<String, dynamic>)).toList(),
      );

  Future<ScanOutcome> crewManualCheckin(String eventId, String ticketId, {String? gate, String? deviceId}) => _call(
        () => _dio.post('/crew/events/$eventId/tickets/$ticketId/checkin', data: {
          if (gate != null && gate.isNotEmpty) 'gate': gate,
          if (deviceId != null) 'deviceId': deviceId,
          'scannedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        (d) => ScanOutcome.fromJson(d as Map<String, dynamic>),
      );

  Future<CrewTicket> crewUndo(String eventId, String ticketId) => _call(
        () => _dio.post('/crew/events/$eventId/tickets/$ticketId/undo'),
        (d) => CrewTicket.fromJson((d as Map<String, dynamic>)['ticket'] as Map<String, dynamic>),
      );

  Future<CrewStats> crewStats(String eventId) =>
      _call(() => _dio.get('/crew/events/$eventId/stats'), (d) => CrewStats.fromJson(d as Map<String, dynamic>));

  // ───── Live & recordings ─────

  Future<EventStreams> eventStreams(String idOrSlug) => _call(
        () => _dio.get('/events/${Uri.encodeComponent(idOrSlug)}/streams', options: Options(extra: {'auth': false})),
        (d) => EventStreams.fromJson(d as Map<String, dynamic>),
      );

  /// kind: 'live' (channel id) or 'vod' (recording id). 403 = no ticket, 410 = not live now.
  Future<WatchGrant> watchToken(String kind, String id) =>
      _call(() => _dio.post('/watch/$kind/$id/token'), (d) => WatchGrant.fromJson(d as Map<String, dynamic>));

  /// 409 = another device took over playback.
  Future<void> watchHeartbeat(String sessionId) => _call(() => _dio.post('/watch/sessions/$sessionId/heartbeat'), (_) {});

  // ───── Organizer app ─────

  Future<List<OrgMembership>> myOrganizations() => _call(
        () => _dio.get('/auth/me'),
        (d) => ((d as Map<String, dynamic>)['organizations'] as List? ?? const []).map((x) => OrgMembership.fromJson(x as Map<String, dynamic>)).toList(),
      );

  Future<List<OrgEvent>> orgEvents(String orgId) =>
      _call(() => _dio.get('/organizations/$orgId/events'), (d) => (d as List).map((x) => OrgEvent.fromJson(x as Map<String, dynamic>)).toList());

  Future<EventDashboard> eventDashboard(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/dashboard'), (d) => EventDashboard.fromJson(d as Map<String, dynamic>));

  /// Live check-in numbers (same shape as the crew stats).
  Future<CrewStats> eventAttendance(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/attendance'), (d) => CrewStats.fromJson(d as Map<String, dynamic>));

  Future<List<RecentOrder>> recentOrders(String orgId, String eventId) => _call(
        () => _dio.get('/organizations/$orgId/events/$eventId/sales'),
        (d) => ((d as Map<String, dynamic>)['recent'] as List).map((x) => RecentOrder.fromJson(x as Map<String, dynamic>)).toList(),
      );

  Future<EventSales> eventSales(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/sales'), (d) => EventSales.fromJson(d as Map<String, dynamic>));

  Future<OrgOrderPage> eventOrders(String orgId, String eventId, {String? status, String? q, String? cursor, int limit = 30}) => _call(
        () => _dio.get('/organizations/$orgId/events/$eventId/orders', queryParameters: {if (status != null) 'status': status, if (q != null) 'q': q, if (cursor != null) 'cursor': cursor, 'limit': limit}),
        (d) => OrgOrderPage.fromJson(d as Map<String, dynamic>),
      );

  Future<OrgOrderDetail> eventOrder(String orgId, String eventId, String orderId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/orders/$orderId'), (d) => OrgOrderDetail.fromJson(d as Map<String, dynamic>));

  Future<PayoutSummary> payoutSummary(String orgId) =>
      _call(() => _dio.get('/organizations/$orgId/payouts/summary'), (d) => PayoutSummary.fromJson(d as Map<String, dynamic>));

  Future<List<CrewCode>> crewCodes(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/crew-codes'), (d) => (d as List).map((x) => CrewCode.fromJson(x as Map<String, dynamic>)).toList());

  Future<CrewCode> createCrewCode(String orgId, String eventId, String label, {String? gate}) => _call(
        () => _dio.post('/organizations/$orgId/events/$eventId/crew-codes', data: {'label': label, if (gate != null && gate.isNotEmpty) 'gate': gate}),
        (d) => CrewCode.fromJson(d as Map<String, dynamic>),
      );

  Future<void> revokeCrewCode(String orgId, String eventId, String codeId) =>
      _call(() => _dio.delete('/organizations/$orgId/events/$eventId/crew-codes/$codeId'), (_) {});

  Future<Announcements> announcements(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/announcements'), (d) => Announcements.fromJson(d as Map<String, dynamic>));

  Future<void> sendAnnouncement(String orgId, String eventId, {required String title, required String body, String? titleMy, String? bodyMy}) => _call(
        () => _dio.post('/organizations/$orgId/events/$eventId/announcements', data: {
          'title': title,
          'body': body,
          if (titleMy != null && titleMy.isNotEmpty) 'titleMy': titleMy,
          if (bodyMy != null && bodyMy.isNotEmpty) 'bodyMy': bodyMy,
        }),
        (_) {},
      );

  Future<List<PromoCodeInfo>> promoCodes(String orgId, String eventId) => _call(
        () => _dio.get('/organizations/$orgId/events/$eventId/promo-codes'),
        (d) => (d as List).map((x) => PromoCodeInfo.fromJson(x as Map<String, dynamic>)).toList(),
      );

  Future<void> createPromoCode(String orgId, String eventId, {required String code, required String kind, required int value, int? maxUses}) => _call(
        () => _dio.post('/organizations/$orgId/events/$eventId/promo-codes', data: {'code': code, 'kind': kind, 'value': value, if (maxUses != null) 'maxUses': maxUses}),
        (_) {},
      );

  Future<void> setPromoActive(String orgId, String eventId, String promoId, bool active) =>
      _call(() => _dio.patch('/organizations/$orgId/events/$eventId/promo-codes/$promoId', data: {'isActive': active}), (_) {});

  // ───── Event night: attendees, seating, guest tickets, waitlist ─────

  Future<List<Attendee>> attendees(String orgId, String eventId) => _call(
        () => _dio.get('/organizations/$orgId/events/$eventId/attendees'),
        (d) => (d as List).map((x) => Attendee.fromJson(x as Map<String, dynamic>)).toList(),
      );

  Future<OrgSeating> orgSeating(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/seating'), (d) => OrgSeating.fromJson(d as Map<String, dynamic>));

  Future<List<GuestTicket>> guestTickets(String orgId, String eventId) => _call(
        () => _dio.get('/organizations/$orgId/events/$eventId/seating/guests'),
        (d) => (d as List).map((x) => GuestTicket.fromJson(x as Map<String, dynamic>)).toList(),
      );

  /// Like [_call], but a 409 carrying `takenSeats` becomes [SeatsChanged].
  Future<T> _seatsCall<T>(Future<Response<dynamic>> Function() send, T Function(dynamic data) parse) async {
    try {
      return await _call(send, parse);
    } on ApiException catch (e) {
      if (e.status == 409 && e.takenSeats.isNotEmpty) throw SeatsChanged(e.message, e.takenSeats, reasonCode: e.reasonCode);
      rethrow;
    }
  }

  Future<int> holdSeats(String orgId, String eventId, List<String> seats, String label) => _seatsCall(
        () => _dio.post('/organizations/$orgId/events/$eventId/seating/hold', data: {'seats': seats, 'label': label}),
        (d) => ((d as Map<String, dynamic>)['held'] as num).toInt(),
      );

  Future<int> releaseSeats(String orgId, String eventId, List<String> seats) => _seatsCall(
        () => _dio.post('/organizations/$orgId/events/$eventId/seating/release', data: {'seats': seats}),
        (d) => ((d as Map<String, dynamic>)['released'] as num).toInt(),
      );

  /// Issues complimentary tickets for [seats]; returns how many were issued.
  Future<int> issueGuestTickets(String orgId, String eventId, List<String> seats, {required String guestName, required String phone, String? label}) => _seatsCall(
        () => _dio.post('/organizations/$orgId/events/$eventId/seating/comps', data: {
          'seats': seats,
          'guestName': guestName,
          'phone': phone,
          if (label != null && label.isNotEmpty) 'label': label,
        }),
        (d) => ((d as Map<String, dynamic>)['tickets'] as List).length,
      );

  Future<void> revokeGuestTicket(String orgId, String eventId, String ticketId) =>
      _call(() => _dio.post('/organizations/$orgId/events/$eventId/seating/comps/$ticketId/revoke'), (_) {});

  Future<WaitlistCounts> waitlistCounts(String orgId, String eventId) =>
      _call(() => _dio.get('/organizations/$orgId/events/$eventId/waitlist'), (d) => WaitlistCounts.fromJson(d as Map<String, dynamic>));

  Future<Inbox> organizerNotifications() =>
      _call(() => _dio.get('/me/notifications', queryParameters: {'audience': 'organizer'}), (d) => Inbox.fromJson(d as Map<String, dynamic>));

  Future<void> markOrganizerNotificationsRead([List<String> ids = const []]) =>
      _call(() => _dio.post('/me/notifications/read', data: ids.isEmpty ? {'audience': 'organizer'} : {'ids': ids}), (_) {});
}

/// Result of a token refresh: done, rejected by the server, or transient ([failure] says what went wrong).
class _Refresh {
  const _Refresh.ok()
      : ok = true,
        failure = null;
  const _Refresh.rejected()
      : ok = false,
        failure = null;
  const _Refresh.transient(DioException this.failure) : ok = false;
  final bool ok;
  final DioException? failure;
}
