import 'package:event360_core/event360_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push.dart';

/// Overridden in main() / tests.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider not overridden'));
final configProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment(Event360App.organizer));
// Own key prefix: on the web the organizer preview shares an origin with the other apps.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore(null, 'e360org'));
final apiProvider = Provider<Event360Api>((ref) => Event360Api(ref.watch(configProvider), ref.watch(tokenStoreProvider)));
final pushProvider = Provider<PushClient>((ref) => FirebasePush.configured ? FirebasePush() : const NoPush());
const pushTokenKey = 'org_push_token';

// ───── Language ─────

class LangNotifier extends Notifier<String> {
  static const _key = 'org_lang';
  @override
  String build() => ref.watch(prefsProvider).getString(_key) ?? 'my';

  Future<void> toggle() async {
    state = state == 'my' ? 'en' : 'my';
    await ref.read(prefsProvider).setString(_key, state);
  }
}

final langProvider = NotifierProvider<LangNotifier, String>(LangNotifier.new);
final localeProvider = Provider<Locale>((ref) => Locale(ref.watch(langProvider)));

// ───── Session: the organizations this account can manage ─────

/// Set when a signed-in session ended on the server side (a 401 that the token refresh could not fix); the sign-in
/// screen shows "Please sign in again" once and clears it.
class SessionEndedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final sessionEndedProvider = NotifierProvider<SessionEndedNotifier, bool>(SessionEndedNotifier.new);

