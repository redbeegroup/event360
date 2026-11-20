import 'dart:convert';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push.dart';

/// Overridden in main() / tests.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider not overridden'));
final configProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment(Event360App.user));
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
final apiProvider = Provider<Event360Api>((ref) => Event360Api(ref.watch(configProvider), ref.watch(tokenStoreProvider)));

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
  @override
  Future<Me?> build() async {
    final api = ref.watch(apiProvider);
    if (await api.tokens.accessToken() == null) return null;
    try {
      return await api.me();
    } on ApiException catch (e) {
      if (e.isUnauthorized) return null;
      // Offline: keep the user signed in (tickets work offline); profile details load later.
      return Me(id: '', phone: null);
    }
  }

  Future<void> signedIn() async => ref.invalidateSelf();

  Future<void> signOut() async {
    // Stop this phone getting the user's notifications (needs the session, so before logout)
    final push = ref.read(pushProvider);
    final token = ref.read(prefsProvider).getString(pushTokenKey);
    if (token != null) {
      await ref.read(apiProvider).removeDevice(token).catchError((_) {});
      await ref.read(prefsProvider).remove(pushTokenKey);
      await push.deleteToken().catchError((_) {});
    }
    await ref.read(apiProvider).logout();
    await ref.read(prefsProvider).remove(MyTicketsNotifier.cacheKey);
    ref.invalidate(myTicketsProvider);
    state = const AsyncData(null);
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

final searchResultsProvider = FutureProvider.family<EventPage, SearchQuery>((ref, s) =>
    ref.watch(apiProvider).events(q: s.q, category: s.category, city: s.city, free: s.freeOnly ? true : null, limit: 50));

// ───── My tickets (cached for offline use at the venue) ─────

class MyTicketsNotifier extends AsyncNotifier<List<MyTicket>> {
  static const cacheKey = 'my_tickets_cache_v1';

  List<MyTicket> _cached() {
    final raw = ref.read(prefsProvider).getString(cacheKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List).map((j) => MyTicket.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Whether the last list came from the offline cache.
  bool fromCache = false;

  @override
  Future<List<MyTicket>> build() async {
    final me = await ref.watch(sessionProvider.future);
    if (me == null) return const [];
    try {
      final fresh = await ref.read(apiProvider).myTickets();
      await ref.read(prefsProvider).setString(cacheKey, jsonEncode(fresh.map((t) => t.toJson()).toList()));
      fromCache = false;
      return fresh;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        fromCache = true;
        return _cached();
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
