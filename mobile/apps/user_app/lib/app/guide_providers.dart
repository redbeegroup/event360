import 'package:event360_core/event360_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'providers.dart';

/// [KeyValueStore] over SharedPreferences, for the offline event cache.
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this.prefs);
  final SharedPreferences prefs;

  @override
  String? getString(String key) => prefs.getString(key);
  @override
  Future<void> setString(String key, String value) => prefs.setString(key, value);
  @override
  Future<void> remove(String key) => prefs.remove(key);
  @override
  Iterable<String> keys() => prefs.getKeys();
}

/// Saved copies of the events the buyer holds tickets for (next to the ticket cache).
final eventCacheProvider = Provider<EventCache>((ref) => EventCache(PrefsKeyValueStore(ref.watch(prefsProvider)), now: () => ref.read(nowProvider)()));

/// What the guide shows: the event and its announcements, live or from the saved copy.
@immutable
class GuideData {
  const GuideData({required this.event, this.announcements = const [], this.savedAt, this.neverSaved = false});

  /// Null only when [neverSaved].
  final EventSummary? event;
  final List<EventAnnouncement> announcements;

  /// Non-null when this came from the saved copy (the network was down); the time it was saved.
  final DateTime? savedAt;

  /// The network was down and no copy of this event was ever saved.
  final bool neverSaved;

  bool get offline => savedAt != null || neverSaved;
}

/// Loads the guide's event data. On success the saved copy is refreshed; with no network the saved copy (or `neverSaved`) is returned.
/// Announcements that are refused (403) or missing (404) leave the live event without announcements; other errors are errors.
final guideProvider = FutureProvider.autoDispose.family<GuideData, String>(
  (ref, id) async {
    final api = ref.watch(apiProvider);
    final cache = ref.watch(eventCacheProvider);

    GuideData fromSaved() {
      final saved = cache.read(id);
      if (saved == null) return const GuideData(event: null, neverSaved: true);
      return GuideData(event: EventSummary.fromJson(saved.event), announcements: saved.announcements, savedAt: saved.savedAt);
    }

    final Map<String, dynamic> raw;
    try {
      raw = await api.eventRaw(id);
    } on ApiException catch (e) {
      if (e.isNetwork) return fromSaved();
      rethrow;
    }
    final event = EventSummary.fromJson(raw);
    var announcements = const <EventAnnouncement>[];
    try {
      announcements = await api.eventAnnouncements(id);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Half a connection: the saved copy keeps its label; with none, the live event is shown without announcements.
        if (cache.read(id) != null) return fromSaved();
        return GuideData(event: event);
      }
      if (!e.isForbidden && !e.isNotFound) rethrow;
    }
    // Only while signed in: a fetch that finishes after sign-out must not leave a copy behind.
    if (ref.read(sessionProvider).value != null) {
      try {
        await cache.write(id, raw, announcements);
      } catch (_) {} // a full or failing disk must not hide the live guide
    }
    return GuideData(event: event, announcements: announcements);
  },
  retry: (_, __) => null,
);

/// What the viewer may do on `/event/:id/guide`.
enum GuideAccess { loading, error, signedOut, noTicket, allowed }

/// The viewer's tickets that open the guide: VALID or CHECKED_IN for this event (id or slug), from the live list or the saved copy of it.
bool isUsableTicket(MyTicket t, String idOrSlug) => (t.status == 'VALID' || t.status == 'CHECKED_IN') && (t.eventId == idOrSlug || t.eventSlug == idOrSlug);

({GuideAccess access, List<MyTicket> tickets}) guideAccessOf({required AsyncValue<Me?> session, required AsyncValue<List<MyTicket>> tickets, required String idOrSlug}) {
  if (session.isLoading && !session.hasValue) return (access: GuideAccess.loading, tickets: const []);
  if (session.hasValue && session.value == null) return (access: GuideAccess.signedOut, tickets: const []);
  if (session.hasError && !session.hasValue) return (access: GuideAccess.error, tickets: const []);
  if (tickets.hasError && !tickets.hasValue) return (access: GuideAccess.error, tickets: const []);
  if (!tickets.hasValue) return (access: GuideAccess.loading, tickets: const []);
  final usable = tickets.value!.where((t) => isUsableTicket(t, idOrSlug)).toList();
  return (access: usable.isEmpty ? GuideAccess.noTicket : GuideAccess.allowed, tickets: usable);
}

/// Live sessions and recordings for the guide's Watch buttons; null when they can't be loaded (offline, or none).
final guideStreamsProvider = FutureProvider.autoDispose.family<EventStreams?, String>((ref, id) async {
  try {
    return await ref.watch(apiProvider).eventStreams(id);
  } on ApiException {
    return null;
  }
});

/// Opens a link outside the app (maps). Tests override it. False when nothing could open it.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>((ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

/// Where the Directions button goes: the venue's map pin, else the organizer's map link, else a search for the name.
Uri guideDirectionsUri(Venue v) {
  if (v.latitude != null && v.longitude != null) {
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=${v.latitude},${v.longitude}');
  }
  if (v.mapUrl != null && v.mapUrl!.isNotEmpty) return Uri.parse(v.mapUrl!);
  return Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([v.name, v.address, v.city].whereType<String>().join(', '))}');
}
