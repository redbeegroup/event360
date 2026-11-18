import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.idOrSlug});
  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final event = ref.watch(eventProvider(idOrSlug));
    return event.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.event_busy,
          message: e is ApiException && e.status == 404 ? t.noEvents : t.loadError,
          actionLabel: t.retry,
          onAction: () => ref.invalidate(eventProvider(idOrSlug)),
        ),
      ),
      data: (e) => _Detail(event: e),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.event});
  final EventSummary event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final e = event;
    final ended = e.endsAt.isBefore(DateTime.now());
    final cancelled = e.status == 'CANCELLED';
    final description = pickLang(lang, e.description, e.descriptionMy);
    final summary = pickLang(lang, e.summary, e.summaryMy);
    final canRegister = !ended && !cancelled && e.ticketTypes.any((tt) => tt.isFree && !tt.soldOut);

    Widget infoRow(IconData icon, String title, [String? sub]) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: theme.colorScheme.primaryContainer, child: Icon(icon, color: theme.colorScheme.onPrimaryContainer)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub),
        );

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          actions: [
            IconButton(
              tooltip: t.share,
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: '${pickLang(lang, e.title, e.titleMy)}\n${formatEventDate(e.startsAt, lang)}')),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(background: EventCover(url: e.coverImageUrl, aspectRatio: 16 / 10)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList.list(children: [
            if (cancelled) _Banner(text: t.eventCancelled, color: theme.colorScheme.error),
            if (!cancelled && ended) _Banner(text: t.eventEnded, color: theme.colorScheme.outline),
            Wrap(spacing: 6, children: [
              Pill(pickLang(lang, e.categoryName, e.categoryNameMy), color: theme.colorScheme.secondary),
              Pill(formatLabel(t, e.format), color: theme.colorScheme.tertiary),
            ]),
            const SizedBox(height: 10),
            Text(pickLang(lang, e.title, e.titleMy), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (summary.isNotEmpty) ...[const SizedBox(height: 6), Text(summary, style: theme.textTheme.bodyLarge)],
            const SizedBox(height: 12),
            infoRow(Icons.event, formatEventDate(e.startsAt, lang), formatTimeRange(e.startsAt, e.endsAt, lang)),
            if (e.venue != null)
              infoRow(Icons.place_outlined, pickLang(lang, e.venue!.name, e.venue!.nameMy), [e.venue!.address, e.venue!.city].whereType<String>().join(', ')),
            if (e.format == 'ONLINE') infoRow(Icons.live_tv_outlined, t.formatOnline),
            infoRow(e.organizerVerified ? Icons.verified : Icons.groups_outlined, e.organizerName, e.organizerVerified ? t.verified : t.organizer),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.about, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(description),
            ],
            const SizedBox(height: 20),
            Text(t.tickets, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final tt in e.ticketTypes)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(pickLang(lang, tt.name, tt.nameMy)),
                  subtitle: Text(tt.soldOut ? t.soldOut : t.remaining(tt.remaining)),
                  trailing: Text(tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang)),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            if (e.ticketTypes.any((tt) => !tt.isFree)) Text(t.paidSoon, style: theme.textTheme.bodySmall),
          ]),
        ),
      ]),
      bottomNavigationBar: canRegister
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(onPressed: () => _startRegister(context, ref), child: Text(t.registerFree)),
              ),
            )
          : null,
    );
  }

  Future<void> _startRegister(BuildContext context, WidgetRef ref) async {
    final me = await ref.read(sessionProvider.future);
    if (!context.mounted) return;
    if (me == null) {
      await context.push('/login?from=${Uri.encodeComponent('/event/${event.id}')}');
      return;
    }
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _RegisterSheet(event: event));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );
}

class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.event});
  final EventSummary event;
  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  late TicketType _type = widget.event.ticketTypes.firstWhere((t) => t.isFree && !t.soldOut);
  int _qty = 1;
  bool _busy = false;
  String? _error;
  bool _done = false;

  int get _max => [_type.maxPerOrder, _type.remaining].reduce((a, b) => a < b ? a : b);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).register(widget.event.id, _type.id, _qty);
      ref.invalidate(myTicketsProvider);
      ref.invalidate(eventProvider(widget.event.id));
      setState(() => _done = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final free = widget.event.ticketTypes.where((tt) => tt.isFree && !tt.soldOut).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: _done
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(t.registered, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/tickets');
                },
                child: Text(t.viewTickets),
              ),
            ])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(pickLang(lang, widget.event.title, widget.event.titleMy), style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final tt in free)
                RadioListTile<String>(
                  value: tt.id,
                  groupValue: _type.id,
                  onChanged: (_) => setState(() {
                    _type = tt;
                    _qty = 1;
                  }),
                  title: Text(pickLang(lang, tt.name, tt.nameMy)),
                  subtitle: Text(t.remaining(tt.remaining)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('${t.quantity} · ${t.perPersonLimit(_type.maxPerOrder)}')),
                IconButton.outlined(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$_qty', style: theme.textTheme.titleLarge)),
                IconButton.outlined(onPressed: _qty < _max ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add)),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.register),
              ),
            ]),
    );
  }
}
