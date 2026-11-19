import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/activity_screen.dart';
import '../screens/events_screen.dart';
import '../screens/login_screen.dart';
import '../screens/lookup_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/setup_screen.dart';
import 'providers.dart';

/// Signed out → /login; account without an event → /events; no device/gate yet → /setup; else /scan.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/scan',
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      if (s == null) return loc == '/login' || loc == '/redeem' ? null : '/login';
      if (s.event == null) return loc == '/events' ? null : '/events';
      if (!s.ready) return loc == '/setup' ? null : '/setup';
      if (['/login', '/redeem', '/events', '/setup'].contains(loc)) return '/scan';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      // Link in the organizer's QR: …/crew/#/redeem?code=K7QM-4XRT
      GoRoute(path: '/redeem', builder: (_, s) => LoginScreen(initialCode: s.uri.queryParameters['code'])),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/lookup', builder: (_, __) => const LookupScreen()),
      GoRoute(path: '/activity', builder: (_, __) => const ActivityScreen()),
    ],
  );
  ref.listen(sessionProvider, (_, __) => router.refresh());
  return router;
});
