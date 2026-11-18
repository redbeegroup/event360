import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.returnTo});
  final String? returnTo;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _devCode;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String _message(L10n t, ApiException e) => e.isRateLimited ? t.tooManyCodes : (e.isNetwork ? t.loadError : e.message);

  Future<void> _send() async {
    final t = L10n.of(context);
    if (!isValidMyanmarPhone(_phone.text)) return setState(() => _error = t.invalidPhone);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _devCode = await ref.read(apiProvider).requestOtp(_phone.text);
      setState(() => _codeSent = true);
    } on ApiException catch (e) {
      setState(() => _error = _message(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final t = L10n.of(context);
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) return setState(() => _error = t.invalidCode);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).verifyOtp(_phone.text, _code.text);
      await ref.read(sessionProvider.notifier).signedIn();
      ref.invalidate(myTicketsProvider);
      if (!mounted) return;
      if (widget.returnTo != null) {
        context.pop();
      } else {
        context.go('/tickets');
      }
    } on ApiException catch (e) {
      setState(() => _error = _message(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.signIn)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Icon(Icons.phone_iphone, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(_codeSent ? t.codeSentTo(_phone.text) : t.signInToRegister, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (!_codeSent)
            TextField(
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]'))],
              decoration: InputDecoration(labelText: t.phoneNumber, hintText: t.phoneHint, prefixIcon: const Icon(Icons.phone)),
              onSubmitted: (_) => _send(),
            )
          else ...[
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: InputDecoration(labelText: t.code, counterText: ''),
              onSubmitted: (_) => _verify(),
            ),
            if (_devCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t.devCode(_devCode!), textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.tertiary)),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                        _devCode = null;
                      }),
              child: Text(t.changeNumber),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _verify : _send),
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(_codeSent ? t.verify : t.sendCode),
          ),
        ]),
      ),
    );
  }
}
