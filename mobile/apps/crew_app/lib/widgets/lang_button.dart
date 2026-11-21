import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Toggles Myanmar / English.
class LangButton extends ConsumerWidget {
  const LangButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
        onPressed: () => ref.read(langProvider.notifier).toggle(),
        child: Text(ref.watch(langProvider) == 'my' ? 'English' : 'မြန်မာ'),
      );
}

/// The shared theme makes filled buttons full-width; use this (a compact navy pill) for buttons inside rows, list tiles and dialogs.
final compactFilled = E360Buttons.navy.merge(FilledButton.styleFrom(minimumSize: const Size(64, 44), padding: const EdgeInsets.symmetric(horizontal: 18), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)));
