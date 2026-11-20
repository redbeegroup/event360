import 'package:dio/dio.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports each distinct error once, up to the per-session cap', () async {
    final sent = <Map<String, dynamic>>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        sent.add(Map<String, dynamic>.from(o.data as Map));
        h.resolve(Response(requestOptions: o, statusCode: 202));
      }));
    final r = ErrorReporter(const AppConfig(app: Event360App.crew, apiBaseUrl: 'https://api.example'), dio: dio, maxPerSession: 3);
    await r.report(StateError('boom'), StackTrace.current);
    await r.report(StateError('boom'), StackTrace.current);
    for (var i = 0; i < 5; i++) {
      await r.report(Exception('e$i'), null);
    }
    expect(sent, hasLength(3));
    expect(sent.first['source'], 'crew_app');
    expect(sent.first['message'], contains('boom'));
    expect(sent.first['stack'], isNotEmpty);
  });

  test('a failing endpoint never throws', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.reject(DioException(requestOptions: o))));
    final r = ErrorReporter(const AppConfig(app: Event360App.user, apiBaseUrl: 'https://api.example'), dio: dio);
    await r.report(Exception('x'), null);
  });
}
