import 'dart:async';
import 'dart:math';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/waitlist_text.dart';
import '../l10n/app_localizations.dart';
import 'discount_lines.dart';

/// How often `/me/waitlist` is refreshed while the buyer is in a line or holds an offer.
const Duration kWaitlistPoll = Duration(seconds: 30);

/// "23:41" for the time left until [end] (never negative).
String countdownText(DateTime end, DateTime now) {
  final left = end.difference(now);
  final s = left.isNegative ? 0 : left.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Keeps `/me/waitlist` fresh for the whole app shell: when the app comes back to the foreground, and every 30 s while
/// the buyer is in a line or holds an offer (so a new offer shows up without leaving the screen).
class WaitlistSync extends ConsumerStatefulWidget {
  const WaitlistSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<WaitlistSync> createState() => _WaitlistSyncState();
}

class _WaitlistSyncState extends ConsumerState<WaitlistSync> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _active = false; // the buyer is in a line or holds an offer

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(waitlistProvider, (_, next) {
      final entries = next.value;
      if (entries == null) return;
      _active = entries.any((e) => e.isActive);
      _schedule();
    }, fireImmediately: true);
  }

  /// The 30 s timer runs only while there is an active entry and the app is in the foreground.
  void _schedule() {
    if (_active && _foreground) {
      _timer ??= Timer.periodic(kWaitlistPoll, (_) => ref.invalidate(waitlistProvider));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) ref.invalidate(waitlistProvider);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Rebuilds every second while [tickWhen] says so (the countdowns); idle otherwise, so nothing runs when no offer shows.
mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _tick;

  void tickWhen(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

/// "Tickets are waiting for you — 23:41 left". Shown on Home and My Tickets while the buyer has a live offer; tapping it
/// opens checkout (standing types) or the seat picker with the offered seats preselected (seated types).
class OfferBanner extends ConsumerStatefulWidget {
  const OfferBanner({super.key, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4)});
  final EdgeInsets padding;
  @override
  ConsumerState<OfferBanner> createState() => _OfferBannerState();
}

class _OfferBannerState extends ConsumerState<OfferBanner> with _Ticking<OfferBanner> {
  String? _expiredFor;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final entries = ref.watch(waitlistProvider).value ?? const <WaitlistEntry>[];
    final offer = soonestOffer(entries);
    tickWhen(offer != null);
    if (offer == null) {
      // An offer that just ran out: ask the server what happened to it (once)
      final lapsed = entries.where((e) => e.status == 'OFFERED' && e.offerExpiresAt != null).firstOrNull;
      if (lapsed != null && _expiredFor != lapsed.id) {
        _expiredFor = lapsed.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.invalidate(waitlistProvider);
        });
      }
      return const SizedBox.shrink();
    }
    final label = t.offerBanner(countdownText(offer.offerExpiresAt!, offer.serverNow));
    return Padding(
      padding: widget.padding,
      child: Material(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const Key('offerBanner'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => openOffer(context, ref, offer),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(Icons.timer_outlined, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, key: const Key('offerBannerText'), style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onTertiaryContainer)),
                  Text(
                    '${pickLang(ref.watch(langProvider), offer.eventTitle, offer.eventTitleMy)} · ${pickLang(ref.watch(langProvider), offer.ticketTypeName, offer.ticketTypeNameMy)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onTertiaryContainer),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Buys from [offer]: seated types open the seat picker with the offered seats preselected, standing types open the
/// order sheet; either way the order carries the offer's `waitlistEntryId`. Any OFFERED entry is "buy now", whatever
/// order id it carries (a reopened offer keeps the cancelled order's id).
Future<void> openOffer(BuildContext context, WidgetRef ref, WaitlistEntry offer) async {
  if (offer.isSeated) {
    await context.push('/event/${offer.eventId}/seats?offer=${offer.id}');
    ref.invalidate(waitlistProvider);
    return;
  }
  final orderId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => OfferSheet(entry: offer),
  );
  ref.invalidate(waitlistProvider);
  if (orderId != null && context.mounted) await context.push('/checkout/$orderId');
}

/// Order sheet for a standing-type offer: up to the offered quantity of the type, then checkout.
class OfferSheet extends ConsumerStatefulWidget {
  const OfferSheet({super.key, required this.entry});
  final WaitlistEntry entry;
  @override
  ConsumerState<OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends ConsumerState<OfferSheet> {
  // Same key for retries of this sheet: the API returns the same order instead of taking stock twice
  final String _idempotencyKey = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  late int _qty = max(1, widget.entry.offeredQty);
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The event may have been cached before a price step took effect: fetch it again for the total
    Future.microtask(() {
      if (mounted) ref.invalidate(eventProvider(widget.entry.eventId));
    });
  }

  Future<void> _submit() async {
    final e = widget.entry;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await ref.read(apiProvider).createOrder(e.eventId, {e.ticketTypeId: _qty}, idempotencyKey: '$_idempotencyKey-$_qty', waitlistEntryId: e.id);
      ref.invalidate(eventProvider(e.eventId));
      if (o.isPaid) {
        ref.invalidate(myTicketsProvider);
        ref.invalidate(waitlistProvider);
        if (mounted) {
          Navigator.of(context).pop();
          context.go('/tickets');
        }
      } else {
        ref.invalidate(pendingOrdersProvider);
        if (mounted) Navigator.of(context).pop(o.id); // → checkout
      }
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = waitlistErrorText(L10n.of(context), err));
      if (err.status == 409 || err.status == 404) ref.invalidate(waitlistProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final e = widget.entry;
    final live = e.isOffered;
    final ev = ref.watch(eventProvider(e.eventId));
    // Only a fresh fetch prices the total (not the cached event while it reloads)
    final event = ev.isLoading ? null : ev.value;
    final tt = event?.ticketTypes.where((x) => x.id == e.ticketTypeId).firstOrNull;
    final max_ = max(1, e.offeredQty);
    // An estimate, worked out like checkout (current price, group discount); the order's own total is authoritative
    final view = tt == null || tt.isFree
        ? null
        : resolveDiscount(tiers: event!.groupDiscounts, paidQty: _qty, paidSubtotalMmk: tt.priceMmk * _qty, totalMmk: tt.priceMmk * _qty);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.offerSheetTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${pickLang(lang, e.eventTitle, e.eventTitleMy)} · ${pickLang(lang, e.ticketTypeName, e.ticketTypeNameMy)}', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(live ? t.offerSheetHint(e.offeredQty, countdownText(e.offerExpiresAt!, e.serverNow)) : t.offerEnded, key: const Key('offerSheetHint')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(t.quantity)),
          IconButton.outlined(key: const Key('offerMinus'), onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$_qty', key: const Key('offerQty'), style: theme.textTheme.titleLarge)),
          IconButton.outlined(key: const Key('offerPlus'), onPressed: _qty < max_ ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add)),
        ]),
        if (view != null) ...[
          DiscountLines(view: view, lang: lang),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text(t.offerTotalEstimate, style: theme.textTheme.titleMedium)),
              Text(t.mmk(formatAmount(view.totalMmk, lang)), key: const Key('offerTotal'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const Key('offerError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('offerSubmit'),
          onPressed: _busy || !live ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(tt != null && tt.isFree ? t.register : t.checkout),
        ),
      ]),
    );
  }
}

/// Countdown line for the seat picker: "Reserved for you · 23:41 left".
class OfferCountdown extends StatefulWidget {
  const OfferCountdown({super.key, required this.entry, required this.onExpired});
  final WaitlistEntry entry;
  final VoidCallback onExpired;
  @override
  State<OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<OfferCountdown> with _Ticking<OfferCountdown> {
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    tickWhen(true);
    final over = !widget.entry.isOffered;
    if (over && !_fired) {
      _fired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onExpired());
    }
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.onTertiaryContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            over ? t.offerEnded : t.reservedForYouLeft(countdownText(widget.entry.offerExpiresAt!, widget.entry.serverNow)),
            key: const Key('offerCountdown'),
            style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onTertiaryContainer),
          ),
        ),
      ]),
    );
  }
}
