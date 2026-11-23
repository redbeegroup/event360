import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import 'common.dart';
import 'overview_tab.dart' show StatTile, orderStatusLabel;

/// Localized order status; an unknown value from a newer API shows as it is.
String orderStatusText(L10n t, String status) => orderStatusLabel(t, status);

/// Inside Sales an order waiting for payment reads like its filter chip.
String _salesStatus(L10n t, String status) => status == 'PENDING_PAYMENT' ? t.filterPending : orderStatusText(t, status);

/// Refunds are shown in plain words: PENDING and FAILED are still being worked on.
String refundStateText(L10n t, String status) => switch (status) {
      'PENDING' || 'FAILED' => t.refundInProgress,
      'MANUAL' => t.refundByHand,
      'SUCCEEDED' => t.refundDone,
      _ => status,
    };

String _paymentStatusText(L10n t, String status) => switch (status) {
      'SUCCEEDED' => t.orderStatus_PAID,
      'INITIATED' || 'PENDING' => t.filterPending,
      'FAILED' => t.orderStatus_FAILED,
      'EXPIRED' => t.orderStatus_EXPIRED,
      'REFUNDED' => t.orderStatus_REFUNDED,
      _ => status,
    };

String _providerText(L10n t, String code) => switch (code) {
      'KBZPAY' => 'KBZPay',
      'WAVEPAY' => 'WavePay',
      'CBPAY' => 'CB Pay',
      'AYAPAY' => 'AYA Pay',
      'CB_MPGS' => t.paymentCard,
      'MPU' => 'MPU',
      'CASH' => t.paymentCash,
      _ => code,
    };

const _pageSize = 30;
const _debounce = Duration(milliseconds: 350);

/// (chip key suffix, API status value)
const _filters = <(String, String?)>[('all', null), ('paid', 'paid'), ('refunded', 'refunded'), ('pending', 'pending'), ('incomplete', 'incomplete')];

String _filterLabel(L10n t, String id) => switch (id) {
      'paid' => t.filterPaid,
      'refunded' => t.filterRefunded,
      'pending' => t.filterPending,
      'incomplete' => t.filterIncomplete,
      _ => t.filterAll,
    };

E360BadgeKind _statusKind(String status) => status == 'PAID' || status == 'CONFIRMED' ? E360BadgeKind.success : E360BadgeKind.neutral;

/// "Hold ends 6:00 PM" while it runs, "Hold ended ..." after; the date is added when the hold is not on today's date.
String holdLine(L10n t, DateTime hold, DateTime now, String lang) {
  final today = toYangon(now), day = toYangon(hold);
  final sameDay = today.year == day.year && today.month == day.month && today.day == day.day;
  final text = sameDay ? formatTime(hold, lang) : formatDayTime(hold, lang);
  return hold.isAfter(now) ? t.holdUntil(text) : t.holdEnded(text);
}

/// Sales totals and ticket types (Summary), and a searchable, paged list of orders (Orders). View only.
class SalesTab extends ConsumerStatefulWidget {
  const SalesTab({super.key, required this.k, this.openOrders, this.shown});
  final EventKey k;

  /// Counts the times this tab became the visible one again; the event screen owns it.
  final ValueNotifier<int>? shown;

  /// Counts requests to show the Orders view (the Overview link); the event screen owns it.
  final ValueNotifier<int>? openOrders;
  @override
  ConsumerState<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends ConsumerState<SalesTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  // After a quiet refetch the triggers (Orders link, tab shown again) wait this long before the next one.
  Timer? _cooling;
  bool _showOrders = false;
  bool _totalsFailed = false;

