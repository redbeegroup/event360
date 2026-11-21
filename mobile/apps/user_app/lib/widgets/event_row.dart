import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event_card.dart';

/// "Thu, 31 Dec · 7:30 PM · Shwe Pyi Theatre" (venue, or "Online"; either may be missing).
String eventMeta(L10n t, String lang, EventSummary e) {
  final place = e.format == 'ONLINE' ? t.formatOnline : (e.venue == null ? null : pickLang(lang, e.venue!.name, e.venue!.nameMy));
  return [formatDay(e.startsAt, lang), formatTime(e.startsAt, lang), if (place != null && place.isNotEmpty) place].join(' · ');
}

/// Price line: "Free" in green, "Sold out" as the dark badge, else "From 5,000 MMK".
class _PriceLine extends StatelessWidget {
  const _PriceLine(this.e, this.lang, {this.size = 13});
  final EventSummary e;
  final String lang;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final free = e.isFree || e.minPriceMmk == 0;
    if (e.soldOut) return Align(alignment: AlignmentDirectional.centerStart, child: E360Badge(t.soldOut, kind: E360BadgeKind.dark));
    final label = priceLabel(t, lang, e);
    if (label.isEmpty) return const SizedBox.shrink();
    final color = free ? (dark ? E360DarkColors.success : E360Colors.success) : theme.colorScheme.onSurface;
    return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: size, color: color));
  }
}

/// Compact row: 84 px square cover, title, date · time · venue, price.
class EventRow extends ConsumerWidget {
  const EventRow({super.key, required this.event});
  final EventSummary event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/event/${event.id}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 84),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 84, height: 84, child: EventCover(url: event.coverImageUrl, aspectRatio: 1))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(pickLang(lang, event.title, event.titleMy),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(height: 1.25)),
              const SizedBox(height: 3),
              Text(eventMeta(t, lang, event), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              const SizedBox(height: 3),
              _PriceLine(event, lang),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Large card: 176 px cover with a gold "Reserved seating" badge when the event has seat selection.
class FeaturedEventCard extends ConsumerWidget {
  const FeaturedEventCard({super.key, required this.event, this.width, this.coverHeight = 176});
  final EventSummary event;
  final double? width;
  final double coverHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/event/${event.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: coverHeight,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                EventCover(url: event.coverImageUrl),
                if (event.seating != null) Positioned(left: 12, top: 12, child: E360Badge(t.reservedSeating, kind: E360BadgeKind.gold)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text(pickLang(lang, event.title, event.titleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(eventMeta(t, lang, event), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          _PriceLine(event, lang, size: 14),
        ]),
      ),
    );
  }
}

/// White search pill: "Find things to do / in <city>" with a round filter button.
class DiscoverSearchPill extends StatelessWidget {
  const DiscoverSearchPill({super.key, this.city, required this.onTap, required this.onFilters});
  final String? city;
  final VoidCallback onTap;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dark
            ? null
            : const [BoxShadow(color: Color(0x0F15172E), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x0F15172E), blurRadius: 20, offset: Offset(0, 6))],
        border: dark ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: Row(children: [
        Expanded(
          child: InkWell(
            key: const Key('discoverSearch'),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(children: [
                Icon(Icons.search, size: 22, color: scheme.onSurface),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.findThingsToDo, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(city == null ? t.inMyanmar : t.inCity(city!),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6, left: 8),
          child: Semantics(
            button: true,
            label: t.filters,
            excludeSemantics: true,
            child: Material(
              color: scheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                key: const Key('discoverFilters'),
                customBorder: const CircleBorder(),
                onTap: onFilters,
                child: SizedBox(width: 44, height: 44, child: Icon(Icons.tune, size: 20, color: scheme.onSurface)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
