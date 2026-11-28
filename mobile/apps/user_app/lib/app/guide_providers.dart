import 'dart:async';
import 'dart:collection' show ListBase;

import 'package:event360_core/event360_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'providers.dart';

export 'providers.dart' show eventCacheProvider, PrefsKeyValueStore;

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

/// The saved copy for an event id or slug (the URL may carry either): the entry keyed by that id, else the one whose event has that slug.
/// Returns the id it is saved under, so the entry can be removed. An unreadable entry is removed and counts as not saved.
Future<({String id, SavedEvent saved})?> findSavedEvent(EventCache cache, String idOrSlug) async {
  Future<({String id, SavedEvent saved})?> usable(String id) async {
    final saved = cache.read(id);
    if (saved == null) return null;
    try {
      EventSummary.fromJson(saved.event);
      return (id: id, saved: saved);
    } catch (_) {
      await cache.store.remove('${EventCache.prefix}$id'); // parses as JSON but is not an event: drop it
      return null;
    }
  }

  final direct = await usable(idOrSlug);
  if (direct != null) return direct;
  for (final k in cache.store.keys().where((k) => k.startsWith(EventCache.prefix)).toList()) {
    final id = k.substring(EventCache.prefix.length);
    if (cache.read(id)?.event['slug'] == idOrSlug) return usable(id);
  }
  return null;
}