  // Order list state. [_seq] numbers each request series; an answer that is not the latest is dropped.
  String _typed = '';
  String _query = '';
  String _filter = 'all';
  List<OrgOrderRow> _rows = const [];
  String? _nextCursor;
  bool _started = false;
  bool _loading = true;
  bool _error = false;
  bool _moreFailed = false;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    // A cached answer from an earlier visit would sit under a fresh order list
    if (ref.exists(eventSalesProvider(widget.k))) {
      // (After the frame: this tab can be rebuilt while the page is being built.)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(eventSalesProvider(widget.k));
      });
    }
    final n = widget.openOrders;
    if (n != null) {
      _showOrders = n.value > 0;
      n.addListener(_onOpenOrders);
    }
    widget.shown?.addListener(_quietRefetch);
  }

  @override
  void dispose() {
    widget.openOrders?.removeListener(_onOpenOrders);
    widget.shown?.removeListener(_quietRefetch);
    _timer?.cancel();
    _cooling?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onOpenOrders() {
    if (!mounted) return;
    setState(() => _showOrders = true);
    _quietRefetch();
  }

  /// This tab is kept alive, so it would otherwise show what it fetched on the last visit. Totals and the first
  /// page are fetched again without blanking the rows; at most once every 5 seconds.
  void _quietRefetch() {
    if (!mounted || _cooling?.isActive == true) return;
    _cooling = Timer(const Duration(seconds: 5), () {});
    ref.invalidate(eventSalesProvider(widget.k));
    if (_started) _loadFirst(keep: true);
  }

  String? get _status => _filters.firstWhere((f) => f.$1 == _filter).$2;

  /// Returns false when the request failed (the earlier rows stay when [keep] is set).
  Future<bool> _loadFirst({bool keep = false}) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = false;
      _moreFailed = false;
      if (!keep) {
        _rows = const [];
        _nextCursor = null;
      }
    });
    try {
      final page = await ref.read(apiProvider).eventOrders(widget.k.orgId, widget.k.eventId, status: _status, q: _query.isEmpty ? null : _query, limit: _pageSize);
      if (!mounted || seq != _seq) return true;
      setState(() {
        _rows = _dedupe(const [], page.orders);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return true;
      setState(() {
        _loading = false;
        _error = !keep;
      });
      return false;
    }
    _afterFrame();
    return true;
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loading) return;
    final seq = _seq;
    setState(() {
      _loading = true;
      _moreFailed = false;
    });
    try {
      final page = await ref.read(apiProvider).eventOrders(widget.k.orgId, widget.k.eventId, status: _status, q: _query.isEmpty ? null : _query, cursor: cursor, limit: _pageSize);
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = _dedupe(_rows, page.orders);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _moreFailed = true;
      });
    }
    _afterFrame();
  }

  static List<OrgOrderRow> _dedupe(List<OrgOrderRow> have, List<OrgOrderRow> more) {
    final seen = {for (final r in have) r.id};
    return [...have, for (final r in more) if (seen.add(r.id)) r];
  }

  /// A page that does not fill the screen would never be scrolled, so look again once it is laid out.
  void _afterFrame() => WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients || _loading || _error || _moreFailed || _nextCursor == null) return;
    if (_scroll.position.extentAfter < 300) _loadMore();
  }

  void _onSearch(String v) {
    setState(() => _typed = v);
    _timer?.cancel();
    _timer = Timer(_debounce, _applySearch);
  }

  void _clearSearch() {
    _timer?.cancel();
    _search.clear();
    setState(() => _typed = '');
    _applySearch();
  }

  void _applySearch() {
    final q = _typed.trim();
    if (q == _query) return;
    _query = q;
    _loadFirst();
  }

  void _setFilter(String id) {
    if (id == _filter) return;
    _filter = id;
    _loadFirst();
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = L10n.of(context).refreshFailed;
    ref.invalidate(eventSalesProvider(widget.k));
    var ok = true;
    await Future.wait([
      if (_started) _loadFirst(keep: true).then((v) => ok = ok && v),
      ref.read(eventSalesProvider(widget.k).future).then((_) {}, onError: (_) {
        ok = false;
      }),
    ]);
    if (!ok && mounted) messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(OrgOrderRow row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => OrderSheet(k: widget.k, row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final sales = ref.watch(eventSalesProvider(widget.k));
    final data = sales.value;
    // The hint stays through the reload that follows, and goes with the next answer that works.
    if (sales.hasError && sales.hasValue) {
      _totalsFailed = true;
    } else if (sales.hasValue && !sales.isLoading) {
      _totalsFailed = false;
    }
    if (data == null) {
      return sales.hasError ? loadError(t, _refresh) : const Center(child: CircularProgressIndicator());
    }
    // The list is fetched once the totals say there is something to list.
    if (data.hasPaidTypes && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFirst();
      });
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(t.salesViewSummary, key: const Key('salesViewSummary'), textAlign: TextAlign.center)),
              ButtonSegment(value: true, label: Text(t.salesViewOrders, key: const Key('salesViewOrders'), textAlign: TextAlign.center)),
            ],
            selected: {_showOrders},
            onSelectionChanged: (v) => setState(() => _showOrders = v.first),
          ),
        ),
      ),
      Expanded(
        // Both views stay built, so the search text, the filter and the scroll positions survive switching
        child: IndexedStack(index: _showOrders ? 1 : 0, children: [_summary(t, lang, theme, data), _orders(t, lang, theme, data)]),
      ),
    ]);
  }

  Widget _summary(L10n t, String lang, ThemeData theme, EventSales s) {
    if (!s.hasPaidTypes) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(24), physics: const AlwaysScrollableScrollPhysics(), children: [
          Text(t.noPaidTickets, key: const Key('noPaidTickets'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    Widget tile(String label, String value, {String? key}) => StatTile(label: label, value: value, valueKey: key == null ? null : Key(key));
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]),
        );
    final types = s.types.where((x) => x.priceMmk > 0 || x.basePriceMmk > 0).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(key: const Key('salesSummary'), padding: const EdgeInsets.all(12), physics: const AlwaysScrollableScrollPhysics(), children: [
        Column(key: const Key('salesTotals'), crossAxisAlignment: CrossAxisAlignment.start, children: [
          pair(tile(t.paidOrders, formatAmount(s.paidOrders, lang), key: 'paidOrders'), tile(t.grossSales, formatMmk(s.grossMmk, lang), key: 'grossSales')),
          Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 0), child: Text(t.grossCaption, style: theme.textTheme.bodySmall)),
          const SizedBox(height: 10),
          pair(tile(t.commission, formatMmk(s.commissionMmk, lang), key: 'commission'), tile(t.netToYou, formatMmk(s.netMmk, lang), key: 'net')),
          const SizedBox(height: 10),
          tile(t.refunded, t.refundedLine(formatAmount(s.refundedOrders, lang), formatMmk(s.refundedMmk, lang)), key: 'refunded'),
        ]),
        if (_totalsFailed)
          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(t.refreshFailed, key: const Key('salesRefreshFailed'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        Text(t.byTicketType, style: theme.textTheme.titleMedium),
        for (final x in types) _TypeRow(type: x, lang: lang),
        if (types.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text(t.revenueCaption, key: const Key('revenueCaption'), style: theme.textTheme.bodySmall)),
      ]),
    );
  }

  Widget _orders(L10n t, String lang, ThemeData theme, EventSales s) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const Key('orderSearch'),
          controller: _search,
          decoration: InputDecoration(
            hintText: t.orderSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _typed.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch),
          ),
          onChanged: _onSearch,
        ),
        const SizedBox(height: 8),
        // One row that scrolls sideways. The selected fill is the primary colour: the label and the tick must read
        // on it (as on the Guests filter).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in _filters) ...[
              FilterChip(
                key: Key('orderFilter-${f.$1}'),
                label: Text(_filterLabel(t, f.$1)),
                selected: _filter == f.$1,
                labelStyle: _filter == f.$1 ? theme.chipTheme.labelStyle?.copyWith(color: theme.colorScheme.onPrimary) ?? TextStyle(color: theme.colorScheme.onPrimary) : null,
                checkmarkColor: theme.colorScheme.onPrimary,
                onSelected: (_) => _setFilter(f.$1),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 4),
      ]),
    );
    if (!s.hasPaidTypes) {
      // Nothing to search or filter: no field, no chips, so no request can be started from here.
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(24), physics: const AlwaysScrollableScrollPhysics(), children: [
          Text(t.ordersEmpty, key: const Key('ordersEmpty'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    final footer = _footer(t, theme);
    return Column(children: [
      header,
      const Divider(height: 1),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            key: const Key('orderList'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _rows.length + 1,
            itemBuilder: (_, i) {
              if (i == _rows.length) return footer;
              final r = _rows[i];
              return _OrderTile(row: r, lang: lang, onTap: () => _open(r));
            },
          ),
        ),
      ),
    ]);
  }

  Widget _footer(L10n t, ThemeData theme) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    if (_error) return loadError(t, _loadFirst);
    if (_moreFailed) {
      return ListTile(
        key: const Key('loadMoreFailed'),
        onTap: _loadMore,
        title: Text(t.loadMoreFailed, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
      );
    }
    if (_rows.isEmpty) {
      final filtered = _query.isNotEmpty || _filter != 'all';
      return Padding(padding: const EdgeInsets.all(24), child: Text(filtered ? t.ordersNoMatch : t.ordersEmpty, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium));
    }
    return const SizedBox.shrink();
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.lang});
  final SalesTicketType type;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final sub = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final nextPrice = type.nextPriceMmk;
    final nextAt = type.nextPriceAt;
    return Padding(
      key: Key('salesType-${type.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(type.name)),
          const SizedBox(width: 8),
          Text(formatMmk(type.priceMmk, lang)),
        ]),
        if (nextPrice != null && nextAt != null) Text(t.nextPriceLine(formatMmk(nextPrice, lang), formatDayTime(nextAt, lang)), style: sub),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: type.quota == 0 ? 0 : (type.sold / type.quota).clamp(0, 1).toDouble(), minHeight: 8),
        ),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(t.soldOf(formatAmount(type.sold, lang), formatAmount(type.quota, lang)), style: theme.textTheme.bodySmall)),
          const SizedBox(width: 8),
          Flexible(child: Text('${t.revenue} ${formatMmk(type.revenueMmk, lang)}', textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
        ]),
      ]),
    );
  }
}

