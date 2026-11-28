import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'notifications_screen.dart';
import '../app/guide_providers.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_row.dart';
import '../widgets/today_card.dart';
import '../widgets/waitlist_offer.dart';

/// The soonest event that has a cover image, or null.
EventSummary? featuredEvent(List<EventSummary> events) {
  EventSummary? best;
  for (final e in events) {
    if (e.coverImageUrl == null) continue;
    if (best == null || e.startsAt.isBefore(best.startsAt)) best = e;
  }
  return best;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final categories = ref.watch(categoriesProvider);
    final upcoming = ref.watch(upcomingProvider);
    final free = ref.watch(freeEventsProvider);
    final city = ref.watch(lastCityProvider);
    final today = ref.watch(todayEventsProvider).firstOrNull;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Future<void> refresh() async {
      ref.invalidate(categoriesProvider);
      ref.invalidate(upcomingProvider);
      ref.invalidate(freeEventsProvider);
      ref.invalidate(waitlistProvider);
      await ref.read(upcomingProvider.future);
    }

    final otherLang = lang == 'my' ? 'en' : 'my';
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          const E360Mark(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const InboxBell(),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: t.switchLanguage,
            excludeSemantics: true,
            child: OutlinedButton(
              key: const Key('langSwitch'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: scheme.onSurface,
                backgroundColor: scheme.surface,
                side: BorderSide(color: scheme.outlineVariant),
                textStyle: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 14,
                  color: null,
                ),
              ),
              onPressed: () => ref.read(localeProvider.notifier).set(otherLang),
              child: Text(otherLang == 'my' ? 'မြန်မာ' : 'English'),
            ),
          ),
        ],
      ),
    );

    // At least 44 px (the touch target) and taller when large Myanmar text needs it, so nothing clips.
    final chips = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: categories.when(
        data: (cats) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryChip(
                  label: t.allCategories,
                  selected: true,
                  onTap: () => context.go('/explore'),
                ),
                for (final c in cats)
                  _CategoryChip(
                    label: c.name(lang),
                    onTap: () => context.go('/explore?category=${c.slug}'),
                  ),
              ],
            ),
          ),
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );

    final events = upcoming.value;
    final featured = events == null ? null : featuredEvent(events);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header),
              const SliverToBoxAdapter(
                child: OfferBanner(padding: EdgeInsets.fromLTRB(20, 12, 20, 0)),
              ),
              if (today != null)
                SliverToBoxAdapter(
                  child: TodayCard(key: const Key('homeTodayBanner'), ticket: today, padding: const EdgeInsets.fromLTRB(20, 12, 20, 0)),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: DiscoverSearchPill(
                    city: city,
                    onTap: () => context.go('/explore'),
                    onFilters: () => context.go('/explore'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: chips,
                ),
              ),
              if (featured != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: FeaturedEventCard(event: featured),
                  ),
                ),
              ..._popularSection(
                context,
                t.popular,
                upcoming,
                featured,
                onRetry: refresh,
              ),
              ..._freeSection(
                context,
                t.freeEvents,
                free,
                featured?.id,
                onRetry: () => ref.invalidate(freeEventsProvider),
                onSeeAll: () => context.go('/explore'),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title, {VoidCallback? onSeeAll}) {
    final t = L10n.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            // The title keeps the width at normal text size; at large sizes the label is capped, then wraps or ellipsizes
            if (onSeeAll != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
                child: TextButton(
                  onPressed: onSeeAll,
                  child: Text(t.seeAll, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _freeSection(
    BuildContext context,
    String title,
    AsyncValue<List<EventSummary>> value,
    String? featuredId, {
    VoidCallback? onSeeAll,
    VoidCallback? onRetry,
  }) {
    final t = L10n.of(context);
    final header = _header(context, title, onSeeAll: onSeeAll);
    return value.when(
      loading: () => [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (_, __) => [
        header,
        SliverToBoxAdapter(
          child: MessageView(
            icon: Icons.wifi_off,
            message: t.loadError,
            actionLabel: t.retry,
            onAction: onRetry,
          ),
        ),
      ],
      data: (all) {
        final events = [
          for (final e in all)
            if (e.id != featuredId) e,
        ];
        if (events.isEmpty) return [];
        return [
          header,
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < events.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    FeaturedEventCard(
                      event: events[i],
                      width: 280,
                      coverHeight: 140,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ];
      },
    );
  }

  List<Widget> _popularSection(
    BuildContext context,
    String title,
    AsyncValue<List<EventSummary>> value,
    EventSummary? featured, {
    VoidCallback? onRetry,
  }) {
    final t = L10n.of(context);
    final header = _header(context, title);
    return value.when(
      loading: () => [
        header,
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
      error: (_, __) => [
        header,
        SliverToBoxAdapter(
          child: MessageView(
            icon: Icons.wifi_off,
            message: t.loadError,
            actionLabel: t.retry,
            onAction: onRetry,
          ),
        ),
      ],
      data: (all) {
        final events = [
          for (final e in all)
            if (e.id != featured?.id) e,
        ];
        if (events.isEmpty) {
          return featured != null
              ? []
              : [
                  header,
                  SliverToBoxAdapter(
                    child: MessageView(
                      icon: Icons.event_busy,
                      message: t.noEvents,
                    ),
                  ),
                ];
        }
        return [
          header,
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: events.length,
              separatorBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(),
              ),
              itemBuilder: (_, i) => EventRow(event: events[i]),
            ),
          ),
        ];
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    // 36 px chip inside a 44 px touch target
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected ? scheme.primary : scheme.surface,
                shape: StadiumBorder(
                  side: selected
                      ? BorderSide.none
                      : BorderSide(
                          color: theme.brightness == Brightness.dark
                              ? E360DarkColors.chipLine
                              : scheme.outlineVariant,
                        ),
                ),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: 14,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
