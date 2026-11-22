import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import 'common.dart';

/// Localized order status; an unknown value from a newer API shows as it is.
String orderStatusLabel(L10n t, String s) => switch (s) {
      'PENDING_PAYMENT' => t.orderStatus_PENDING_PAYMENT,
      'PAID' => t.orderStatus_PAID,
      'CONFIRMED' => t.orderStatus_CONFIRMED,
      'EXPIRED' => t.orderStatus_EXPIRED,
      'CANCELLED' => t.orderStatus_CANCELLED,
      'REFUNDED' => t.orderStatus_REFUNDED,
      'FAILED' => t.orderStatus_FAILED,
      _ => s,
    };

// ───────────── Overview ─────────────

class OverviewTab extends ConsumerStatefulWidget {
  const OverviewTab({super.key, required this.k});
  final EventKey k;
  @override
  ConsumerState<OverviewTab> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<OverviewTab> {
  Timer? _timer;
  DateTime _updated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider(widget.k));
    ref.invalidate(attendanceProvider(widget.k));
    ref.invalidate(recentOrdersProvider(widget.k));
    ref.invalidate(waitlistProvider(widget.k));
    if (mounted) setState(() => _updated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final dash = ref.watch(dashboardProvider(widget.k));
    final att = ref.watch(attendanceProvider(widget.k)).value;
    final orders = ref.watch(recentOrdersProvider(widget.k)).value ?? const <RecentOrder>[];
    // A failing waitlist request only hides the card
    final waitlist = ref.watch(waitlistProvider(widget.k)).value;
    return dash.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => loadError(t, _refresh),
      data: (d) {
        final tot = d.totals;
        Widget tile(String label, String value, {String? key}) => StatTile(label: label, value: value, valueKey: key == null ? null : Key(key));
        Widget bar(String name, int value, int of) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(name)), Text('${formatAmount(value, lang)} / ${formatAmount(of, lang)}', style: theme.textTheme.bodySmall)]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: of == 0 ? 0 : value / of, minHeight: 8),
                ),
              ]),
            );
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            // Two tiles per row, as tall as the taller one (long amounts wrap instead of overflowing)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: tile(t.ticketsSold, '${formatAmount(tot.ticketsSold, lang)} / ${formatAmount(tot.capacity, lang)}', key: 'sold')),
                const SizedBox(width: 10),
                Expanded(child: tile(t.revenue, formatMmk(tot.revenueMmk, lang), key: 'revenue')),
              ]),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: tile(t.checkedIn, att == null ? formatAmount(tot.checkedIn, lang) : '${formatAmount(att.checkedIn, lang)} / ${formatAmount(att.registered, lang)}', key: 'checkedIn'),
                ),
                const SizedBox(width: 10),
                Expanded(child: tile(t.orders, formatAmount(tot.orders, lang))),
              ]),
            ),
            const SizedBox(height: 8),
            Text(t.byTicketType, style: theme.textTheme.titleMedium),
            for (final tt in d.ticketTypes) bar(tt.name, tt.sold, tt.quota),
            if (d.seatTotals case final st?) ...[
              const SizedBox(height: 12),
              Text(t.seatsTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Three tiles per row; the label sits on top, the count below it
              LayoutBuilder(builder: (_, c) {
                final w = (c.maxWidth - 2 * 10) / 3;
                return Wrap(key: const Key('seatCounts'), spacing: 10, runSpacing: 10, children: [
                  for (final (label, n) in [(t.seatsAvailable, st.available), (t.seatsHeld, st.held), (t.seatsGuest, st.guest), (t.seatsSold, st.sold), (t.seatsComp, st.comp), if (st.offered > 0) (t.seatsOffered, st.offered)])
                    SizedBox(width: w, child: StatTile(label: label, value: formatAmount(n, lang), small: true)),
                ]);
              }),
            ],
            if (att != null && att.byGate.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.byGate, style: theme.textTheme.titleMedium),
              for (final g in att.byGate)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.door_front_door_outlined), title: Text(g.gate ?? t.noGate), trailing: Text(formatAmount(g.checkedIn, lang))),
            ],
            if (waitlist != null && waitlist.total > 0) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('waitlistCard'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.waitlistTitle, style: theme.textTheme.titleMedium),
                  for (final w in waitlist.types.where((w) => w.waiting + w.offered > 0))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lang == 'my' && (w.nameMy ?? '').isNotEmpty ? w.nameMy! : w.name),
                        Text(t.waitlistLine(formatAmount(w.waiting, lang), formatAmount(w.offered, lang)), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Text(t.recentOrders, style: theme.textTheme.titleMedium),
            if (orders.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noOrders)),
            for (final o in orders.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${o.quantity} × · ${formatMmk(o.totalMmk, lang)}'),
                subtitle: Text([o.buyer ?? '', formatDayTime(o.createdAt, lang)].where((s) => s.isNotEmpty).join(' · ')),
                trailing: E360Badge(orderStatusLabel(t, o.status), kind: o.status == 'PAID' ? E360BadgeKind.success : E360BadgeKind.neutral),
              ),
            const SizedBox(height: 8),
            Text(t.updatedAt(formatTime(_updated, lang)), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}

/// Overview number tile: label on top, the number big in the display font.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.valueKey, this.small = false});
  final String label;
  final String value;
  final Key? valueKey;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final my = Localizations.localeOf(context).languageCode == 'my';
    final size = small ? (my ? 20.0 : 22.0) : (my ? 22.0 : 26.0);
    return Container(
      padding: EdgeInsets.all(small ? 12 : 14),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, key: valueKey, style: theme.textTheme.titleLarge?.copyWith(fontSize: size)),
      ]),
    );
  }
}
