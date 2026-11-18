import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';

/// First-run language choice (shown in both languages, since we don't know which one yet).
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});
  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  String _lang = 'my';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(String code, String label, String sub) => Card(
          child: RadioListTile<String>(
            value: code,
            groupValue: _lang,
            onChanged: (v) => setState(() => _lang = v!),
            title: Text(label, style: theme.textTheme.titleMedium),
            subtitle: Text(sub),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            Icon(Icons.celebration, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Event 360', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('ဘာသာစကား ရွေးချယ်ပါ · Choose your language', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 32),
            option('my', 'မြန်မာ', 'Myanmar'),
            const SizedBox(height: 12),
            option('en', 'English', 'အင်္ဂလိပ်'),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                await ref.read(localeProvider.notifier).set(_lang);
                if (context.mounted) context.go('/');
              },
              child: Text(_lang == 'my' ? 'ဆက်လက်မည်' : 'Continue'),
            ),
          ]),
        ),
      ),
    );
  }
}
