import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push.dart';
import 'token_user.dart';

/// Overridden in main() / tests.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider not overridden'));
final configProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment(Event360App.user));
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
final apiProvider = Provider<Event360Api>((ref) => Event360Api(ref.watch(configProvider), ref.watch(tokenStoreProvider)));

/// The clock (UTC). Tests override it to pin time.
final nowProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());

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

// ───── Language ─────

class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'lang';
  @override
  Locale? build() {
    final v = ref.watch(prefsProvider).getString(_key);
    return v == null ? null : Locale(v);
  }

  Future<void> set(String lang) async {
    await ref.read(prefsProvider).setString(_key, lang);
    state = Locale(lang);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

/// 'my' or 'en' — used to pick bilingual content fields.
final langProvider = Provider<String>((ref) => ref.watch(localeProvider)?.languageCode ?? 'my');

// ───── Session ─────

class SessionNotifier extends AsyncNotifier<Me?> {
  /// The id of the user whose session this phone last loaded online. It lets an offline cold start still tell whose tickets the cache holds.
  static const userIdKey = 'session_user_id_v1';

  /// Everything this phone keeps for the previous account: the offline tickets, the saved events and the remembered user id. Only a
  /// sign-out, or a different person signing in, removes it: a session that merely ended (a refresh that failed on a poor connection)
  /// keeps the copies, hidden, so the same buyer finds their tickets again at the door.
  Future<void> _forgetAccount() async {
    final prefs = ref.read(prefsProvider);
    try {
      await prefs.remove(MyTicketsNotifier.cacheKey);
      await prefs.remove(userIdKey);
      await ref.read(eventCacheProvider).clearAll();
    } catch (_) {} // nothing here may keep the app from starting
  }

  /// [id] is signed in (a cold start or `/auth/me` confirmed it). If the copies on this phone belong to somebody else (the stored id, or
  /// the owner tag of the ticket cache, says so) they are removed before anything reads them; then the id is remembered.
  Future<void> _adopt(String id) async {
    if (id.isEmpty) return;
    final prefs = ref.read(prefsProvider);
    final stored = prefs.getString(userIdKey);
    final owner = MyTicketsNotifier.ownerOf(prefs.getString(MyTicketsNotifier.cacheKey));
    final other = (stored != null && stored.isNotEmpty && stored != id) || (owner != null && owner.isNotEmpty && owner != id);
    if (other) await _forgetAccount();
    try {
      await prefs.setString(userIdKey, id);
    } catch (_) {}
  }

  /// A sign-in (not a cold start): whoever signed in must not inherit what is on the phone unless it is provably theirs. [id] is the
  /// user the server answered with, else the token's `sub`; unknown means nothing can be confirmed. Copies are removed when the stored id or
  /// the cache's owner is somebody else, when the cache cannot be attributed (an untagged list or an unknown owner with no stored id), or when
  /// [id] itself is unknown; then the id is stored. Runs before the session is rebuilt.
  Future<void> _adoptSignIn(String? id) async {
    final prefs = ref.read(prefsProvider);
    final stored = prefs.getString(userIdKey) ?? '';
    final raw = prefs.getString(MyTicketsNotifier.cacheKey);
    final owner = MyTicketsNotifier.ownerOf(raw);
    final mine = id != null && id.isNotEmpty;
    final theirs = !mine ||
        (stored.isNotEmpty && stored != id) ||
        (owner != null && owner.isNotEmpty && owner != id) ||
        (stored.isEmpty && raw != null && (owner == null || owner.isEmpty));
    if (theirs) await _forgetAccount();
    if (mine) {
      try {
        await prefs.setString(userIdKey, id);
      } catch (_) {}
    }
  }

  @override
  Future<Me?> build() async {
    final api = ref.watch(apiProvider);
    final prefs = ref.read(prefsProvider);
    final token = await api.tokens.accessToken();
    // No session: nothing is deleted (see _forgetAccount); the signed-out screens simply show nothing.
    if (token == null) return null;
    final tokenUser = userIdFromToken(token);
    try {
      final me = await api.me();
      await _adopt(me.id);
      return me;
    } on ApiException catch (e) {
      if (e.isUnauthorized) return null;
      // Offline: keep the user signed in (tickets work offline); profile details load later. Whose session this is comes from the token,
      // else from the id stored at the last sign-in (empty only for a phone that has never learned it: the cache is then trusted).
      final id = tokenUser ?? prefs.getString(userIdKey) ?? '';
      await _adopt(id);
      return Me(id: id, phone: null);
    }
  }

  /// Call after a successful sign-in with the user id of the verify response (the token's `sub` is used when it is null).
  Future<void> signedIn({String? userId}) async {
    final token = await ref.read(apiProvider).tokens.accessToken();
    await _adoptSignIn(userId ?? userIdFromToken(token));
    ref.invalidateSelf();
  }

  Future<void>? _signingOut;

  /// A second call while a sign-out is running joins it.
  Future<void> signOut() => _signingOut ??= _signOut().whenComplete(() => _signingOut = null);

  Future<void> _signOut() async {
    final api = ref.read(apiProvider);
    final prefs = ref.read(prefsProvider);
    const patience = Duration(seconds: 5);
    // Stop this phone getting the user's notifications (needs the session, so before logout). A dead network must not hold the sign-out.
    final token = prefs.getString(pushTokenKey);
    if (token != null) {
      try {
        await api.removeDevice(token).timeout(patience);
      } catch (_) {}
      try {
        await prefs.remove(pushTokenKey);
      } catch (_) {}
      try {
        await ref.read(pushProvider).deleteToken().timeout(patience);
      } catch (_) {}
    }
    try {
      await api.logout();
    } catch (_) {}
    // The session ends first: a ticket or event fetch that finishes from here on sees nobody signed in and writes nothing. Then the copies
    // go (myTicketsProvider watches this session, so it reloads empty; invalidating it from here is a circular dependency that trips a
    // debug assertion once the ticket list has been read).
    state = const AsyncData(null);
    await _forgetAccount();
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, Me?>(SessionNotifier.new);

// ───── Catalog & events ─────

final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(apiProvider).categories());

final upcomingProvider = FutureProvider<List<EventSummary>>((ref) async => (await ref.watch(apiProvider).events(limit: 20)).items);

final freeEventsProvider = FutureProvider<List<EventSummary>>((ref) async => (await ref.watch(apiProvider).events(free: true, limit: 10)).items);

final eventProvider = FutureProvider.family<EventSummary, String>((ref, id) => ref.watch(apiProvider).event(id));

final eventStreamsProvider = FutureProvider.family<EventStreams, String>((ref, id) => ref.watch(apiProvider).eventStreams(id));

final organizerProvider = FutureProvider.family<OrganizerProfile, String>((ref, slug) => ref.watch(apiProvider).organizer(slug));

@immutable
class SearchQuery {
  const SearchQuery({this.q = '', this.category, this.city, this.freeOnly = false});
  final String q;
  final String? category;
  final String? city;
  final bool freeOnly;

  SearchQuery copyWith({String? q, String? category, bool clearCategory = false, String? city, bool clearCity = false, bool? freeOnly}) => SearchQuery(
        q: q ?? this.q,
        category: clearCategory ? null : (category ?? this.category),
        city: clearCity ? null : (city ?? this.city),
        freeOnly: freeOnly ?? this.freeOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.q == q && other.category == category && other.city == city && other.freeOnly == freeOnly;
  @override
  int get hashCode => Object.hash(q, category, city, freeOnly);
}

/// The city the buyer last picked in Explore (null = any). Only kept in memory; Discover shows it as "in <city>".
class LastCityNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? city) => state = city;
}

final lastCityProvider = NotifierProvider<LastCityNotifier, String?>(LastCityNotifier.new);

final searchResultsProvider = FutureProvider.family<EventPage, SearchQuery>((ref, s) =>
    ref.watch(apiProvider).events(q: s.q, category: s.category, city: s.city, free: s.freeOnly ? true : null, limit: 50));

// ───── My tickets (cached for offline use at the venue) ─────

class MyTicketsNotifier extends AsyncNotifier<List<MyTicket>> {
  static const cacheKey = 'my_tickets_cache_v1';

  /// The owner tag of a raw cache value: null for an untagged (older build) list, '' when the owner was not known, else a user id.
  static String? ownerOf(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? (j['owner'] as String? ?? '') : null;
    } catch (_) {
      return null;
    }
  }

  /// The offline copy for [meId]. The cache is `{"owner": id, "tickets": [...]}`. An untagged list (older builds), or a copy whose owner
  /// was not known (''), is accepted: nobody can say it is someone else's, and it is rewritten tagged on the next online fetch. A copy
  /// tagged with another user, or an unreadable one, is not returned (null). An empty [meId] (user not known offline) trusts any copy.
  List<MyTicket>? _cached(String meId) {
    final raw = ref.read(prefsProvider).getString(cacheKey);
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw);
      final List list;
      if (j is List) {
        list = j;
      } else if (j is Map<String, dynamic>) {
        final owner = (j['owner'] as String?) ?? '';
        if (meId.isNotEmpty && owner.isNotEmpty && owner != meId) return null;
        list = j['tickets'] as List;
      } else {
        return null;
      }
      return list.map((t) => MyTicket.fromJson(t as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Whether the last list came from the offline cache.
  bool fromCache = false;

  /// The id of the signed-in user the current list belongs to (null when signed out or not loaded yet). A list is never shown to
  /// another session: when the session user changes the value is dropped before the reload starts.
  String? owner;

  @override
  Future<List<MyTicket>> build() async {
    void drop() {
      owner = null;
      fromCache = false;
      state = const AsyncLoading<List<MyTicket>>();
    }

    final session = ref.read(sessionProvider);
    if (owner != null && (session.isLoading || owner != session.value?.id)) drop();
    final me = await ref.watch(sessionProvider.future);
    if (me == null) {
      owner = null;
      return const [];
    }
    if (owner != null && owner != me.id) drop(); // a different user signed in: their list starts empty, not as the previous one's
    final prefs = ref.read(prefsProvider);
    // Still the session of the user that started this fetch (nobody signed out or switched while it was running).
    bool current() {
      try {
        return ref.mounted && ref.read(sessionProvider).value?.id == me.id;
      } catch (_) {
        return false;
      }
    }

    try {
      final fresh = await ref.read(apiProvider).myTickets();
      // A fetch that was already in flight when the session ended must not write the signed-out (or the next user's) cache.
      if (current()) {
        final list = fresh.map((t) => t.toJson()).toList();
        // Never tagged with an empty owner: when whose tickets these are is not known, the older plain list stays.
        await prefs.setString(cacheKey, jsonEncode(me.id.isEmpty ? list : {'owner': me.id, 'tickets': list}));
        owner = me.id;
      }
      fromCache = false;
      return fresh;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        // A failure that comes back after the account changed must not relabel the list of whoever is signed in now.
        if (!current()) rethrow;
        final cached = _cached(me.id);
        if (cached == null) rethrow; // someone else's copy (or unreadable): the Tickets tab shows its error and retry
        fromCache = true;
        owner = me.id;
        return cached;
      }
      rethrow;
    }
  }

  Future<void> refresh() async => ref.invalidateSelf();
}

final myTicketsProvider = AsyncNotifierProvider<MyTicketsNotifier, List<MyTicket>>(MyTicketsNotifier.new);

// ───── Paid checkout ─────

/// Payment methods buyers can use now (empty → paid tickets show "available soon").
final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  try {
    return await ref.watch(apiProvider).paymentMethods();
  } on ApiException {
    return const [];
  }
});

