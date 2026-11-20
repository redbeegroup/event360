import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'app_config.dart';

/// Sends uncaught Flutter and Dart errors to the API's error tracker (Admin → Operations).
///
/// At most [maxPerSession] reports per app run and one per distinct message, so a crash loop can't
/// flood the endpoint. Reporting never throws.
class ErrorReporter {
  ErrorReporter(this.config, {Dio? dio, this.maxPerSession = 20})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: config.apiBaseUrl, connectTimeout: const Duration(seconds: 5), sendTimeout: const Duration(seconds: 5)));

  final AppConfig config;
  final int maxPerSession;
  final Dio _dio;
  final Set<String> _seen = {};
  int _sent = 0;

  /// `--dart-define=APP_VERSION=<git sha>` (set by CI).
  static const release = String.fromEnvironment('APP_VERSION');

  String get source => switch (config.app) {
        Event360App.user => 'user_app',
        Event360App.crew => 'crew_app',
        Event360App.organizer => 'organizer_app',
      };

  /// Hooks Flutter's and the platform's error handlers (keeps the existing ones running too).
  void install() {
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutter?.call(details);
      unawaited(report(details.exception, details.stack, route: details.library));
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  Future<void> report(Object error, StackTrace? stack, {String? route}) async {
    final message = error.toString();
    if (_sent >= maxPerSession || !_seen.add(message)) return;
    _sent++;
    try {
      await _dio.post<void>('/v1/telemetry/errors', data: {
        'source': source,
        'message': message.length > 1000 ? message.substring(0, 1000) : message,
        if (stack != null) 'stack': _trim(stack.toString(), 8000),
        if (route != null) 'path': _trim(route, 300),
        if (release.isNotEmpty) 'release': _trim(release, 64),
        'context': {'platform': kIsWeb ? 'web' : defaultTargetPlatform.name, 'debug': kDebugMode},
      });
    } catch (_) {
      // reporting must never crash the app
    }
  }

  static String _trim(String s, int n) => s.length > n ? s.substring(0, n) : s;
}
