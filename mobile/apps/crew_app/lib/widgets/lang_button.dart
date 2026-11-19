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

/// The shared theme makes filled buttons full-width; use this for buttons inside rows, list tiles and dialogs.
final compactFilled = FilledButton.styleFrom(minimumSize: const Size(64, 44));
