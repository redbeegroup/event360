import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lang_button.dart';
import '../widgets/qr_scanner_view.dart';

/// Crew account (email + password) or a volunteer event code (typed or scanned from the organizer's QR).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialCode != null ? 1 : 0);
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _code = TextEditingController(text: widget.initialCode == null ? '' : extractEventCode(widget.initialCode!) ?? widget.initialCode);
  final _device = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _device.text = ref.read(sessionProvider)?.deviceName ?? '';
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _code, _device]) {
      c.dispose();
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanCode() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _CodeScanPage()));
    final code = raw == null ? null : extractEventCode(raw);
    if (code != null) setState(() => _code.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final session = ref.read(sessionProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.signInTitle),
        actions: const [LangButton()],
        bottom: TabBar(controller: _tabs, tabs: [Tab(text: t.tabAccount), Tab(text: t.tabCode)]),
      ),
      body: TabBarView(controller: _tabs, children: [
        ListView(padding: const EdgeInsets.all(20), children: [
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 20), child: Align(child: E360Mark(size: 56))),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: InputDecoration(labelText: t.email)),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: t.password), onSubmitted: (_) => _run(() => session.signInWithAccount(_email.text, _password.text))),
          const SizedBox(height: 16),
          if (_error != null && _tabs.index == 0) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton(style: E360Buttons.gold, onPressed: _busy ? null : () => _run(() => session.signInWithAccount(_email.text, _password.text)), child: Text(t.signIn)),
        ]),
        ListView(padding: const EdgeInsets.all(20), children: [
          const Padding(padding: EdgeInsets.only(top: 4, bottom: 20), child: Align(child: E360Mark(size: 56))),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22, letterSpacing: 3),
            decoration: InputDecoration(labelText: t.eventCode, hintText: t.eventCodeHint),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(style: E360Buttons.outline, onPressed: _scanCode, icon: const Icon(Icons.qr_code_scanner), label: Text(t.scanCodeQr)),
          const SizedBox(height: 12),
          TextField(controller: _device, decoration: InputDecoration(labelText: t.deviceName, hintText: t.deviceNameHint)),
          const SizedBox(height: 16),
          if (_error != null && _tabs.index == 1) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton(
            style: E360Buttons.gold,
            onPressed: _busy
                ? null
                : () => _run(() => session.redeemCode(extractEventCode(_code.text) ?? _code.text, _device.text.trim().isEmpty ? 'Crew device' : _device.text)),
            child: Text(t.useCode),
          ),
        ]),
      ]),
    );
  }
}

class _CodeScanPage extends StatelessWidget {
  const _CodeScanPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).scanCodeQr)),
        body: QrScannerView(onCode: (v) => Navigator.of(context).pop(v)),
      );
}
