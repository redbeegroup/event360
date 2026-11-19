import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Names this device and its gate; both show up in the organizer's reports.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final _gate = TextEditingController(text: ref.read(sessionProvider)?.gate ?? '');
  late final _device = TextEditingController(text: ref.read(sessionProvider)?.deviceName ?? '');

  @override
  void dispose() {
    _gate.dispose();
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final s = ref.watch(sessionProvider);
    final lang = ref.watch(langProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.setupTitle), actions: [
        if (s?.isCode == false)
          IconButton(tooltip: t.chooseEvent, icon: const Icon(Icons.swap_horiz), onPressed: () => ref.read(sessionProvider.notifier).changeEventOrGate()),
        IconButton(tooltip: t.signOut, icon: const Icon(Icons.logout), onPressed: () => ref.read(sessionProvider.notifier).signOut()),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (s?.event != null) ...[
          Text(pickLang(lang, s!.event!.title, s.event!.titleMy), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(formatDayTime(s.event!.startsAt, lang)),
          const SizedBox(height: 20),
        ],
        TextField(controller: _gate, decoration: InputDecoration(labelText: t.gate, hintText: t.gateHint, prefixIcon: const Icon(Icons.door_front_door_outlined))),
        const SizedBox(height: 12),
        TextField(controller: _device, decoration: InputDecoration(labelText: t.deviceName, hintText: t.deviceNameHint, prefixIcon: const Icon(Icons.phone_android))),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(t.startScanning),
          onPressed: () => ref.read(sessionProvider.notifier).setGate(_gate.text, _device.text.trim().isEmpty ? 'Crew device' : _device.text),
        ),
      ]),
    );
  }
}
