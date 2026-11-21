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
          final upcoming = list.where((x) => x.isUpcoming).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = list.where((x) => !x.isUpcoming).toList();
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
              for (final x in upcoming) _TicketTile(ticket: x),
              if (past.isNotEmpty) _Header(t.past),
              for (final x in past) _TicketTile(ticket: x, dim: true),
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

class _TicketTile extends ConsumerWidget {
  const _TicketTile({required this.ticket, this.dim = false});
  final MyTicket ticket;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => context.push('/ticket/${ticket.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 84, height: 84, child: EventCover(url: ticket.coverImageUrl, aspectRatio: 1))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pickLang(lang, ticket.eventTitle, ticket.eventTitleMy), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(formatEventDate(ticket.startsAt, lang), style: theme.textTheme.bodySmall),
                  Text(pickLang(lang, ticket.ticketTypeName, ticket.ticketTypeNameMy), style: theme.textTheme.bodySmall),
                  if (ticket.seatText(lang) != null)
                    Text(ticket.seatText(lang)!, key: Key('seat-${ticket.id}'), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                  if (ticket.isComplimentary)
                    Text(
                      ticket.compLabel == null || ticket.compLabel!.isEmpty ? t.complimentary : t.complimentaryLabel(ticket.compLabel!),
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.brightness == Brightness.dark ? E360DarkColors.success : E360Colors.success),
                    ),
                ]),
              ),
              const Padding(padding: EdgeInsets.only(left: 8, top: 4), child: Icon(Icons.qr_code_2)),
            ]),
          ),
        ),
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