String _buyer(L10n t, OrgOrderRow r) {
  final name = (r.buyerName ?? '').trim();
  if (name.isNotEmpty) return name;
  final phone = (r.buyerPhone ?? '').trim();
  return phone.isNotEmpty ? phone : t.walkUp;
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row, required this.lang, required this.onTap});
  final OrgOrderRow row;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final hold = row.holdExpiresAt;
    return ListTile(
      key: Key('orderRow-${row.id}'),
      onTap: onTap,
      title: Text(_buyer(t, row), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t.orderNumber(row.number)} · ${formatAmount(row.quantity, lang)} × · ${formatMmk(row.totalMmk, lang)}', maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(formatDayTime(row.createdAt, lang), style: theme.textTheme.bodySmall),
        if (row.status == 'PENDING_PAYMENT' && hold != null) Text(holdLine(t, hold, DateTime.now(), lang), style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          E360Badge(_salesStatus(t, row.status), kind: _statusKind(row.status)),
          if (row.needsReview) E360Badge(t.beingReviewed, kind: E360BadgeKind.gold),
        ]),
      ]),
    );
  }
}

/// Read-only bottom sheet with one order.
class OrderSheet extends ConsumerStatefulWidget {
  const OrderSheet({super.key, required this.k, required this.row});
  final EventKey k;
  final OrgOrderRow row;
  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  OrgOrderDetail? _detail;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final d = await ref.read(apiProvider).eventOrder(widget.k.orgId, widget.k.eventId, widget.row.id);
      if (mounted) setState(() => _detail = d);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Widget _line(ThemeData theme, String label, String value, {bool bold = false, Key? key}) {
    final style = bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Flexible(child: Text(value, key: key, textAlign: TextAlign.end, style: style)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final sub = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final r = widget.row;
    final d = _detail;
    return SafeArea(
      key: const Key('orderSheet'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(t.orderNumber(r.number), key: const Key('orderNumber'), style: theme.textTheme.titleLarge)),
            TextButton(key: const Key('orderSheetClose'), onPressed: () => Navigator.of(context).pop(), child: Text(t.done)),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            E360Badge(_salesStatus(t, r.status), kind: _statusKind(r.status)),
            if (r.needsReview) E360Badge(t.beingReviewed, kind: E360BadgeKind.gold),
          ]),
          const SizedBox(height: 12),
          Text(_buyer(t, r), style: theme.textTheme.titleMedium),
          if ((r.buyerName ?? '').trim().isNotEmpty && (r.buyerPhone ?? '').trim().isNotEmpty) Text(r.buyerPhone!, key: const Key('orderPhone'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(t.orderCreated(formatDayTime(r.createdAt, lang)), style: sub),
          if (r.paidAt != null) Text(t.orderPaid(formatDayTime(r.paidAt!, lang)), style: sub),
          if (r.status == 'PENDING_PAYMENT' && r.holdExpiresAt != null) Text(holdLine(t, r.holdExpiresAt!, DateTime.now(), lang), style: sub),
          if (r.needsReview) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('reviewNote'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Text(t.reviewNote, style: theme.textTheme.bodyMedium),
            ),
          ],
          const Divider(height: 28),
          if (d == null)
            _error ? loadError(t, _load) : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            ..._detailBody(t, lang, theme, sub, d),
        ]),
      ),
    );
  }

  List<Widget> _detailBody(L10n t, String lang, ThemeData theme, TextStyle? sub, OrgOrderDetail d) {
    final discountLabel = d.promoCode != null && d.promoCode!.isNotEmpty ? t.discountPromo(d.promoCode!) : (d.groupDiscountBp != null ? t.discountGroup : t.discount);
    return [
      for (final it in d.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pickLang(lang, it.name, it.nameMy), style: theme.textTheme.bodyLarge),
            Text('${formatAmount(it.quantity, lang)} × ${formatMmk(it.unitPriceMmk, lang)}', style: sub),
            if (it.seats.isNotEmpty) Text(t.seatsLine(it.seats.map((s) => pickLang(lang, s.label, s.labelMy)).join(', ')), style: sub),
          ]),
        ),
      const Divider(height: 20),
      _line(theme, t.subtotal, formatMmk(d.subtotalMmk, lang)),
      if (d.row.discountMmk > 0) _line(theme, discountLabel, '− ${formatMmk(d.row.discountMmk, lang)}', key: const Key('orderDiscount')),
      _line(theme, t.total, formatMmk(d.row.totalMmk, lang), bold: true, key: const Key('orderTotal')),
      _line(theme, t.commission, formatMmk(d.commissionMmk, lang)),
      if (d.payments.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(t.payments, style: theme.textTheme.titleMedium),
        for (final p in d.payments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_providerText(t, p.provider)} · ${_paymentStatusText(t, p.status)}'),
              Text(formatDayTime(p.createdAt, lang), style: sub),
            ]),
          ),
      ],
      if (d.refunds.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(t.refunds, style: theme.textTheme.titleMedium),
        for (final f in d.refunds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatMmk(f.amountMmk, lang)),
              Text(refundStateText(t, f.status), style: sub),
            ]),
          ),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.wholeOrderRefund, style: sub)),
      ],
      if (d.ticketsTotal > 0) ...[
        const SizedBox(height: 16),
        Text(t.ticketsCheckedIn(formatAmount(d.ticketsCheckedIn, lang), formatAmount(d.ticketsTotal, lang)), key: const Key('orderTickets')),
      ],
    ];
  }
}
