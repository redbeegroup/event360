import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Opens a payment URL (wallet checkout page / KBZPay PWA). Overridden in tests.
final openPaymentUrlProvider = Provider<Future<void> Function(String url)>(
  (ref) => (url) async {
    await launchUrl(Uri.parse(url), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication, webOnlyWindowName: '_self');
  },
);

/// Pays a held order: choose a wallet, pay there, and this screen follows the order until it is paid or expires.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.orderId, this.pollInterval = const Duration(seconds: 3)});
  final String orderId;
  final Duration pollInterval;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> with WidgetsBindingObserver {
  Order? _order;
  String? _provider;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(widget.pollInterval, (_) {
      if (_order?.status == 'PENDING_PAYMENT') _load();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _order?.status == 'PENDING_PAYMENT') setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(); // back from the wallet app
  }

  Future<void> _load() async {
    try {
      final o = await ref.read(apiProvider).order(widget.orderId);
      if (!mounted) return;
      final wasOpen = _order?.status == 'PENDING_PAYMENT';
      setState(() {
        _order = o;
        _provider ??= o.paymentProvider;
      });
      if (o.status != 'PENDING_PAYMENT') {
        _poll?.cancel();
        if (wasOpen || o.isPaid) {
          ref.invalidate(myTicketsProvider);
          ref.invalidate(pendingOrdersProvider);
          ref.invalidate(eventProvider(o.eventId));
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pay() async {
    final p = _provider;
    if (p == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Web: the wallet page sends the buyer back to this checkout (the hash route), which then shows the result
      final back = kIsWeb ? Uri.base.replace(fragment: '/checkout/${widget.orderId}').toString() : null;
      final o = await ref.read(apiProvider).payOrder(widget.orderId, p, returnUrl: back);
      if (!mounted) return;
      setState(() => _order = o);
      final url = o.paymentAction?.openUrl;
      if (url != null && o.paymentAction!.type != 'QR') await ref.read(openPaymentUrlProvider)(url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      final o = await ref.read(apiProvider).cancelOrder(widget.orderId);
      ref.invalidate(pendingOrdersProvider);
      if (mounted) setState(() => _order = o);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _left(DateTime until) {
    final d = until.difference(DateTime.now().toUtc());
    if (d.isNegative) return '0:00';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final o = _order;
    Widget body;
    if (o == null) {
      body = _error != null
          ? MessageView(icon: Icons.error_outline, message: _error!, actionLabel: t.retry, onAction: _load)
          : const Center(child: CircularProgressIndicator());
    } else if (o.isPaid) {
      body = _Result(
        key: const Key('paid'),
        icon: Icons.check_circle,
        color: theme.brightness == Brightness.dark ? E360DarkColors.success : E360Colors.success,
        text: t.paymentReceived,
        action: FilledButton(style: E360Buttons.gold, onPressed: () => context.go('/tickets'), child: Text(t.viewTickets)),
      );
    } else if (o.status == 'CANCELLED') {
      body = _Result(
        icon: Icons.cancel_outlined,
        color: theme.colorScheme.outline,
        text: t.orderCancelled,
        action: FilledButton(style: E360Buttons.navy, onPressed: () => context.go('/event/${o.eventId}'), child: Text(t.startAgain)),
      );
    } else if (!o.isOpen) {
      body = _Result(
        key: const Key('expired'),
        icon: Icons.timer_off_outlined,
        color: theme.colorScheme.error,
        text: t.holdExpired,
        action: FilledButton(style: E360Buttons.navy, onPressed: () => context.go('/event/${o.eventId}'), child: Text(t.startAgain)),
      );
    } else {
      final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
      final selected = _provider ?? (methods.length == 1 ? methods.single.code : null);
      final action = o.paymentAction;
      final started = action != null;
      body = ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pickLang(lang, o.eventTitle, o.eventTitleMy), style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final i in o.items) Text(t.orderSummary('${i.quantity}', pickLang(lang, i.name, i.nameMy)), style: theme.textTheme.bodyLarge),
              if (o.discountMmk > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text(t.discount, style: theme.textTheme.bodyLarge)),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                      child: Text('− ${t.mmk(formatAmount(o.discountMmk, lang))}', key: const Key('discount'), textAlign: TextAlign.end, style: theme.textTheme.bodyLarge),
                    ),
                  ]),
                ),
              const Divider(height: 24),
              Row(children: [
                Expanded(child: Text(t.total, style: theme.textTheme.titleMedium)),
                // Large text: a long amount wraps instead of pushing the label out
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                  child: Text(t.mmk(formatAmount(o.totalMmk, lang)), textAlign: TextAlign.end, style: theme.textTheme.headlineSmall),
                ),
              ]),
              if (o.holdExpiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Flexible(child: Text(t.holdExpiresIn(_left(o.holdExpiresAt!)), key: const Key('countdown'), style: theme.textTheme.titleSmall)), // wraps on a narrow phone (Myanmar)
                  ]),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        if (started) ...[
          Row(children: [
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 12),
            Expanded(child: Text(t.waitingForPayment, style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          Text(t.waitingHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          if (action.type == 'QR' && action.qr != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
                child: QrImageView(data: action.qr!, size: 220),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.scanToPay, textAlign: TextAlign.center),
          ] else if (action.openUrl != null)
            OutlinedButton.icon(
              style: E360Buttons.outline,
              onPressed: () => ref.read(openPaymentUrlProvider)(action.openUrl!),
              icon: const Icon(Icons.open_in_new),
              label: Text(t.openWalletAgain),
            ),
          const SizedBox(height: 16),
          Text(t.payWith, style: theme.textTheme.bodySmall),
        ] else
          Text(t.choosePayment, style: theme.textTheme.titleLarge),
        if (methods.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.paymentNotAvailable)),
        const SizedBox(height: 8),
        for (final m in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MethodCard(
              key: Key('method-${m.code}'),
              label: m.label,
              selected: m.code == selected,
              onTap: _busy ? null : () => setState(() => _provider = m.code),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('pay'),
          style: E360Buttons.gold.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54))),
          onPressed: _busy || selected == null || (started && selected == o.paymentProvider && action.type == 'QR')
              ? null
              : () {
                  _provider = selected;
                  _pay();
                },
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(t.payNow(t.mmk(formatAmount(o.totalMmk, lang)))),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _cancel, child: Text(t.cancelOrder)),
      ]);
    }
    return Scaffold(appBar: AppBar(title: Text(t.checkout)), body: body);
  }
}

/// A payment method as a selectable card: 2 px navy border when chosen (like the ticket picker's cards).
class _MethodCard extends StatelessWidget {
  const _MethodCard({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1)),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? scheme.primary : scheme.outline),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({super.key, required this.icon, required this.color, required this.text, required this.action});
  final IconData icon;
  final Color color;
  final String text;
  final Widget action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            action,
          ]),
        ),
      );
}
