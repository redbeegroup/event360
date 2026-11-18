import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where access/refresh tokens live. Secure storage on devices; an in-memory version for tests.
abstract class TokenStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> save(String access, String refresh);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _a = 'e360_access';
  static const _r = 'e360_refresh';

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
