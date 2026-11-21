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
        color: theme.colorScheme.primary,
        text: t.paymentReceived,
        action: FilledButton(onPressed: () => context.go('/tickets'), child: Text(t.viewTickets)),
      );
    } else if (o.status == 'CANCELLED') {
      body = _Result(icon: Icons.cancel_outlined, color: theme.colorScheme.outline, text: t.orderCancelled, action: OutlinedButton(onPressed: () => context.go('/event/${o.eventId}'), child: Text(t.startAgain)));
    } else if (!o.isOpen) {
      body = _Result(
        key: const Key('expired'),
        icon: Icons.timer_off_outlined,
        color: theme.colorScheme.error,
        text: t.holdExpired,
        action: OutlinedButton(onPressed: () => context.go('/event/${o.eventId}'), child: Text(t.startAgain)),
      );
    } else {
      final methods = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
      final selected = _provider ?? (methods.length == 1 ? methods.single.code : null);
      final action = o.paymentAction;
      final started = action != null;
      body = ListView(padding: const EdgeInsets.all(20), children: [
        Text(pickLang(lang, o.eventTitle, o.eventTitleMy), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final i in o.items) Text(t.orderSummary('${i.quantity}', pickLang(lang, i.name, i.nameMy))),
        if (o.discountMmk > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(t.discount)),
              Text('− ${t.mmk(formatAmount(o.discountMmk, lang))}', key: const Key('discount')),
            ]),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(t.total, style: theme.textTheme.titleMedium)),
          Text(t.mmk(formatAmount(o.totalMmk, lang)), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ]),
        if (o.holdExpiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(child: Text(t.holdExpiresIn(_left(o.holdExpiresAt!)), key: const Key('countdown'))), // wraps on a narrow phone (Myanmar)
            ]),
          ),
        const Divider(height: 32),
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
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: action.qr!, size: 220),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.scanToPay, textAlign: TextAlign.center),
          ] else if (action.openUrl != null)
            OutlinedButton.icon(
              onPressed: () => ref.read(openPaymentUrlProvider)(action.openUrl!),
              icon: const Icon(Icons.open_in_new),
              label: Text(t.openWalletAgain),
            ),
          const SizedBox(height: 16),
          Text(t.payWith, style: theme.textTheme.bodySmall),
        ] else
          Text(t.choosePayment, style: theme.textTheme.titleMedium),
        if (methods.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.paymentNotAvailable)),
        for (final m in methods)
          RadioListTile<String>(
            key: Key('method-${m.code}'),
            value: m.code,
            groupValue: selected,
            onChanged: _busy ? null : (v) => setState(() => _provider = v),
            title: Text(m.label),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('pay'),
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
