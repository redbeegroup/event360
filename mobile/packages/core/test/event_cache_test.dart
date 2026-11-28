import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

class MemStore implements KeyValueStore {
  final m = <String, String>{};
  @override
  String? getString(String key) => m[key];
  @override
  Future<void> setString(String key, String value) async => m[key] = value;
  @override
  Future<void> remove(String key) async => m.remove(key);
  @override
  Iterable<String> keys() => m.keys.toList();
}

void main() {
  final now = DateTime.utc(2027, 2, 1, 12);
  late MemStore store;
  late DateTime clock;
  late EventCache cache;
  setUp(() {
    store = MemStore();
    clock = now;
    cache = EventCache(store, now: () => clock);
  });

  Map<String, dynamic> ev(DateTime ends) => {'id': 'x', 'endsAt': ends.toIso8601String()};

  test('write then read round trip', () async {
    final a = EventAnnouncement(id: 'a', title: 'T', body: 'B', createdAt: DateTime.utc(2027, 1, 1));
    await cache.write('e1', ev(now), [a]);
    final s = cache.read('e1')!;
    expect(s.event['id'], 'x');
    expect(s.announcements.single.title, 'T');
    expect(s.savedAt, now);
  });

  test('missing and unreadable entries read as null', () {
    expect(cache.read('nope'), isNull);
    store.m['${EventCache.prefix}bad'] = '{not json';
    expect(cache.read('bad'), isNull);
    store.m['${EventCache.prefix}wrong'] = jsonEncode([1, 2]);
    expect(cache.read('wrong'), isNull);
  });

  test('clearAll removes only prefixed keys', () async {
    await cache.write('e1', ev(now), []);
    await cache.write('e2', ev(now), []);
    store.m['my_tickets_cache_v1'] = 'keep';
    await cache.clearAll();
    expect(store.m.keys, ['my_tickets_cache_v1']);
  });

  test('prune drops events ended more than 7 days ago, keeps 6 days', () async {
    await cache.write('old', ev(now.subtract(const Duration(days: 8))), []);
    await cache.write('recent', ev(now.subtract(const Duration(days: 6))), []);
    await cache.prune(keepEventIds: {'old', 'recent'});
    expect(cache.read('old'), isNull);
    expect(cache.read('recent'), isNotNull);
  });

  test('prune keeps only the given ids and drops unreadable entries', () async {
    await cache.write('a', ev(now.add(const Duration(days: 1))), []);
    await cache.write('b', ev(now.add(const Duration(days: 1))), []);
    store.m['${EventCache.prefix}bad'] = 'zzz';
    await cache.prune(keepEventIds: {'a', 'bad'});
    expect(cache.read('a'), isNotNull);
    expect(cache.read('b'), isNull);
    expect(store.m.containsKey('${EventCache.prefix}bad'), isFalse);
  });

  test('prune caps at 10 by most recent save', () async {
    final ids = [for (var i = 0; i < 12; i++) 'e$i'];
    for (var i = 0; i < ids.length; i++) {
      clock = now.add(Duration(minutes: i));
      await cache.write(ids[i], ev(now.add(const Duration(days: 1))), []);
    }
    await cache.prune(keepEventIds: ids.toSet());
    expect(cache.read('e0'), isNull);
    expect(cache.read('e1'), isNull);
    for (var i = 2; i < 12; i++) {
      expect(cache.read('e$i'), isNotNull, reason: 'e$i');
    }
  });
}