/// Loads the guide's event data. On success the saved copy is refreshed (under the event's real id, whatever the URL carried); with no
/// network the saved copy (or `neverSaved`) is returned. Announcements that are refused (401, 403) or missing (404) leave the live event without
/// announcements (and without stale saved ones); other errors are errors.
final guideProvider = FutureProvider.autoDispose.family<GuideData, String>(
  (ref, idOrSlug) async {
    final api = ref.watch(apiProvider);
    final cache = ref.watch(eventCacheProvider);

    Future<GuideData> fromSaved() async {
      final found = await findSavedEvent(cache, idOrSlug);
      if (found == null) return const GuideData(event: null, neverSaved: true);
      return GuideData(event: EventSummary.fromJson(found.saved.event), announcements: found.saved.announcements, savedAt: found.saved.savedAt);
    }

    final Map<String, dynamic> raw;
    try {
      raw = await api.eventRaw(idOrSlug);
    } on ApiException catch (e) {
      if (e.isNotFound) rethrow; // the event is gone: a copy of it would be a lie
      if (e.isNetwork) {
        if (kIsWeb) rethrow; // the web build keeps and serves no copies
        return fromSaved();
      }
      // A server error: the saved copy (labelled) is better than an error page, when there is one.
      if (!kIsWeb && (await findSavedEvent(cache, idOrSlug)) != null) return fromSaved();
      rethrow;
    }
    final event = EventSummary.fromJson(raw);
    var announcements = const <EventAnnouncement>[];
    try {
      announcements = await api.eventAnnouncements(event.id); // the server needs the real id, not a slug
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // Half a connection: the saved copy keeps its label; with none, the live event is shown without announcements.
        if (!kIsWeb && (await findSavedEvent(cache, event.id)) != null) return fromSaved();
        return GuideData(event: event);
      }
      if (!e.isForbidden && !e.isNotFound && !e.isUnauthorized) rethrow;
    }
    // Only while signed in: a fetch that finishes after sign-out must not leave a copy behind.
    if (!kIsWeb && ref.read(sessionProvider).value != null) {
      try {
        await cache.write(event.id, raw, announcements);
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

/// [ticketsOwner] is the user id the ticket list belongs to ([MyTicketsNotifier.owner]): a list that is not the current session's (or
/// is still being reloaded for a new session) is never trusted. A refresh for the same user, and the offline copy of their list, are.
({GuideAccess access, List<MyTicket> tickets}) guideAccessOf({
  required AsyncValue<Me?> session,
  required AsyncValue<List<MyTicket>> tickets,
  required String idOrSlug,
  required String? ticketsOwner,
}) {
  if (session.isLoading) return (access: GuideAccess.loading, tickets: const []);
  if (session.hasValue && session.value == null) return (access: GuideAccess.signedOut, tickets: const []);
  if (session.hasError && !session.hasValue) return (access: GuideAccess.error, tickets: const []);
  if (tickets.hasError && !tickets.hasValue) return (access: GuideAccess.error, tickets: const []);
  if (!tickets.hasValue) return (access: GuideAccess.loading, tickets: const []);
  if (ticketsOwner == null || ticketsOwner != session.value?.id) return (access: GuideAccess.loading, tickets: const []);
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
/// Cancelled events are left out: nothing is "happening". Empty when signed out. Recomputed every minute (and when the app resumes, see
/// `GuideBackground`), so the card appears at midnight and goes when the event ends without a ticket reload.
final todayEventsProvider = Provider.autoDispose<List<MyTicket>>((ref) {
  final timer = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  if (ref.watch(sessionProvider).value == null) return _TodayEvents(const []);
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
  return _TodayEvents(out);
});

/// The list [todayEventsProvider] hands out. Two lists are equal when they hold the same events (and tickets) in the same order, so the provider (which
/// recomputes every minute) only notifies Home and Tickets when the set of today events (or the ticket shown for one) really changes.
class _TodayEvents extends ListBase<MyTicket> {
  _TodayEvents(this._items);
  final List<MyTicket> _items;

  @override
  int get length => _items.length;
  @override
  set length(int _) => throw UnsupportedError('read only');
  @override
  MyTicket operator [](int index) => _items[index];
  @override
  void operator []=(int index, MyTicket value) => throw UnsupportedError('read only');

  @override
  bool operator ==(Object other) {
    if (other is! _TodayEvents || other.length != length) return false;
    for (var i = 0; i < length; i++) {
      final a = other._items[i], b = _items[i];
      if (a.eventId != b.eventId || a.id != b.id || a.status != b.status || a.eventStatus != b.eventStatus) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_items.map((t) => Object.hash(t.eventId, t.id, t.status, t.eventStatus)));
}

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

  /// Events the server said do not exist (404): not asked again this app session.
  final _gone = <String>{};

  Future<void> _once() async {
    if (kIsWeb) return; // the web build is online only
    // Wait for the next pass while the session or the ticket list is reloading: they may belong to someone else by the time they settle.
    if (_disposed || _ref.read(sessionProvider).isLoading || _ref.read(myTicketsProvider).isLoading) return;
    final notifier = _ref.read(myTicketsProvider.notifier);
    final tickets = _ref.read(myTicketsProvider).value;
    final owner = notifier.owner;
    if (tickets == null || owner == null || notifier.fromCache) return;
    // Still the same signed-in user, with nothing reloading. Checked after every await.
    bool same() {
      if (_disposed) return false;
      final session = _ref.read(sessionProvider);
      return !session.isLoading && session.value?.id == owner && _ref.read(myTicketsProvider.notifier).owner == owner && !_ref.read(myTicketsProvider).isLoading;
    }

    if (!same()) return;
    final now = _ref.read(nowProvider)();
    final usable = tickets.where((t) => t.status == 'VALID' || t.status == 'CHECKED_IN').toList();
    final upcoming = <String, MyTicket>{};
    for (final t in usable) {
      if (t.endsAt.isAfter(now)) upcoming.putIfAbsent(t.eventId, () => t);
    }
    final order = upcoming.values.where((t) => !_gone.contains(t.eventId)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final cache = _ref.read(eventCacheProvider);
    final api = _ref.read(apiProvider);
    for (final t in order.take(EventCache.maxEvents)) {
      if (!same()) return;
      try {
        final saved = cache.read(t.eventId);
        if (saved != null && now.difference(saved.savedAt).abs() < fresh) continue; // abs: the phone clock may have moved back
        final Map<String, dynamic> raw;
        try {
          raw = await api.eventRaw(t.eventId);
        } on ApiException catch (e) {
          if (e.isNotFound) _gone.add(t.eventId);
          rethrow;
        }
        if (!same()) return;
        var announcements = const <EventAnnouncement>[];
        try {
          announcements = await api.eventAnnouncements(t.eventId);
        } on ApiException catch (e) {
          if (!e.isForbidden && !e.isNotFound) rethrow;
        }
        if (!same()) return; // signed out or switched while loading: nothing fetched for the previous user is written
        await cache.write(t.eventId, raw, announcements);
      } catch (_) {} // one event failing must not stop the others
    }
    if (!same()) return;
    try {
      await cache.prune(keepEventIds: usable.map((t) => t.eventId).toSet());
    } catch (_) {}
  }
}

/// Starts [EventSaver.run] (after the next frame) each time the ticket list finishes loading. Started by `GuideBackground` in the app shell.
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
