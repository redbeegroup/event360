import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where access/refresh tokens live. Secure storage on devices; an in-memory version for tests.
abstract class TokenStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> save(String access, String refresh);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  /// [prefix] keeps apps apart when they share storage (e.g. the user and crew web previews on one origin).
  SecureTokenStore([FlutterSecureStorage? storage, String prefix = 'e360']) : _s = storage ?? const FlutterSecureStorage(), _a = '${prefix}_access', _r = '${prefix}_refresh';
  final FlutterSecureStorage _s;
  final String _a;
  final String _r;

  @override
  Future<String?> accessToken() => _s.read(key: _a);
  @override
  Future<String?> refreshToken() => _s.read(key: _r);
  @override
  Future<void> save(String access, String refresh) async {
    await _s.write(key: _a, value: access);
    await _s.write(key: _r, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: _a);
    await _s.delete(key: _r);
  }
}

class MemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;
  @override
  Future<String?> accessToken() async => _access;
  @override
  Future<String?> refreshToken() async => _refresh;
  @override
  Future<void> save(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
