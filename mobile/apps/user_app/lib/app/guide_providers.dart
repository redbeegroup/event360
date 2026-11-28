import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
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

// ───── Happening today, and saving upcoming events for offline ─────

/// One ticket per event the signed-in buyer can open the guide for (usable ticket) that is on today ([isEventToday]), earliest start first.
/// Cancelled events are left out: nothing is "happening". Empty when signed out. Watching it also keeps [eventSaverProvider] alive.
final todayEventsProvider = Provider<List<MyTicket>>((ref) {
  ref.watch(eventSaverProvider);
  if (ref.watch(sessionProvider).value == null) return const [];
  final tickets = ref.watch(myTicketsProvider).value ?? const <MyTicket>[];
  final now = ref.read(nowProvider)();
  final byEvent = <String, MyTicket>{};
  for (final t in tickets) {
    if (t.status != 'VALID' && t.status != 'CHECKED_IN') continue;
    if (t.eventStatus == 'CANCELLED') continue;
    if (!isEventToday(startsAt: t.startsAt, endsAt: t.endsAt, now: now)) continue;
    byEvent.putIfAbsent(t.eventId, () => t);
  }
  final out = byEvent.values.toList()
    ..sort((a, b) {
      final c = a.startsAt.compareTo(b.startsAt);
      return c != 0 ? c : a.eventId.compareTo(b.eventId);
    });
  return out;
});

/// Saves up to [EventCache.maxEvents] upcoming events (with announcements) to the phone after the tickets load online.
class EventSaver {
  EventSaver(this._ref);
  final Ref _ref;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// An event saved less than this long ago is not fetched again.
  static const fresh = Duration(hours: 1);

  /// Never throws. A call while a run is in flight asks for one more run after it, so runs never overlap.
  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _once();
      } while (_again && !_disposed);
    } catch (_) {
      // Saving is a convenience; nothing here may reach the Tickets tab.
    } finally {
      _running = false;
    }
  }

  bool get _signedIn => !_disposed && _ref.read(sessionProvider).value != null;

  Future<void> _once() async {
    if (kIsWeb || !_signedIn) return; // the web build is online only
    final notifier = _ref.read(myTicketsProvider.notifier);
    final tickets = _ref.read(myTicketsProvider).value;
    if (tickets == null || notifier.fromCache) return;
    final now = _ref.read(nowProvider)();
    final usable = tickets.where((t) => t.status == 'VALID' || t.status == 'CHECKED_IN').toList();
    final upcoming = <String, MyTicket>{};
    for (final t in usable) {
      if (t.endsAt.isAfter(now)) upcoming.putIfAbsent(t.eventId, () => t);
    }
    final order = upcoming.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final cache = _ref.read(eventCacheProvider);
    final api = _ref.read(apiProvider);
    for (final t in order.take(EventCache.maxEvents)) {
      if (!_signedIn) return;
      try {
        final saved = cache.read(t.eventId);
        if (saved != null && now.difference(saved.savedAt) < fresh) continue;
        final raw = await api.eventRaw(t.eventId);
        var announcements = const <EventAnnouncement>[];
        try {
          announcements = await api.eventAnnouncements(t.eventId);
        } on ApiException catch (e) {
          if (!e.isForbidden && !e.isNotFound) rethrow;
        }
        if (!_signedIn) return; // signed out while this was loading: leave nothing behind
        await cache.write(t.eventId, raw, announcements);
      } catch (_) {} // one event failing must not stop the others
    }
    if (!_signedIn) return;
    try {
      await cache.prune(keepEventIds: usable.map((t) => t.eventId).toSet());
    } catch (_) {}
    if (!_disposed && _ref.read(sessionProvider).value == null) await cache.clearAll();
  }
}

/// Starts [EventSaver.run] (after the next frame) each time the ticket list finishes loading. Watched by [todayEventsProvider].
final eventSaverProvider = Provider<EventSaver>((ref) {
  final saver = EventSaver(ref);
  ref.onDispose(() => saver._disposed = true);
  void schedule() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!saver._disposed) unawaited(saver.run());
    });
    binding.scheduleFrame();
  }

  ref.listen<AsyncValue<List<MyTicket>>>(myTicketsProvider, (prev, next) {
    if (next is AsyncData<List<MyTicket>> && !next.isLoading && !identical(prev?.value, next.value)) schedule();
  }, fireImmediately: true);
  return saver;
});
