import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/token_user.dart';

String segment(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');

void main() {
  test('reads the sub claim of an access token', () {
    expect(userIdFromToken('${segment({'alg': 'HS256'})}.${segment({'sub': 'user-42', 'roles': []})}.c2ln'), 'user-42');
    // A payload whose base64 needs padding of each length.
    for (final id in ['a', 'ab', 'abc', 'abcd']) {
      expect(userIdFromToken('h.${segment({'sub': id})}.s'), id);
    }
  });

  test('anything else is null and never throws', () {
    for (final bad in [null, '', 'abc', 'a.b', 'a.b.c.d', 'a.!!!.c', 'a.${segment('text')}.c', 'a.${segment({'sub': 5})}.c', 'a.${segment({'sub': ''})}.c', 'a.${segment({'x': 1})}.c']) {
      expect(userIdFromToken(bad), isNull, reason: '$bad');
    }
  });
}
