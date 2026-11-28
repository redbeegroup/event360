import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Signing out can take a few seconds without a network (push removal waits up to 5 s): the button is busy meanwhile and cannot be tapped twice.
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(sessionProvider.notifier).signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final me = ref.watch(sessionProvider).value;
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final languageSwitch = SegmentedButton<String>(
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
    );
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
              // Large text: the switch moves under the label instead of squeezing beside it
              trailing: large ? null : languageSwitch,
              subtitle: large ? Align(alignment: AlignmentDirectional.centerStart, child: languageSwitch) : null,
            ),
          ]),
        ),
        const SizedBox(height: 20),
        if (me == null)
          FilledButton(style: E360Buttons.gold, onPressed: () => context.push('/login'), child: Text(t.signIn))
        else
          OutlinedButton.icon(
            style: E360Buttons.outline.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52))),
            icon: _signingOut
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(key: Key('signOutBusy'), strokeWidth: 2))
                : const Icon(Icons.logout),
            label: Text(t.signOut),
            onPressed: _signingOut ? null : _signOut,
          ),
      ]),
    );
  }
}
