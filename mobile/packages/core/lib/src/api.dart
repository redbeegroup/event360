import 'package:dio/dio.dart';

import 'app_config.dart';
import 'models.dart';
import 'token_store.dart';

/// Error with a user-presentable message from the API (`message` field) and the HTTP status.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int? status;
  final String message;

  bool get isRateLimited => status == 429;
  bool get isUnauthorized => status == 401;
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
        if (e.response?.statusCode == 401 && !retried && e.requestOptions.extra['auth'] != false && await _refresh()) {
          final opts = e.requestOptions..extra['retried'] = true;
          opts.headers['Authorization'] = 'Bearer ${await tokens.accessToken()}';
          try {
            return handler.resolve(await _dio.fetch(opts));
          } on DioException catch (e2) {
            return handler.next(e2);
          }
        }
        handler.next(e);
      },
    ));
  }

  final Dio _dio;
  final TokenStore tokens;
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= () async {
        try {
          final rt = await tokens.refreshToken();
          if (rt == null) return false;
          final r = await _dio.post<Map<String, dynamic>>('/auth/refresh',
              data: {'refreshToken': rt}, options: Options(extra: {'auth': false}));
          await tokens.save(r.data!['accessToken'] as String, r.data!['refreshToken'] as String);
          return true;
        } catch (_) {
          await tokens.clear();
          return false;
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
      throw ApiException(e.response?.statusCode, msg);
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

  Future<List<MyTicket>> myTickets() => _call(
        () => _dio.get('/me/tickets'),
        (d) => (d as List).map((t) => MyTicket.fromApi(t as Map<String, dynamic>)).toList(),
      );

  Future<String> ticketPublicKey() => _call(
        () => _dio.get('/meta/ticket-public-key', options: Options(extra: {'auth': false})),
        (d) => (d as Map<String, dynamic>)['publicKey'] as String,
      );
}
