import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';
import '../widgets/waitlist_offer.dart';

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final session = ref.watch(sessionProvider);
    final tickets = ref.watch(myTicketsProvider);
    final fromCache = ref.read(myTicketsProvider.notifier).fromCache;
    final pending = (ref.watch(pendingOrdersProvider).value ?? const <Order>[]).where((o) => o.isOpen).toList();

    Widget body;
    if (session.value == null && !session.isLoading) {
      body = MessageView(icon: Icons.lock_outline, message: t.signInToRegister, actionLabel: t.signIn, onAction: () => context.push('/login'));
    } else {
      body = tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(myTicketsProvider)),
        data: (list) {
          if (list.isEmpty && pending.isEmpty) {
            return Column(children: [
              const OfferBanner(),
              Expanded(child: MessageView(icon: Icons.confirmation_number_outlined, message: t.noTickets, actionLabel: t.explore, onAction: () => context.go('/explore'))),
            ]);
          }
          final now = ref.watch(nowProvider)();
          final byEvent = <String, List<MyTicket>>{};
          for (final x in list) {
            byEvent.putIfAbsent(x.eventId, () => []).add(x);
          }
          final groups = byEvent.values.toList();
          DateTime endOf(List<MyTicket> g) => g.first.endsAt;
          final upcoming = groups.where((g) => endOf(g).isAfter(now)).toList()..sort((a, b) => a.first.startsAt.compareTo(b.first.startsAt));
          final past = groups.where((g) => !endOf(g).isAfter(now)).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(pendingOrdersProvider);
              ref.invalidate(waitlistProvider);
              await ref.read(myTicketsProvider.notifier).refresh();
            },
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const OfferBanner(padding: EdgeInsets.only(bottom: 12)),
              if (fromCache)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const Icon(Icons.cloud_off, size: 18), const SizedBox(width: 6), Text(t.offlineReady)])),
              if (pending.isNotEmpty) _Header(t.pendingPayments),
              for (final o in pending) _PendingTile(order: o),
              if (upcoming.isNotEmpty) _Header(t.upcomingTickets),
              for (final g in upcoming) _EventGroup(tickets: g, now: now),
              if (past.isNotEmpty) _Header(t.past),
              for (final g in past) _EventGroup(tickets: g, now: now, dim: true),
            ]),
          );
        },
      );
    }
    return Scaffold(appBar: AppBar(title: Text(t.myTickets)), body: body);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

/// One event: a header (cover, title, date, guide link) and a row per ticket held for it.
class _EventGroup extends ConsumerWidget {
  const _EventGroup({required this.tickets, required this.now, this.dim = false});
  final List<MyTicket> tickets;
  final DateTime now;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final first = tickets.first;
    final hasGuide = tickets.any((x) => x.status == 'VALID' || x.isCheckedIn) && guideLinkVisible(endsAt: first.endsAt, now: now);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Card(
        key: Key('ticketGroup-${first.eventId}'),
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 64, height: 64, child: EventCover(url: first.coverImageUrl, aspectRatio: 1))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pickLang(lang, first.eventTitle, first.eventTitleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(formatEventDate(first.startsAt, lang), style: theme.textTheme.bodySmall),
                  if (hasGuide)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: Key('groupGuideLink-${first.eventId}'),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
                        onPressed: () => context.push('/event/${first.eventId}/guide'),
                        child: Text(t.eventGuide),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          for (final x in tickets) ...[
            const Divider(height: 1),
            _TicketRow(ticket: x),
          ],
        ]),
      ),
    );
  }
}

class _TicketRow extends ConsumerWidget {
  const _TicketRow({required this.ticket});
  final MyTicket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final String? status = switch (ticket.status) {
      'VALID' => null,
      'CHECKED_IN' => ticket.checkedInAt == null ? t.checkedIn : t.checkedInAt(formatTime(ticket.checkedInAt!, lang)),
      'REFUNDED' => t.ticketStatusRefunded,
      _ => t.ticketStatusCancelled,
    };
    return InkWell(
      key: Key('ticketRow-${ticket.id}'),
      onTap: () => context.push('/ticket/${ticket.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pickLang(lang, ticket.ticketTypeName, ticket.ticketTypeNameMy), style: theme.textTheme.bodyMedium),
              if (ticket.seatText(lang) != null)
                Text(ticket.seatText(lang)!, key: Key('seat-${ticket.id}'), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
              if (ticket.isComplimentary)
                Text(
                  ticket.compLabel == null || ticket.compLabel!.isEmpty ? t.complimentary : t.complimentaryLabel(ticket.compLabel!),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: dark ? E360DarkColors.success : E360Colors.success),
                ),
              if (status != null)
                Text(
                  status,
                  key: Key('ticketStatus-${ticket.id}'),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: ticket.isCheckedIn ? (dark ? E360DarkColors.success : E360Colors.success) : theme.colorScheme.onSurfaceVariant),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Icon(ticket.status == 'VALID' ? Icons.qr_code_2 : (ticket.isCheckedIn ? Icons.check_circle_outline : Icons.block)),
          ),
        ]),
      ),
    );
  }
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.hourglass_top, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pickLang(lang, order.eventTitle, order.eventTitleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                Text('${order.quantity} × · ${t.mmk(formatAmount(order.totalMmk, lang))}', style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            style: E360Buttons.navy.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
            onPressed: () => context.push('/checkout/${order.id}'),
            child: Text(t.continuePayment),
          ),
        ]),
      ),
    );
  }
}
