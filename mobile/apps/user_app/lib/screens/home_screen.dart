import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'notifications_screen.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final categories = ref.watch(categoriesProvider);
    final upcoming = ref.watch(upcomingProvider);
    final free = ref.watch(freeEventsProvider);
    final theme = Theme.of(context);

    Future<void> refresh() async {
      ref.invalidate(categoriesProvider);
      ref.invalidate(upcomingProvider);
      ref.invalidate(freeEventsProvider);
      await ref.read(upcomingProvider.future);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(slivers: [
          SliverAppBar.large(title: Text(t.appTitle, style: const TextStyle(fontWeight: FontWeight.w700)), actions: const [InboxBell()]),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.go('/explore'),
                child: InputDecorator(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchHint),
                  child: Text(t.searchHint, style: TextStyle(color: theme.hintColor)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: categories.when(
                data: (cats) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(label: Text(c.name(lang)), onPressed: () => context.go('/explore?category=${c.slug}')),
                      ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
          ),
          ..._section(context, t.freeEvents, free, horizontal: true, onSeeAll: () => context.go('/explore')),
          ..._section(context, t.upcoming, upcoming, onRetry: refresh),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]),
      ),
    );
  }

  List<Widget> _section(BuildContext context, String title, AsyncValue<List<EventSummary>> value,
      {bool horizontal = false, VoidCallback? onSeeAll, VoidCallback? onRetry}) {
    final t = L10n.of(context);
    final header = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: Text(t.seeAll)),
        ]),
      ),
    );
    return value.when(
      loading: () => [header, const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())))],
      error: (_, __) => [
        header,
        SliverToBoxAdapter(child: MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: onRetry)),
      ],
      data: (events) {
        if (events.isEmpty) {
          return horizontal ? [] : [header, SliverToBoxAdapter(child: MessageView(icon: Icons.event_busy, message: t.noEvents))];
        }
        if (horizontal) {
          return [
            header,
            SliverToBoxAdapter(
              child: SizedBox(
                height: 350,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => EventCard(event: events[i], width: 260),
                ),
              ),
            ),
          ];
        }
        return [
          header,
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.separated(
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => EventCard(event: events[i]),
            ),
          ),
        ];
      },
    );
  }
}
