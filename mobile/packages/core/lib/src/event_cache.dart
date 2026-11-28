/// Offline copy of the events a buyer holds tickets for (guide screens read it when the network is down).
library;

import 'dart:convert';

import 'models.dart';

/// The slice of key-value storage the cache needs; the app adapts SharedPreferences to it.
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Iterable<String> keys();
}

class SavedEvent {
  const SavedEvent({required this.event, required this.announcements, required this.savedAt});
  final Map<String, dynamic> event;
  final List<EventAnnouncement> announcements;
  final DateTime savedAt;
}

class EventCache {
  EventCache(this.store, {DateTime Function()? now}) : _now = now ?? (() => DateTime.now().toUtc());
  final KeyValueStore store;
  final DateTime Function() _now;

  static const prefix = 'event_cache_v1_';
  static const maxEvents = 10;

  SavedEvent? read(String eventId) => _parse(store.getString('$prefix$eventId'));

  Future<void> write(String eventId, Map<String, dynamic> event, List<EventAnnouncement> announcements) => store.setString(
        '$prefix$eventId',
        jsonEncode({
          'savedAt': _now().toUtc().toIso8601String(),
          'event': event,
          'announcements': announcements.map((a) => a.toJson()).toList(),
        }),
      );

  /// Sign-out: forget every cached event (other keys are left alone).
  Future<void> clearAll() async {
    for (final k in _cacheKeys()) {
      await store.remove(k);
    }
  }

  /// An entry whose event JSON has no parsable `endsAt` is never treated as ended: it is kept if it is in the keep set (and within the cap).
  /// Keeps only events in [keepEventIds] that ended at most 7 days ago (and unreadable entries go), at most [maxEvents], newest save first.
  Future<void> prune({required Set<String> keepEventIds}) async {
    final now = _now().toUtc();
    final kept = <String, DateTime>{};
    for (final k in _cacheKeys()) {
      final id = k.substring(prefix.length);
      final saved = _parse(store.getString(k));
      final ends = saved == null ? null : DateTime.tryParse('${saved.event['endsAt']}');
      final stale = ends != null && now.isAfter(ends.toUtc().add(const Duration(days: 7)));
      if (saved == null || !keepEventIds.contains(id) || stale) {
        await store.remove(k);
      } else {
        kept[k] = saved.savedAt;
      }
    }
    if (kept.length > maxEvents) {
      // Equal save times fall back to the key so the result is deterministic.
      final oldestFirst = kept.keys.toList()
        ..sort((a, b) {
          final c = kept[a]!.compareTo(kept[b]!);
          return c != 0 ? c : a.compareTo(b);
        });
      for (final k in oldestFirst.take(kept.length - maxEvents)) {
        await store.remove(k);
      }
    }
  }

  List<String> _cacheKeys() => store.keys().where((k) => k.startsWith(prefix)).toList();

  SavedEvent? _parse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SavedEvent(
        event: j['event'] as Map<String, dynamic>,
        announcements: ((j['announcements'] as List?) ?? const []).map((a) => EventAnnouncement.fromJson(a as Map<String, dynamic>)).toList(),
        savedAt: DateTime.parse(j['savedAt'] as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}