/// The signed-in user's orders still waiting for payment.
final pendingOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final me = await ref.watch(sessionProvider.future);
  if (me == null) return const [];
  try {
    return await ref.watch(apiProvider).pendingOrders();
  } on ApiException {
    return const [];
  }
});

// ───── Waitlist ─────

/// The signed-in buyer's waitlist entries (`GET /me/waitlist`); empty when signed out or offline. A refresh keeps the
/// previous list on screen (and on failure) so a banner doesn't flicker.
class WaitlistNotifier extends AsyncNotifier<List<WaitlistEntry>> {
  @override
  Future<List<WaitlistEntry>> build() async {
    final me = await ref.watch(sessionProvider.future);
    if (me == null) return const [];
    try {
      return await ref.read(apiProvider).myWaitlist();
    } on ApiException {
      return state.value ?? const [];
    }
  }

  Future<void> refresh() async => ref.invalidateSelf();
}

final waitlistProvider = AsyncNotifierProvider<WaitlistNotifier, List<WaitlistEntry>>(WaitlistNotifier.new);

/// The buyer's active entry for a ticket type (WAITING, or OFFERED), if any.
WaitlistEntry? activeEntryFor(List<WaitlistEntry> entries, String ticketTypeId) =>
    entries.where((e) => e.ticketTypeId == ticketTypeId && e.isActive && (e.status != 'OFFERED' || e.isOffered)).firstOrNull;

/// The live offer that ends first, if any. Any OFFERED entry counts, whatever its `orderId` (a reopened offer still carries
/// the cancelled order's id).
WaitlistEntry? soonestOffer(List<WaitlistEntry> entries) {
  final live = entries.where((e) => e.isOffered).toList()..sort((a, b) => a.offerExpiresAt!.compareTo(b.offerExpiresAt!));
  return live.firstOrNull;
}

// ───── Notifications ─────

final pushProvider = Provider<PushClient>((ref) => FirebasePush.configured ? FirebasePush() : const NoPush());
const pushTokenKey = 'push_token';

/// Latest inbox page for the signed-in user (empty when signed out).
final inboxProvider = FutureProvider<Inbox>((ref) async {
  final me = await ref.watch(sessionProvider.future);
  if (me == null) return Inbox(items: const [], unread: 0);
  return ref.watch(apiProvider).notifications();
});

/// Registers this phone's push token for the signed-in user (and again when Firebase rotates it).
Future<void> registerPush(PushClient push, Event360Api api, SharedPreferences prefs, {String? token}) async {
  if (!push.supported) return;
  final t = token ?? await push.token();
  if (t == null) return;
  await api.registerDevice(t, 'android');
  await prefs.setString(pushTokenKey, t);
}
