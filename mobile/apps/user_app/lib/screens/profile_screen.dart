import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final me = ref.watch(sessionProvider).value;
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.profile)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Column(children: [
            ListTile(
              minTileHeight: 64,
              leading: CircleAvatar(backgroundColor: scheme.primaryContainer, foregroundColor: scheme.onPrimaryContainer, child: const Icon(Icons.person)),
              title: Text(me == null ? t.notSignedIn : (me.displayName ?? me.phone ?? ''), style: theme.textTheme.titleMedium),
              subtitle: me?.phone == null ? null : Text(t.signedInAs(me!.phone!)),
            ),
            const Divider(),
            ListTile(
              minTileHeight: 64,
              leading: Icon(Icons.translate, color: scheme.primary),
              title: Text(t.language, style: theme.textTheme.titleMedium),
              trailing: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: scheme.primary,
                  selectedForegroundColor: scheme.onPrimary,
                  side: BorderSide(color: scheme.outlineVariant),
                  minimumSize: const Size(44, 44),
                ),
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'my', label: Text('မြန်မာ')), ButtonSegment(value: 'en', label: Text('EN'))],
                selected: {lang},
                onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        if (me == null)
          FilledButton(style: E360Buttons.gold, onPressed: () => context.push('/login'), child: Text(t.signIn))
        else
          OutlinedButton.icon(
            style: E360Buttons.outline.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52))),
            icon: const Icon(Icons.logout),
            label: Text(t.signOut),
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          ),
      ]),
    );
  }
}
