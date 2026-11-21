import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/checkin_controller.dart';
import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/undo.dart';

/// Attendance by ticket type and gate, plus the latest scans with Undo.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final st = ref.watch(checkinProvider);
    final s = st.stats;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final okInk = dark ? E360DarkColors.success : E360Colors.success;
    final warnInk = dark ? E360DarkColors.amberInk : E360Colors.amberInk;
    final pct = st.registered == 0 ? 0.0 : (st.checkedIn / st.registered).clamp(0.0, 1.0);
    Widget heading(String text) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 6), child: Text(text, style: theme.textTheme.titleMedium));
    Widget row(Widget title, Widget trailing) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [Expanded(child: title), const SizedBox(width: 12), trailing]),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t.activity), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: t.retry, onPressed: () => ref.read(checkinProvider.notifier).refresh()),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(checkinProvider.notifier).refresh(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Attendance tile: the headline number in the display font, with a progress bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.attendance(st.checkedIn, st.registered), style: theme.textTheme.titleLarge?.copyWith(fontSize: 26)),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: pct, minHeight: 8, borderRadius: BorderRadius.circular(8), color: okInk, backgroundColor: theme.colorScheme.surfaceContainerHighest),
              if (st.pending.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(t.pendingSync(st.pending.length), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
              if (!st.online) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.offlineBanner(st.pending.length), style: theme.textTheme.bodySmall?.copyWith(color: warnInk, fontWeight: FontWeight.w600))),
            ]),
          ),
          if (s != null) ...[
            heading(t.byTicketType),
            for (final tt in s.byTicketType) row(Text(pickLang(lang, tt.name, tt.nameMy)), Text('${tt.checkedIn} / ${tt.registered}', style: theme.textTheme.titleSmall)),
            heading(t.byGate),
            if (s.byGate.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noScans)),
            for (final g in s.byGate) row(Text(g.gate ?? t.noGate), Text('${g.checkedIn}', style: theme.textTheme.titleSmall)),
            heading(t.recentScans),
            if (s.recent.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noScans)),
            for (final r in s.recent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.undone ? Icons.undo : (r.duplicate ? Icons.warning_amber_rounded : Icons.check_circle),
                  color: r.undone ? theme.colorScheme.onSurfaceVariant : (r.duplicate ? warnInk : okInk),
                ),
                title: Text(r.holderName, style: TextStyle(decoration: r.undone ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  formatTime(r.at, lang),
                  pickLang(lang, r.ticketTypeName, r.ticketTypeNameMy),
                  if (r.gate != null) r.gate!,
                  if (r.by != null) r.by!,
                  if (r.duplicate) t.duplicate,
                  if (r.method == 'MANUAL') t.manual,
                  if (r.offline) t.offline,
                  if (r.undone) t.undone,
                ].join(' · ')),
                trailing: !r.undone && !r.duplicate && r.ticketStatus == 'CHECKED_IN'
                    ? TextButton(onPressed: () => confirmUndo(context, ref, r.ticketId, r.holderName), child: Text(t.undo))
                    : null,
              ),
          ] else if (st.online)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }
}
