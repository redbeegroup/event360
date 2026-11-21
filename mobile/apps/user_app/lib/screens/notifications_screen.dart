import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

IconData _icon(String kind) => switch (kind) {
      'ticket_confirmed' => Icons.confirmation_number_outlined,
      'event_reminder' => Icons.alarm,
      'event_changed' => Icons.edit_calendar_outlined,
      'event_cancelled' => Icons.event_busy_outlined,
      'live_now' => Icons.live_tv,
      'order_refunded' => Icons.currency_exchange,
      'announcement' => Icons.campaign_outlined,
      'ticket_received' => Icons.redeem,
      _ => Icons.notifications_none,
    };

/// Bell with the unread count, for app bars.
class InboxBell extends ConsumerWidget {
  const InboxBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider).value == null) return const SizedBox.shrink();
    final unread = ref.watch(inboxProvider).value?.unread ?? 0;
    return IconButton(
      key: const Key('inboxBell'),
      tooltip: L10n.of(context).notifications,
      onPressed: () => context.push('/notifications'),
      icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: const Icon(Icons.notifications_outlined)),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final inbox = ref.watch(inboxProvider);

    Future<void> open(AppNotification n) async {
      if (n.unread) {
        await ref.read(apiProvider).markNotificationsRead([n.id]).catchError((_) {});
        ref.invalidate(inboxProvider);
      }
      if (n.link != null && n.link!.startsWith('/') && context.mounted) await context.push(n.link!);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.notifications), actions: [
        if ((inbox.value?.unread ?? 0) > 0)
          TextButton(
            onPressed: () async {
              await ref.read(apiProvider).markNotificationsRead().catchError((_) {});
              ref.invalidate(inboxProvider);
            },
            child: Text(t.markAllRead),
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
                      key: Key('notif-${n.id}'),
                      tileColor: n.unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                      leading: CircleAvatar(backgroundColor: theme.colorScheme.primaryContainer, foregroundColor: theme.colorScheme.onPrimaryContainer, child: Icon(_icon(n.kind))),
                      title: Text(pickLang(lang, n.title, n.titleMy), style: theme.textTheme.titleSmall?.copyWith(fontWeight: n.unread ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(pickLang(lang, n.body, n.bodyMy)),
                        const SizedBox(height: 2),
                        Text('${formatDay(n.createdAt, lang)} · ${formatTime(n.createdAt, lang)}', style: theme.textTheme.bodySmall),
                      ]),
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
