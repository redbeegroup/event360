import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

IconData _icon(String kind) => switch (kind) {
      'org_event_approved' => Icons.verified_outlined,
      'org_event_rejected' => Icons.report_gmailerrorred,
      'org_first_sale' => Icons.celebration_outlined,
      'org_half_sold' => Icons.trending_up,
      'org_sold_out' => Icons.local_fire_department_outlined,
      'org_daily' => Icons.insights_outlined,
      _ => Icons.notifications_none,
    };

class InboxBell extends ConsumerWidget {
  const InboxBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(inboxProvider).value?.unread ?? 0;
    return IconButton(
      key: const Key('inboxBell'),
      tooltip: L10n.of(context).notifications,
      onPressed: () => context.push('/notifications'),
      icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: const Icon(Icons.notifications_outlined)),
    );
  }
}

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final inbox = ref.watch(inboxProvider);

    Future<void> open(AppNotification n) async {
      if (n.unread) {
        await ref.read(apiProvider).markOrganizerNotificationsRead([n.id]).catchError((_) {});
        ref.invalidate(inboxProvider);
      }
      if (n.link != null && n.link!.startsWith('/') && n.link != '/' && context.mounted) await context.push(n.link!);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.notifications), actions: [
        if ((inbox.value?.unread ?? 0) > 0)
          ConstrainedBox(
            // Large text: the label wraps instead of pushing the title out of the bar
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
            child: TextButton(
              onPressed: () async {
                await ref.read(apiProvider).markOrganizerNotificationsRead().catchError((_) {});
                ref.invalidate(inboxProvider);
              },
              child: Text(t.markAllRead, textAlign: TextAlign.center),
            ),
          ),
      ]),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(inboxProvider)),
        data: (box) => box.items.isEmpty
            ? MessageView(icon: Icons.notifications_none, message: t.noNotifications)
            : RefreshIndicator(
                onRefresh: () => ref.refresh(inboxProvider.future),
                child: ListView.separated(
                  itemCount: box.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = box.items[i];
                    return ListTile(
                      tileColor: n.unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                      leading: CircleAvatar(backgroundColor: theme.colorScheme.surfaceContainerHighest, foregroundColor: theme.colorScheme.primary, child: Icon(_icon(n.kind))),
                      title: Text(pickLang(lang, n.title, n.titleMy), style: TextStyle(fontWeight: n.unread ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${pickLang(lang, n.body, n.bodyMy)}\n${formatDayTime(n.createdAt, lang)}'),
                      isThreeLine: true,
                      onTap: () => open(n),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
