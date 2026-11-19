import 'package:event360_core/event360_core.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(t.activity), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: t.retry, onPressed: () => ref.read(checkinProvider.notifier).refresh()),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(checkinProvider.notifier).refresh(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t.attendance(st.checkedIn, st.registered), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (st.pending.isNotEmpty) Text(t.pendingSync(st.pending.length)),
          if (!st.online) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.offlineBanner(st.pending.length))),
          if (s != null) ...[
            const SizedBox(height: 16),
            Text(t.byTicketType, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final tt in s.byTicketType)
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(pickLang(lang, tt.name, tt.nameMy)), trailing: Text('${tt.checkedIn} / ${tt.registered}')),
            const SizedBox(height: 8),
            Text(t.byGate, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (s.byGate.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noScans)),
            for (final g in s.byGate)
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(g.gate ?? t.noGate), trailing: Text('${g.checkedIn}')),
            const SizedBox(height: 8),
            Text(t.recentScans, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (s.recent.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noScans)),
            for (final r in s.recent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.undone ? Icons.undo : (r.duplicate ? Icons.warning_amber_rounded : Icons.check_circle),
                  color: r.undone ? Colors.grey : (r.duplicate ? const Color(0xFFC77700) : const Color(0xFF1B873F)),
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
