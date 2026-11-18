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
    return Scaffold(
      appBar: AppBar(title: Text(t.profile)),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(me == null ? t.notSignedIn : (me.displayName ?? me.phone ?? '')),
          subtitle: me?.phone == null ? null : Text(t.signedInAs(me!.phone!)),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text(t.language),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'my', label: Text('မြန်မာ')), ButtonSegment(value: 'en', label: Text('EN'))],
            selected: {lang},
            onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
          ),
        ),
        const Divider(),
        if (me == null)
          ListTile(leading: const Icon(Icons.login), title: Text(t.signIn), onTap: () => context.push('/login'))
        else
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(t.signOut),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
      ]),
    );
  }
}
