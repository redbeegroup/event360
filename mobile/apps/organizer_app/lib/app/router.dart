import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/event_screen.dart';
import '../screens/events_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/login_screen.dart';
import '../screens/payouts_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      if (s.isLoading && !s.hasValue) return null;
      final signedIn = s.value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      // Owners and finance only, by the organization chosen right now
      if (state.matchedLocation == '/payouts' && ref.read(currentOrgProvider)?.canSeePayouts != true) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/event/:id', builder: (_, s) => EventScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/payouts', builder: (_, __) => const PayoutsScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const InboxScreen()),
    ],
  );
  ref.listen(sessionProvider, (_, __) => router.refresh());
  ref.listen(currentOrgProvider, (_, __) => router.refresh());
  return router;
});
