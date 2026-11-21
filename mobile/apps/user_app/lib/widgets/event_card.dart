import 'package:cached_network_image/cached_network_image.dart';
import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

String priceLabel(L10n t, String lang, EventSummary e) {
  // Free only when everything is free; a free option next to paid ones says so.
  if (e.isFree) return t.free;
  if (e.minPriceMmk == 0) return t.freeTicketsAvailable;
  if (e.minPriceMmk == null) return '';
  return t.fromPrice(t.mmk(formatAmount(e.minPriceMmk!, lang)));
}

String formatLabel(L10n t, String format) => switch (format) {
      'ONLINE' => t.formatOnline,
      'HYBRID' => t.formatHybrid,
      _ => t.formatInPerson,
    };

/// Cover image with a soft branded placeholder when the event has none.
class EventCover extends StatelessWidget {
  const EventCover({super.key, required this.url, this.aspectRatio = 16 / 9});
  final String? url;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Icon(Icons.celebration_outlined, size: 40, color: scheme.onPrimaryContainer.withValues(alpha: 0.6)),
    );
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: url == null
          ? placeholder
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, placeholder: (_, __) => placeholder, errorWidget: (_, __, ___) => placeholder),
    );
  }
}

class EventCard extends ConsumerWidget {
  const EventCard({super.key, required this.event, this.width});
  final EventSummary event;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final badge = dateBadge(event.startsAt, lang);
    final place = event.format == 'ONLINE' ? t.formatOnline : event.venue?.city;
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/event/${event.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              EventCover(url: event.coverImageUrl),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    Text(badge.day, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.1)),
                    Text(badge.month, style: theme.textTheme.labelSmall),
                  ]),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pickLang(lang, event.title, event.titleMy),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text([formatEventDate(event.startsAt, lang), if (place != null) place].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (event.soldOut) E360Badge(t.soldOut, kind: E360BadgeKind.dark) else E360Badge(priceLabel(t, lang, event), kind: event.isFree || event.minPriceMmk == 0 ? E360BadgeKind.success : E360BadgeKind.neutral),
                  E360Badge(pickLang(lang, event.categoryName, event.categoryNameMy)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Text shared via the share sheet: title, date, place, and a link to the web app.
String shareText(EventSummary e, String lang) {
  final place = e.venue == null ? null : [pickLang(lang, e.venue!.name, e.venue!.nameMy), e.venue!.city].join(', ');
  const webBase = String.fromEnvironment('WEB_APP_URL', defaultValue: 'https://app.dev.event360.app');
  return [
    pickLang(lang, e.title, e.titleMy),
    '📅 ${formatEventDate(e.startsAt, lang)}',
    if (place != null) '📍 $place',
    if (pickLang(lang, e.summary, e.summaryMy).isNotEmpty) pickLang(lang, e.summary, e.summaryMy),
    '$webBase/#/event/${e.slug}',
  ].join('\n');
}
