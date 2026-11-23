import 'package:dio/dio.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// An API whose every request fails with [status] and [body].
Event360Api failingApi(int status, Object? body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example/v1'))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) => h.reject(DioException(requestOptions: o, response: Response(requestOptions: o, statusCode: status, data: body))),
    ));
  return Event360Api(const AppConfig(app: Event360App.user, apiBaseUrl: 'https://api.example'), MemoryTokenStore(), dio: dio);
}

/// Answers every request with [status]; [paths] collects what was asked.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, this.paths);
  final int status;
  final List<String> paths;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    return ResponseBody.fromString('{"message":"nope"}', status, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

/// Scripted server: [handle] answers each request (status + json body) or throws a DioException (a dropped connection).
class _ScriptAdapter implements HttpClientAdapter {
  _ScriptAdapter(this.handle);
  final (int, String) Function(RequestOptions o) handle;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    paths.add(options.path);
    final (status, body) = handle(options);
    return ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('token refresh outcomes', () {
    ({Event360Api api, _ScriptAdapter ad, MemoryTokenStore store, List<int> ended}) setup((int, String) Function(RequestOptions) refresh) {
      final store = MemoryTokenStore()..save('old', 'rt');
      var fresh = false;
      final ad = _ScriptAdapter((o) {
        if (o.path == '/auth/refresh') {
          final r = refresh(o);
          if (r.$1 == 200) fresh = true;
          return r;
        }
        final auth = o.headers['Authorization'];
        return fresh && auth == 'Bearer new' ? (200, '{"id":"u","phone":"0","organizations":[]}') : (401, '{"message":"x"}');
      });
      final api = Event360Api(const AppConfig(app: Event360App.organizer, apiBaseUrl: 'https://api.example'), store,
          dio: Dio(BaseOptions(baseUrl: 'https://api.example/v1'))..httpClientAdapter = ad);
      final ended = <int>[];
      api.onSessionExpired = () => ended.add(1);
      return (api: api, ad: ad, store: store, ended: ended);
    }

    const ok = (200, '{"accessToken":"new","refreshToken":"rt2"}');

    test('a dropped connection during refresh keeps the session and fails as a network error', () async {
      var drop = true;
      final h = setup((o) => drop ? throw DioException.connectionError(requestOptions: o, reason: 'offline') : ok);
      await expectLater(h.api.myOrganizations(), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
      expect(h.ended, isEmpty);
      expect(await h.store.accessToken(), 'old');
      expect(await h.store.refreshToken(), 'rt');
      // a later request refreshes successfully
      drop = false;
      await h.api.myOrganizations();
      expect(await h.store.accessToken(), 'new');
      expect(h.ended, isEmpty);
    });

    test('a 5xx from refresh keeps the session', () async {
      final h = setup((o) => (503, '{"message":"down"}'));
      await expectLater(h.api.myOrganizations(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 503)));
      expect(h.ended, isEmpty);
      expect(await h.store.refreshToken(), 'rt');
    });

    test('a refresh the server rejects (400, 401, 403) clears the tokens and ends the session once', () async {
      for (final code in [400, 401, 403]) {
        final h = setup((o) => (code, '{"message":"no"}'));
        await expectLater(h.api.myOrganizations(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
        expect(h.ended.length, 1, reason: '$code');
        expect(await h.store.accessToken(), isNull, reason: '$code');
      }
    });

    test('parallel 401s share one refresh', () async {
      final h = setup((o) => ok);
      await Future.wait([h.api.myOrganizations(), h.api.myOrganizations(), h.api.myOrganizations()]);
      expect(h.ad.paths.where((p) => p == '/auth/refresh').length, 1);
      expect(h.ended, isEmpty);
    });
  });

  group('onSessionExpired', () {
    Event360Api apiWith(int status, MemoryTokenStore store, List<String> paths) => Event360Api(
        const AppConfig(app: Event360App.organizer, apiBaseUrl: 'https://api.example'), store,
        dio: Dio(BaseOptions(baseUrl: 'https://api.example/v1'))..httpClientAdapter = _StatusAdapter(status, paths));

    test('a 401 that survives the refresh calls the hook once and clears the tokens', () async {
      final store = MemoryTokenStore()..save('a', 'r');
      final paths = <String>[];
      var ended = 0;
      final api = apiWith(401, store, paths)..onSessionExpired = () => ended++;
      await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
      expect(ended, 1);
      expect(paths, ['/auth/me', '/auth/refresh']);
      expect(await store.accessToken(), isNull);
    });

    test('a failed sign-in (no session) does not call the hook', () async {
      final api = apiWith(401, MemoryTokenStore(), <String>[]);
      var ended = 0;
      api.onSessionExpired = () => ended++;
      await expectLater(api.passwordLogin('a@b.c', 'x'), throwsA(isA<ApiException>()));
      expect(ended, 0);
    });

    test('other errors do not call the hook', () async {
      final store = MemoryTokenStore()..save('a', 'r');
      final api = apiWith(403, store, <String>[]);
      var ended = 0;
      api.onSessionExpired = () => ended++;
      await expectLater(api.me(), throwsA(isA<ApiException>().having((e) => e.isForbidden, '403', true)));
      expect(ended, 0);
    });
  });

  test('SeatsChanged carries the reasonCode', () async {
    final api = failingApi(409, {'message': 'Some seats are no longer available', 'reasonCode': 'SEATS_NOT_AVAILABLE', 'takenSeats': ['A:1:1']});
    await expectLater(api.holdSeats('o', 'e', ['A:1:1'], 'x'), throwsA(isA<SeatsChanged>().having((e) => e.reasonCode, 'reasonCode', 'SEATS_NOT_AVAILABLE')));
  });

  test('ApiException carries reasonCode from the error body', () async {
    final api = failingApi(400, {'message': 'This code has been used up', 'reasonCode': 'USED_UP'});
    await expectLater(
      api.createOrder('e1', {'tt': 1}, idempotencyKey: 'k', promoCode: 'X'),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 400)
          .having((e) => e.message, 'message', 'This code has been used up')
          .having((e) => e.reasonCode, 'reasonCode', 'USED_UP')),
    );
  });

  test('ApiException has no reasonCode when the body has none', () async {
    final api = failingApi(409, {'message': 'Some seats were just taken', 'takenSeats': ['A:1:1']});
    await expectLater(
      api.createOrder('e1', const {}, idempotencyKey: 'k', seats: ['A:1:1']),
      throwsA(isA<ApiException>().having((e) => e.reasonCode, 'reasonCode', isNull).having((e) => e.takenSeats, 'takenSeats', ['A:1:1'])),
    );
  });

  test('WaitlistEntry: an OFFERED entry is a live offer whatever its orderId; an expired one is not', () {
    Map<String, dynamic> row(String status, Duration left, {String? orderId}) => {
          'id': 'w1',
          'ticketTypeId': 'tt',
          'eventId': 'e1',
          'status': status,
          'quantity': 2,
          'position': null,
          'offeredQty': 2,
          'offerExpiresAt': DateTime.now().toUtc().add(left).toIso8601String(),
          'seatKeys': ['A:1:1', 'A:1:2'],
          'orderId': orderId,
          'event': {'id': 'e1', 'slug': 's', 'title': 'T', 'titleMy': null},
          'ticketType': {'id': 'tt', 'name': 'General', 'nameMy': null},
        };
    final reopened = WaitlistEntry.fromJson(row('OFFERED', const Duration(minutes: 5), orderId: 'old'));
    expect(reopened.isOffered, isTrue);
    expect(reopened.isSeated, isTrue);
    expect(reopened.seatKeys, ['A:1:1', 'A:1:2']);
    expect(WaitlistEntry.fromJson(row('OFFERED', const Duration(minutes: -1))).isOffered, isFalse);
    expect(WaitlistEntry.fromJson(row('PURCHASED', const Duration(minutes: 5))).isOffered, isFalse);
    expect(WaitlistEntry.fromJson(row('WAITING', Duration.zero)).isWaiting, isTrue);
  });

  test('WaitlistEntry counts the offer down on the server clock', () {
    final now = DateTime.now().toUtc();
    final e = WaitlistEntry.fromJson({
      'id': 'w1',
      'ticketTypeId': 'tt',
      'eventId': 'e1',
      'status': 'OFFERED',
      'quantity': 1,
      'serverNow': now.subtract(const Duration(hours: 1)).toIso8601String(), // the phone is an hour ahead
      'offerExpiresAt': now.subtract(const Duration(minutes: 55)).toIso8601String(),
    });
    expect(e.isOffered, isTrue);
    expect(e.offerExpiresAt!.difference(e.serverNow).inMinutes, inInclusiveRange(4, 5));
  });
}
