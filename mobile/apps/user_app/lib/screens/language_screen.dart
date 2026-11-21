import 'package:event360_ui/event360_ui.dart';
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
    Widget option(String code, String label, String sub) {
      final on = _lang == code;
      final scheme = theme.colorScheme;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2 : 1)),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onTap: () => setState(() => _lang = code),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      Text(sub, style: theme.textTheme.bodySmall),
                    ]),
                  ),
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? scheme.primary : scheme.outline),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Align(child: E360Mark(size: 64)),
            const SizedBox(height: 16),
            Text('Event 360', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('ဘာသာစကား ရွေးချယ်ပါ · Choose your language', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 32),
            option('my', 'မြန်မာ', 'Myanmar'),
            const SizedBox(height: 12),
            option('en', 'English', 'အင်္ဂလိပ်'),
            const Spacer(),
            FilledButton(
              style: E360Buttons.gold,
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