class SessionNotifier extends AsyncNotifier<List<OrgMembership>?> {
  @override
  Future<List<OrgMembership>?> build() async {
    final api = ref.watch(apiProvider);
    // The one place a 401 that survives the token refresh is handled (the API client calls this), not every screen.
    api.onSessionExpired = _sessionExpired;
    if (await api.tokens.accessToken() == null) return null;
    try {
      return (await api.myOrganizations()).where((o) => o.canView).toList();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // The stored session was already dead when the app opened: the sign-in screen says so.
        Future.microtask(() => ref.read(sessionEndedProvider.notifier).set(true));
        return null;
      }
      rethrow;
    }
  }

  /// Signs out without any call that needs the session: the tokens and the push token go, the router returns to sign-in.
  void _sessionExpired() {
    if (state.value == null) return; // already signed out, or still working out who this is
    try {
      ref.read(sessionEndedProvider.notifier).set(true);
      state = const AsyncData(null);
    } catch (_) {
      return; // the notifier was disposed meanwhile
    }
    _forget();
  }

  Future<void> _forget() async {
    try {
      final prefs = ref.read(prefsProvider);
      if (prefs.getString(pushTokenKey) != null) {
        await prefs.remove(pushTokenKey);
        await ref.read(pushProvider).deleteToken().catchError((_) {});
      }
      await ref.read(apiProvider).logout();
    } catch (_) {}
    _dropCachedData();
  }

  /// Every data provider watches the API provider: rebuilding it drops what the last user had loaded (sales, guests, seats),
  /// so the next person to sign in on this device never sees it, even for a moment.
  void _dropCachedData() {
    try {
      ref.invalidate(apiProvider);
    } catch (_) {}
  }

  Future<void> signIn(String email, String password) async {
    await ref.read(apiProvider).passwordLogin(email, password);
    // Whatever was loaded (or failed to load) before this sign-in belongs to nobody now: start every data provider afresh.
    _dropCachedData();
    ref.invalidateSelf();
    await future;
  }

  Future<void> signOut() async {
    // Signed out first: a 401 from the calls below (a session that was already over) must not read as "session ended".
    state = const AsyncData(null);
    final token = ref.read(prefsProvider).getString(pushTokenKey);
    if (token != null) {
      await ref.read(apiProvider).removeDevice(token).catchError((_) {});
      await ref.read(prefsProvider).remove(pushTokenKey);
      await ref.read(pushProvider).deleteToken().catchError((_) {});
    }
    await ref.read(apiProvider).logout();
    _dropCachedData();
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, List<OrgMembership>?>(SessionNotifier.new);

/// Chosen organization (remembered); defaults to the first one.
class OrgNotifier extends Notifier<String?> {
  static const _key = 'org_selected';
  @override
  String? build() => ref.watch(prefsProvider).getString(_key);
  Future<void> select(String id) async {
    state = id;
    await ref.read(prefsProvider).setString(_key, id);
  }
}

final selectedOrgIdProvider = NotifierProvider<OrgNotifier, String?>(OrgNotifier.new);

final currentOrgProvider = Provider<OrgMembership?>((ref) {
  final orgs = ref.watch(sessionProvider).value ?? const <OrgMembership>[];
  if (orgs.isEmpty) return null;
  final id = ref.watch(selectedOrgIdProvider);
  return orgs.firstWhere((o) => o.id == id, orElse: () => orgs.first);
});

final orgEventsProvider = FutureProvider<List<OrgEvent>>((ref) async {
  final org = ref.watch(currentOrgProvider);
  if (org == null) return const [];
  return ref.watch(apiProvider).orgEvents(org.id);
});

/// (orgId, eventId) key for per-event data.
typedef EventKey = ({String orgId, String eventId});

final dashboardProvider = FutureProvider.family<EventDashboard, EventKey>((ref, k) => ref.watch(apiProvider).eventDashboard(k.orgId, k.eventId));
final attendanceProvider = FutureProvider.family<CrewStats, EventKey>((ref, k) => ref.watch(apiProvider).eventAttendance(k.orgId, k.eventId));
final recentOrdersProvider = FutureProvider.family<List<RecentOrder>, EventKey>((ref, k) => ref.watch(apiProvider).recentOrders(k.orgId, k.eventId));
final waitlistProvider = FutureProvider.family<WaitlistCounts, EventKey>((ref, k) => ref.watch(apiProvider).waitlistCounts(k.orgId, k.eventId));
final eventSalesProvider = FutureProvider.family<EventSales, EventKey>((ref, k) => ref.watch(apiProvider).eventSales(k.orgId, k.eventId),
    // A failed refresh is reported at once (the tab says so) rather than retried behind the scenes
    retry: (_, __) => null);
/// Owner/finance payout totals. Not kept once the screen closes, so each visit shows fresh numbers; a failed refresh is reported at once.
final payoutSummaryProvider = FutureProvider.autoDispose.family<PayoutSummary, String>((ref, orgId) => ref.watch(apiProvider).payoutSummary(orgId), retry: (_, __) => null);
final attendeesProvider = FutureProvider.family<List<Attendee>, EventKey>((ref, k) => ref.watch(apiProvider).attendees(k.orgId, k.eventId),
    // A failed refresh is reported at once (the tab says so) rather than retried behind the scenes
    retry: (_, __) => null);
final orgSeatingProvider = FutureProvider.family<OrgSeating, EventKey>((ref, k) => ref.watch(apiProvider).orgSeating(k.orgId, k.eventId));
final guestTicketsProvider = FutureProvider.family<List<GuestTicket>, EventKey>((ref, k) => ref.watch(apiProvider).guestTickets(k.orgId, k.eventId));
final crewCodesProvider = FutureProvider.family<List<CrewCode>, EventKey>((ref, k) => ref.watch(apiProvider).crewCodes(k.orgId, k.eventId));
final announcementsProvider = FutureProvider.family<Announcements, EventKey>((ref, k) => ref.watch(apiProvider).announcements(k.orgId, k.eventId));
final promoCodesProvider = FutureProvider.family<List<PromoCodeInfo>, EventKey>((ref, k) => ref.watch(apiProvider).promoCodes(k.orgId, k.eventId));

final inboxProvider = FutureProvider<Inbox>((ref) async {
  final orgs = await ref.watch(sessionProvider.future);
  if (orgs == null) return Inbox(items: const [], unread: 0);
  return ref.watch(apiProvider).organizerNotifications();
});

/// Crew app web preview (opened from the Door tab); set per build.
const crewWebUrl = String.fromEnvironment('CREW_WEB_URL', defaultValue: 'https://app.dev.event360.app/crew/');

Future<void> registerPush(PushClient push, Event360Api api, SharedPreferences prefs, {String? token}) async {
  if (!push.supported) return;
  final t = token ?? await push.token();
  if (t == null) return;
  await api.registerDevice(t, 'android', appId: 'organizer_app');
  await prefs.setString(pushTokenKey, t);
}
