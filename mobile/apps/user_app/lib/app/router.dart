import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../screens/checkout_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/explore_screen.dart';
import '../screens/home_screen.dart';
import '../screens/language_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/organizer_screen.dart';
import '../screens/seat_picker_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/ticket_screen.dart';
import '../screens/tickets_screen.dart';
import '../screens/watch_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // First run: ask for the language before anything else.
      final chosen = ref.read(localeProvider) != null;
      if (!chosen && state.matchedLocation != '/language') return '/language';
      return null;
    },
    routes: [
      GoRoute(path: '/language', builder: (_, __) => const LanguageScreen()),
      GoRoute(
        path: '/login',
        builder: (_, s) => LoginScreen(returnTo: s.uri.queryParameters['from']),
      ),
      GoRoute(path: '/event/:id', builder: (_, s) => EventDetailScreen(idOrSlug: s.pathParameters['id']!)),
      GoRoute(path: '/event/:id/seats', builder: (_, s) => SeatPickerScreen(idOrSlug: s.pathParameters['id']!)),
      GoRoute(path: '/ticket/:id', builder: (_, s) => TicketScreen(ticketId: s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/checkout/:id', builder: (_, s) => CheckoutScreen(orderId: s.pathParameters['id']!)),
      GoRoute(
        path: '/watch/:kind/:id',
        builder: (_, s) => WatchScreen(kind: s.pathParameters['kind']!, id: s.pathParameters['id']!, title: s.uri.queryParameters['title'] ?? ''),
      ),
      GoRoute(path: '/organizer/:slug', builder: (_, s) => OrganizerScreen(slug: s.pathParameters['slug']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/explore', builder: (_, s) => ExploreScreen(initialCategory: s.uri.queryParameters['category'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/tickets', builder: (_, __) => const TicketsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t.home),
          NavigationDestination(icon: const Icon(Icons.search), label: t.explore),
          NavigationDestination(
              icon: const Icon(Icons.confirmation_number_outlined), selectedIcon: const Icon(Icons.confirmation_number), label: t.myTickets),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t.profile),
        ],
      ),
    );
  }
}
