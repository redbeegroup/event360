import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/checkin_controller.dart';
import '../l10n/app_localizations.dart';
import 'lang_button.dart';

/// Confirms, then undoes a check-in (needs the server).
Future<void> confirmUndo(BuildContext context, WidgetRef ref, String ticketId, String name) async {
  final t = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(t.undoConfirm(name)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
        FilledButton(style: compactFilled, onPressed: () => Navigator.pop(c, true), child: Text(t.undo)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(checkinProvider.notifier).undo(ticketId);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.undone}: $name')));
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.isNetwork ? t.undoOffline : e.message)));
  }
}
