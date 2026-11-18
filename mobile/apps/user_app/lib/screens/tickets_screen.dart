import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final session = ref.watch(sessionProvider);
    final tickets = ref.watch(myTicketsProvider);
    final fromCache = ref.read(myTicketsProvider.notifier).fromCache;

    Widget body;
    if (session.value == null && !session.isLoading) {
      body = MessageView(icon: Icons.lock_outline, message: t.signInToRegister, actionLabel: t.signIn, onAction: () => context.push('/login'));
    } else {
      body = tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(myTicketsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return MessageView(icon: Icons.confirmation_number_outlined, message: t.noTickets, actionLabel: t.explore, onAction: () => context.go('/explore'));
          }
          final upcoming = list.where((x) => x.isUpcoming).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = list.where((x) => !x.isUpcoming).toList();
          return RefreshIndicator(
            onRefresh: () => ref.read(myTicketsProvider.notifier).refresh(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (fromCache)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const Icon(Icons.cloud_off, size: 18), const SizedBox(width: 6), Text(t.offlineReady)])),
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
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _TicketTile extends ConsumerWidget {
  const _TicketTile({required this.ticket, this.dim = false});
  final MyTicket ticket;
  final bool dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: () => context.push('/ticket/${ticket.id}'),
          child: Row(children: [
            SizedBox(width: 96, child: EventCover(url: ticket.coverImageUrl, aspectRatio: 1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pickLang(lang, ticket.eventTitle, ticket.eventTitleMy),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(formatEventDate(ticket.startsAt, lang), style: theme.textTheme.bodySmall),
                  Text(pickLang(lang, ticket.ticketTypeName, ticket.ticketTypeNameMy), style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
            const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.qr_code_2)),
          ]),
        ),
      ),
    );
  }
}
