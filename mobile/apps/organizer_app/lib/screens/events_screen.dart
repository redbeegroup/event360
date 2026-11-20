import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
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
        error: (_, __) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(orgEventsProvider)),
        data: (list) {
          if (list.isEmpty) return MessageView(icon: Icons.event_busy_outlined, message: t.noEvents);
          final upcoming = list.where((e) => !e.isPast).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = list.where((e) => e.isPast).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(orgEventsProvider.future),
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
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
              if (v == 'out') ref.read(sessionProvider.notifier).signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'lang', child: Text(lang == 'my' ? 'English' : 'မြန်မာ')),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.lang, this.dim = false});
  final OrgEvent event;
  final String lang;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: ListTile(
        key: Key('event-${event.id}'),
        title: Text(pickLang(lang, event.title, event.titleMy), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([formatDayTime(event.startsAt, lang), if (event.venue != null) event.venue!].join(' · ')),
        trailing: event.isLiveNow && event.status == 'PUBLISHED'
            ? Chip(label: Text(t.liveNow), backgroundColor: theme.colorScheme.errorContainer, visualDensity: VisualDensity.compact)
            : Text(statusLabel(t, event.status), style: theme.textTheme.bodySmall),
        onTap: () => context.push('/event/${event.id}'),
      ),
    );
  }
}

