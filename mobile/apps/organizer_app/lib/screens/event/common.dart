import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

Widget loadError(L10n t, VoidCallback retry) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: retry);

Widget readOnly(BuildContext context, L10n t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [const Icon(Icons.lock_outline, size: 18), const SizedBox(width: 6), Expanded(child: Text(t.readOnly, style: Theme.of(context).textTheme.bodySmall))]),
    );
