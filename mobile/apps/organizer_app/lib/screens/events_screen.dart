import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event/common.dart';
import 'inbox_screen.dart';

String statusLabel(L10n t, String s) => switch (s) {
      'DRAFT' => t.status_DRAFT,
      'SUBMITTED' => t.status_SUBMITTED,
      'PUBLISHED' => t.status_PUBLISHED,
      'ONGOING' => t.status_ONGOING,
      'COMPLETED' => t.status_COMPLETED,
      'CANCELLED' => t.status_CANCELLED,
      'REJECTED' => t.status_REJECTED,
      _ => s,
    };

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final orgs = ref.watch(sessionProvider).value ?? const <OrgMembership>[];
    final org = ref.watch(currentOrgProvider);
    final events = ref.watch(orgEventsProvider);
    final lang = ref.watch(langProvider);

    Widget body;
    if (org == null) {
      body = MessageView(icon: Icons.group_off_outlined, message: t.notOrganizer);
    } else {
      body = events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => loadError(t, () => ref.invalidate(orgEventsProvider), e),
        data: (list) {
          if (list.isEmpty) return MessageView(icon: Icons.event_busy_outlined, message: t.noEvents);
          final upcoming = list.where((e) => !e.isPast).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = list.where((e) => e.isPast).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(orgEventsProvider.future),
            child: ListView(padding: const EdgeInsets.only(top: 0, bottom: 16), children: [
              if (upcoming.isNotEmpty) _Header(t.upcoming),
              for (final e in upcoming) _EventTile(event: e, lang: lang),
              if (past.isNotEmpty) _Header(t.past),
              for (final e in past) _EventTile(event: e, lang: lang, dim: true),
            ]),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: orgs.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('orgPicker'),
                  isExpanded: true,
                  value: org?.id,
                  items: [for (final o in orgs) DropdownMenuItem(value: o.id, child: Text(o.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (id) {
                    if (id != null) ref.read(selectedOrgIdProvider.notifier).select(id);
                  },
                ),
              )
            : Text(org?.name ?? t.appTitle),
        actions: [
          const InboxBell(),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'lang') ref.read(langProvider.notifier).toggle();
              if (v == 'payouts') context.push('/payouts');
              if (v == 'out') ref.read(sessionProvider.notifier).signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'lang', child: Text(lang == 'my' ? 'English' : 'မြန်မာ')),
              if (org?.canSeePayouts ?? false) PopupMenuItem(key: const Key('menuPayouts'), value: 'payouts', child: Text(t.payouts)),
              PopupMenuItem(value: 'out', child: Text(t.signOut)),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

/// Compact event row, like the buyer app's: square cover, title, date · venue, status badge.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.lang, this.dim = false});
  final OrgEvent event;
  final String lang;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final live = event.isLiveNow && event.status == 'PUBLISHED';
    final good = event.status == 'PUBLISHED' || event.status == 'ONGOING';
    final placeholder = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.celebration_outlined, size: 30, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
    );
    final cover = event.coverImageUrl;
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: InkWell(
        key: Key('event-${event.id}'),
        onTap: () => context.push('/event/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: cover == null ? placeholder : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(pickLang(lang, event.title, event.titleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(height: 1.25)),
                  const SizedBox(height: 3),
                  Text([formatDayTime(event.startsAt, lang), if (event.venue != null) event.venue!].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: live ? E360Badge(t.liveNow, kind: E360BadgeKind.success) : E360Badge(statusLabel(t, event.status), kind: good ? E360BadgeKind.success : E360BadgeKind.neutral),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
