import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';

/// Colour + headline for a scan result.
({Color color, IconData icon, String title}) resultStyle(L10n t, ScanOutcome o) => switch (o.result) {
      'ACCEPTED' => (color: const Color(0xFF1B873F), icon: Icons.check_circle, title: t.resultAccepted),
      'ALREADY_CHECKED_IN' => (color: const Color(0xFFC77700), icon: Icons.warning_amber_rounded, title: t.resultDuplicate),
      'WRONG_EVENT' => (color: const Color(0xFFC62828), icon: Icons.event_busy, title: t.resultWrongEvent),
      'VOID' => (color: const Color(0xFFC62828), icon: Icons.block, title: t.resultVoid),
      'REFUNDED' => (color: const Color(0xFFC62828), icon: Icons.money_off, title: t.resultRefunded),
      'TRANSFERRED' => (color: const Color(0xFFC62828), icon: Icons.swap_horiz, title: t.resultTransferred),
      'NO_OFFLINE_DATA' => (color: const Color(0xFF555555), icon: Icons.cloud_off, title: t.loadError),
      _ => (color: const Color(0xFFC62828), icon: Icons.cancel, title: o.reason == 'outdated_qr' ? t.outdatedQr : t.resultInvalid),
    };

/// Big, glanceable result of the last scan.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.outcome, required this.lang, this.onUndo, this.onClose});
  final ScanOutcome outcome;
  final String lang;
  final VoidCallback? onUndo;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final s = resultStyle(t, outcome);
    final tk = outcome.ticket;
    final ci = tk?.checkedIn;
    final details = <String>[
      if (outcome.result == 'ALREADY_CHECKED_IN' && ci != null)
        [t.checkedInAt(formatTime(ci.at, lang)), if (ci.gate != null && ci.gate!.isNotEmpty) t.atGate(ci.gate!), if (ci.by != null) t.byWho(ci.by!)].join(' '),
      if (outcome.otherEventTitle != null) t.otherEvent(outcome.otherEventTitle!),
      if (outcome.reason == 'not_in_list') t.notInList,
      if (outcome.offline) t.offlineChecked,
    ];
    return Material(
      color: s.color,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(s.icon, color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(s.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white))),
              ]),
              if (tk != null) ...[
                const SizedBox(height: 10),
                Text(tk.holderName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('${pickLang(lang, tk.ticketTypeName, tk.ticketTypeNameMy)} · #${tk.code}', style: const TextStyle(fontSize: 15, color: Colors.white)),
              ],
              for (final d in details) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d, style: const TextStyle(color: Colors.white))),
              if (onUndo != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo),
                    label: Text(t.undo),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
