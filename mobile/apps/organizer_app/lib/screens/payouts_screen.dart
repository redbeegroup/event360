import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event/common.dart';
import 'event/overview_tab.dart' show StatTile;

String _methodText(L10n t, String m) => switch (m) {
      'BANK' => t.methodBANK,
      'KBZPAY' => 'KBZPay',
      'WAVEPAY' => 'WavePay',
      'CASH' => t.paymentCash,
      'OTHER' => t.methodOTHER,
      _ => m,
    };

/// What the organization has earned, been paid and is owed, by event and by payout. View only.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final org = ref.watch(currentOrgProvider);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t.payouts),
      if (org != null) Text(org.name, key: const Key('payoutsOrg'), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
    ]);
    if (org == null || !org.canSeePayouts) {
      return Scaffold(appBar: AppBar(title: title), body: const SizedBox());
    }
    final provider = payoutSummaryProvider(org.id);
    final summary = ref.watch(provider);

    Future<void> refresh() async {
      final messenger = ScaffoldMessenger.of(context);
      final message = t.refreshFailed;
      ref.invalidate(provider);
      try {
        await ref.read(provider.future);
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    }

    final data = summary.value;
    return Scaffold(
      appBar: AppBar(title: title),
      body: data == null
          ? (summary.hasError ? loadError(t, () => ref.invalidate(provider)) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: refresh, child: _Body(summary: data, lang: lang)),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary, required this.lang});
  final PayoutSummary summary;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final s = summary;
    final owing = s.owedMmk < 0;
    Widget tile(String key, String label, String value) => StatTile(label: label, value: value, oneLine: true, valueKey: Key(key));
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]),
        );
    return ListView(
      key: const Key('payoutsList'),
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        pair(tile('payoutTile-earned', t.earned, formatMmk(s.earnedMmk, lang)), tile('payoutTile-paidOut', t.paidOut, formatMmk(s.paidOutMmk, lang))),
        const SizedBox(height: 10),
        owing
            ? tile('payoutTile-owed', t.balance, t.youOwe(formatMmk(-s.owedMmk, lang)))
            : tile('payoutTile-owed', t.owedToYou, formatMmk(s.owedMmk, lang)),
        const SizedBox(height: 16),
        Text(t.byEvent, style: theme.textTheme.titleMedium),
        if (s.events.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.noSalesYet, key: const Key('noSalesYet'), style: theme.textTheme.bodyMedium))
        else
          for (final e in s.events) _EventRow(row: e, lang: lang),
        if (!s.reconciled)
          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(t.reconcileNote, key: const Key('reconcileNote'), style: theme.textTheme.bodySmall)),
        const SizedBox(height: 16),
        Text(t.payoutHistory, style: theme.textTheme.titleMedium),
        if (s.payouts.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.noPayouts, key: const Key('noPayouts'), style: theme.textTheme.bodyMedium))
        else
          for (final p in s.payouts) _PayoutRowTile(row: p, lang: lang),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.row, required this.lang});
  final PayoutEventRow row;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    // The lines read as a sum: sales before refunds, minus refunded, minus commission, equals net.
    Widget line(String id, String label, int v, {bool minus = false, bool bold = false, bool quiet = false}) {
      final style = bold ? theme.textTheme.titleSmall : quiet ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant) : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Flexible(child: Text(minus ? '− ${formatMmk(v, lang)}' : formatMmk(v, lang), key: Key('payoutLine-$id-${row.eventId}'), textAlign: TextAlign.end, style: style)),
        ]),
      );
    }

    return ExpansionTile(
      key: Key('payoutEvent-${row.eventId}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8, right: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(row.title, style: theme.textTheme.titleSmall),
      subtitle: Text(formatMmk(row.netMmk, lang), key: Key('payoutNet-${row.eventId}'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      children: [
        line('gross', t.salesBeforeRefunds, row.grossMmk),
        line('refunds', t.refundedAmount, row.refundsMmk, minus: true),
        line('commission', t.commission, row.commissionMmk, minus: true),
        const Divider(height: 12),
        line('net', t.netToYou, row.netMmk, bold: true),
        const SizedBox(height: 4),
        line('discounts', t.discountsIncluded, row.discountMmk, quiet: true),
      ],
    );
  }
}

class _PayoutRowTile extends StatelessWidget {
  const _PayoutRowTile({required this.row, required this.lang});
  final PayoutRow row;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final voided = row.isVoided;
    final strike = voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    Widget text(String s, {TextStyle? style, Key? key}) => Text(s, key: key, style: (style ?? theme.textTheme.bodyMedium)?.merge(strike));
    final ref = row.reference, note = row.note;
    return Container(
      key: Key('payoutRow-${row.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        text(formatMmk(row.amountMmk, lang), style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        text('${formatDate(row.paidAt, lang)} · ${_methodText(t, row.method)}', style: theme.textTheme.bodySmall),
        if (ref != null && ref.isNotEmpty) text('${t.reference}: $ref', style: theme.textTheme.bodySmall),
        if (note != null && note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: text(note)),
        if (voided)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              E360Badge(t.voided, kind: E360BadgeKind.neutral),
              if (row.voidReason != null) Text(row.voidReason!, key: Key('voidReason-${row.id}'), style: theme.textTheme.bodySmall),
            ]),
          ),
      ]),
    );
  }
}
