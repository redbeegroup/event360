import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// "Happening today — {event}. Open your guide": one tappable card that opens the event's guide. Not a button in the gold sense.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key, required this.ticket, this.padding = EdgeInsets.zero});
  final MyTicket ticket;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant));
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.primaryContainer,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: () => context.push('/event/${ticket.eventId}/guide'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(Icons.event_available, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.happeningToday, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                    Text(pickLang(lang, ticket.eventTitle, ticket.eventTitleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 2),
                    Text(t.openGuide, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                  ]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
