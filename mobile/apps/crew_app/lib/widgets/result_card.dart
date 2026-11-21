import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';

/// Colour, ink, icon and headline for a scan result. Accepted is success, already-checked-in is the amber tone,
/// everything that turns a guest away is danger. The icon and headline carry the meaning too, never colour alone.
({Color color, Color onColor, IconData icon, String title}) resultStyle(L10n t, ScanOutcome o, {Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final success = dark ? E360DarkColors.success : E360Colors.success;
  final amber = dark ? E360DarkColors.amberInk : E360Colors.amberInk;
  final danger = dark ? E360DarkColors.danger : E360Colors.danger;
  final neutral = dark ? E360DarkColors.muted : E360Colors.muted;
  final on = dark ? E360DarkColors.paper : Colors.white;
  ({Color color, Color onColor, IconData icon, String title}) s(Color c, IconData i, String title) => (color: c, onColor: on, icon: i, title: title);
  return switch (o.result) {
    'ACCEPTED' => s(success, Icons.check_circle, t.resultAccepted),
    'ALREADY_CHECKED_IN' => s(amber, Icons.warning_amber_rounded, t.resultDuplicate),
    'WRONG_EVENT' => s(danger, Icons.event_busy, t.resultWrongEvent),
    'VOID' => s(danger, Icons.block, t.resultVoid),
    'REFUNDED' => s(danger, Icons.money_off, t.resultRefunded),
    'TRANSFERRED' => s(danger, Icons.swap_horiz, t.resultTransferred),
    'NO_OFFLINE_DATA' => s(neutral, Icons.cloud_off, t.loadError),
    _ => s(danger, Icons.cancel, o.reason == 'outdated_qr' ? t.outdatedQr : t.resultInvalid),
  };
}

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
    final theme = Theme.of(context);
    final s = resultStyle(t, outcome, brightness: theme.brightness);
    final tk = outcome.ticket;
    final ci = tk?.checkedIn;
    final details = <String>[
      if (outcome.result == 'ALREADY_CHECKED_IN' && ci != null)
        [t.checkedInAt(formatTime(ci.at, lang)), if (ci.gate != null && ci.gate!.isNotEmpty) t.atGate(ci.gate!), if (ci.by != null) t.byWho(ci.by!)].join(' '),
      if (outcome.otherEventTitle != null) t.otherEvent(outcome.otherEventTitle!),
      if (outcome.reason == 'not_in_list') t.notInList,
      if (outcome.offline) t.offlineChecked,
    ];
    final ink = s.onColor;
    return Material(
      color: s.color,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: const Color(0x66000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: DefaultTextStyle(
            style: TextStyle(color: ink),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(s.icon, color: ink, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(s.title, key: const Key('resultTitle'), style: theme.textTheme.titleLarge?.copyWith(fontSize: 24, color: ink))),
              ]),
              if (tk != null) ...[
                const SizedBox(height: 10),
                if (tk.seat != null && tk.seat!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(pickLang(lang, tk.seat, tk.seatMy), key: const Key('resultSeat'), style: theme.textTheme.titleLarge?.copyWith(fontSize: 28, color: ink)),
                  ),
                Text(tk.holderName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
                Text('${pickLang(lang, tk.ticketTypeName, tk.ticketTypeNameMy)} · #${tk.code}', style: TextStyle(fontSize: 15, color: ink)),
              ],
              for (final d in details) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d, style: TextStyle(color: ink))),
              if (onUndo != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: ink),
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
