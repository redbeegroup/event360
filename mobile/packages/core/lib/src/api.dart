import 'package:dio/dio.dart';

import 'app_config.dart';

/// Thin API wrapper. Replaced by the generated OpenAPI client (`melos run gen:api`) in Phase 1.
class Event360Api {
  Event360Api(AppConfig config)
      : _dio = Dio(BaseOptions(baseUrl: '${config.apiBaseUrl}/v1', connectTimeout: const Duration(seconds: 10)));

  final Dio _dio;

  Future<List<Map<String, dynamic>>> categories() async {
    final res = await _dio.get<List<dynamic>>('/categories');
    return (res.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> requestOtp(String phone) async =>
      (await _dio.post<Map<String, dynamic>>('/auth/otp/request', data: {'phone': phone})).data!;

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async =>
      (await _dio.post<Map<String, dynamic>>('/auth/otp/verify', data: {'phone': phone, 'code': code})).data!;
}
