import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lang_button.dart';

/// Organizer accounts sign in with the same email + password as the portal.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(_email.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.appTitle), actions: const [LangButton()]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Align(child: E360Mark(size: 56)),
        const SizedBox(height: 12),
        Text(t.signInTitle, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        TextField(key: const Key('email'), controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: InputDecoration(labelText: t.email)),
        const SizedBox(height: 12),
        TextField(key: const Key('password'), controller: _password, obscureText: true, decoration: InputDecoration(labelText: t.password), onSubmitted: (_) => _submit()),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('signIn'),
          style: E360Buttons.gold,
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.signIn),
        ),
      ]),
    );
  }
}
