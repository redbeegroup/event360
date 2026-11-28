import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../screens/checkout_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/event_guide_screen.dart';
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
import '../widgets/waitlist_offer.dart';
import 'guide_providers.dart';
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
      GoRoute(path: '/event/:id/seats', builder: (_, s) => SeatPickerScreen(idOrSlug: s.pathParameters['id']!, offerEntryId: s.uri.queryParameters['offer'])),
      GoRoute(
        path: '/event/:id/guide',
        // Only for a signed-in holder of a VALID or CHECKED_IN ticket for this event (the screen enforces it again once the ticket list has loaded).
        redirect: (context, state) {
          final id = state.pathParameters['id']!;
          final a = guideAccessOf(session: ref.read(sessionProvider), tickets: ref.read(myTicketsProvider), idOrSlug: id).access;
          return switch (a) {
            GuideAccess.signedOut => '/login?from=${Uri.encodeQueryComponent('/event/$id/guide')}',
            GuideAccess.noTicket => '/event/$id',
            _ => null,
          };
        },
        builder: (_, s) => EventGuideScreen(eventId: s.pathParameters['id']!),
      ),
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
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    return Scaffold(
      body: WaitlistSync(child: shell),
      bottomNavigationBar: _TabBar(
        selected: shell.currentIndex,
        onSelected: go,
        items: [
          _Tab(t.tabDiscover, Icons.home_outlined, Icons.home),
          _Tab(t.explore, Icons.search, Icons.manage_search),
          _Tab(t.tabTickets, Icons.confirmation_number_outlined, Icons.confirmation_number),
          _Tab(t.tabAccount, Icons.person_outline, Icons.person),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon, selectedIcon;
}

/// Bottom tabs: white bar, hairline top border, a short gold marker above the active tab.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.items, required this.selected, required this.onSelected});
  final List<_Tab> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == selected,
                    child: InkWell(
                      onTap: () => onSelected(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Stack(alignment: Alignment.topCenter, children: [
                          if (i == selected)
                            Container(width: 32, height: 3, decoration: BoxDecoration(color: E360Colors.gold, borderRadius: BorderRadius.circular(2))),
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 4),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(i == selected ? items[i].selectedIcon : items[i].icon, size: 24, color: i == selected ? scheme.primary : scheme.onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: i == selected ? FontWeight.w700 : FontWeight.w600,
                                  color: i == selected ? scheme.primary : scheme.onSurfaceVariant,
                                ),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
