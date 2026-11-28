import 'dart:convert';

/// The user id (`sub`) inside an access token, read without the network and without checking the signature (the server does that; this
/// only tells the app whose session the token belongs to). Null for anything that is not a token with a string `sub`.
String? userIdFromToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final sub = payload is Map ? payload['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}
