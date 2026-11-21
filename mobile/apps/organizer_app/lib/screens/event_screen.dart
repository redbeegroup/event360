import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lang_button.dart' show compactFilled;

/// One event: live overview, door codes, announcements and promo codes.
/// Localized order status; an unknown value from a newer API shows as it is.
String orderStatusLabel(L10n t, String s) => switch (s) {
      'PENDING_PAYMENT' => t.orderStatus_PENDING_PAYMENT,
      'PAID' => t.orderStatus_PAID,
      'CONFIRMED' => t.orderStatus_CONFIRMED,
      'EXPIRED' => t.orderStatus_EXPIRED,
      'CANCELLED' => t.orderStatus_CANCELLED,
      'REFUNDED' => t.orderStatus_REFUNDED,
      'FAILED' => t.orderStatus_FAILED,
      _ => s,
    };

class EventScreen extends ConsumerWidget {
  const EventScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final org = ref.watch(currentOrgProvider);
    final event = ref.watch(orgEventsProvider).value?.where((e) => e.id == eventId).firstOrNull;
    if (org == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final k = (orgId: org.id, eventId: eventId);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(event == null ? '' : pickLang(lang, event.title, event.titleMy), maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(key: const Key('tabOverview'), text: t.tabOverview),
            Tab(key: const Key('tabDoor'), text: t.tabDoor),
            Tab(key: const Key('tabAnnounce'), text: t.tabAnnounce),
            Tab(key: const Key('tabPromos'), text: t.tabPromos),
          ]),
        ),
        body: TabBarView(children: [
          _Overview(k: k),
          _Door(k: k, canEdit: org.canEdit),
          _Announce(k: k, canEdit: org.canEdit),
          _Promos(k: k, canEdit: org.canEdit),
        ]),
      ),
    );
  }
}

Widget _loadError(L10n t, VoidCallback retry) => MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: retry);

Widget _readOnly(BuildContext context, L10n t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [const Icon(Icons.lock_outline, size: 18), const SizedBox(width: 6), Expanded(child: Text(t.readOnly, style: Theme.of(context).textTheme.bodySmall))]),
    );

// ───────────── Overview ─────────────

class _Overview extends ConsumerStatefulWidget {
  const _Overview({required this.k});
  final EventKey k;
  @override
  ConsumerState<_Overview> createState() => _OverviewState();
}

class _OverviewState extends ConsumerState<_Overview> {
  Timer? _timer;
  DateTime _updated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardProvider(widget.k));
    ref.invalidate(attendanceProvider(widget.k));
    ref.invalidate(recentOrdersProvider(widget.k));
    if (mounted) setState(() => _updated = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final dash = ref.watch(dashboardProvider(widget.k));
    final att = ref.watch(attendanceProvider(widget.k)).value;
    final orders = ref.watch(recentOrdersProvider(widget.k)).value ?? const <RecentOrder>[];
    return dash.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _loadError(t, _refresh),
      data: (d) {
        final tot = d.totals;
        Widget tile(String label, String value, {String? key}) => StatTile(label: label, value: value, valueKey: key == null ? null : Key(key));
        Widget bar(String name, int value, int of) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(name)), Text('${formatAmount(value, lang)} / ${formatAmount(of, lang)}', style: theme.textTheme.bodySmall)]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: of == 0 ? 0 : value / of, minHeight: 8),
                ),
              ]),
            );
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            // Two tiles per row, as tall as the taller one (long amounts wrap instead of overflowing)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: tile(t.ticketsSold, '${formatAmount(tot.ticketsSold, lang)} / ${formatAmount(tot.capacity, lang)}', key: 'sold')),
                const SizedBox(width: 10),
                Expanded(child: tile(t.revenue, formatMmk(tot.revenueMmk, lang), key: 'revenue')),
              ]),
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: tile(t.checkedIn, att == null ? formatAmount(tot.checkedIn, lang) : '${formatAmount(att.checkedIn, lang)} / ${formatAmount(att.registered, lang)}', key: 'checkedIn'),
                ),
                const SizedBox(width: 10),
                Expanded(child: tile(t.orders, formatAmount(tot.orders, lang))),
              ]),
            ),
            const SizedBox(height: 8),
            Text(t.byTicketType, style: theme.textTheme.titleMedium),
            for (final tt in d.ticketTypes) bar(tt.name, tt.sold, tt.quota),
            if (d.seatTotals case final st?) ...[
              const SizedBox(height: 12),
              Text(t.seatsTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // Three tiles per row; the label sits on top, the count below it
              LayoutBuilder(builder: (_, c) {
                final w = (c.maxWidth - 2 * 10) / 3;
                return Wrap(key: const Key('seatCounts'), spacing: 10, runSpacing: 10, children: [
                  for (final (label, n) in [(t.seatsAvailable, st.available), (t.seatsHeld, st.held), (t.seatsGuest, st.guest), (t.seatsSold, st.sold), (t.seatsComp, st.comp)])
                    SizedBox(width: w, child: StatTile(label: label, value: formatAmount(n, lang), small: true)),
                ]);
              }),
            ],
            if (att != null && att.byGate.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.byGate, style: theme.textTheme.titleMedium),
              for (final g in att.byGate)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.door_front_door_outlined), title: Text(g.gate ?? t.noGate), trailing: Text(formatAmount(g.checkedIn, lang))),
            ],
            const SizedBox(height: 12),
            Text(t.recentOrders, style: theme.textTheme.titleMedium),
            if (orders.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t.noOrders)),
            for (final o in orders.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${o.quantity} × · ${formatMmk(o.totalMmk, lang)}'),
                subtitle: Text([o.buyer ?? '', formatDayTime(o.createdAt, lang)].where((s) => s.isNotEmpty).join(' · ')),
                trailing: E360Badge(orderStatusLabel(t, o.status), kind: o.status == 'PAID' ? E360BadgeKind.success : E360BadgeKind.neutral),
              ),
            const SizedBox(height: 8),
            Text(t.updatedAt(formatTime(_updated, lang)), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}

/// Overview number tile: label on top, the number big in the display font.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.valueKey, this.small = false});
  final String label;
  final String value;
  final Key? valueKey;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final my = Localizations.localeOf(context).languageCode == 'my';
    final size = small ? (my ? 20.0 : 22.0) : (my ? 22.0 : 26.0);
    return Container(
      padding: EdgeInsets.all(small ? 12 : 14),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, key: valueKey, style: theme.textTheme.titleLarge?.copyWith(fontSize: size)),
      ]),
    );
  }
}

// ───────────── Door (crew codes) ─────────────

class _Door extends ConsumerStatefulWidget {
  const _Door({required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<_Door> createState() => _DoorState();
}

class _DoorState extends ConsumerState<_Door> {
  final _label = TextEditingController();
  final _gate = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _gate.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_label.text.trim().length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(apiProvider).createCrewCode(widget.k.orgId, widget.k.eventId, _label.text.trim(), gate: _gate.text.trim());
      ref.invalidate(crewCodesProvider(widget.k));
      _label.clear();
      _gate.clear();
      if (mounted) await showDialog<void>(context: context, builder: (_) => _CodeDialog(code: c));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(CrewCode c) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.revokeConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.revoke)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiProvider).revokeCrewCode(widget.k.orgId, widget.k.eventId, c.id).catchError((_) {});
    ref.invalidate(crewCodesProvider(widget.k));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final codes = ref.watch(crewCodesProvider(widget.k));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t.doorHint),
      const SizedBox(height: 12),
      if (widget.canEdit) ...[
        TextField(key: const Key('codeLabel'), controller: _label, decoration: InputDecoration(labelText: t.codeLabel)),
        const SizedBox(height: 8),
        TextField(key: const Key('codeGate'), controller: _gate, decoration: InputDecoration(labelText: t.gate)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('createCode'), style: E360Buttons.gold, onPressed: _busy ? null : _create, icon: const Icon(Icons.qr_code_2), label: Text(t.createCode)),
      ] else
        _readOnly(context, t),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: E360Buttons.outline,
        onPressed: () => launchUrl(Uri.parse(crewWebUrl), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new),
        label: Text(t.openCrewApp),
      ),
      const SizedBox(height: 12),
      codes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _loadError(t, () => ref.invalidate(crewCodesProvider(widget.k))),
        data: (list) => Column(children: [
          for (final c in list)
            ListTile(
              key: Key('code-${c.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(c.active ? Icons.badge_outlined : Icons.block, color: c.active ? theme.colorScheme.primary : theme.disabledColor),
              title: Text([c.label, if (c.gate != null) c.gate!].join(' · ')),
              subtitle: Text(
                c.revokedAt != null
                    ? t.revoked
                    : !c.active
                        ? t.expired
                        : '${t.devices(c.devices)} · ${formatDayTime(c.expiresAt, lang)}',
              ),
              trailing: c.active && widget.canEdit ? TextButton(onPressed: () => _revoke(c), child: Text(t.revoke)) : null,
            ),
        ]),
      ),
    ]);
  }
}

class _CodeDialog extends StatelessWidget {
  const _CodeDialog({required this.code});
  final CrewCode code;
  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    // The Crew app reads the code from any link with ?code=…; the web link also works on phones without the app.
    final link = '$crewWebUrl#/redeem?code=${code.code}';
    return AlertDialog(
      title: Text(t.codeCreated),
      content: SizedBox(
        width: 260,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(color: Colors.white, padding: const EdgeInsets.all(10), child: SizedBox.square(dimension: 200, child: QrImageView(data: link, size: 200))),
        const SizedBox(height: 12),
        SelectableText(code.code ?? '', key: const Key('newCode'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
        const SizedBox(height: 8),
        Text(t.codeOnce, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
      ),
      actions: [
        IconButton(onPressed: () => Clipboard.setData(ClipboardData(text: code.code ?? '')), icon: const Icon(Icons.copy)),
        FilledButton(style: compactFilled, onPressed: () => Navigator.of(context).pop(), child: Text(t.done)),
      ],
    );
  }
}

// ───────────── Announcements ─────────────

class _Announce extends ConsumerStatefulWidget {
  const _Announce({required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<_Announce> createState() => _AnnounceState();
}

class _AnnounceState extends ConsumerState<_Announce> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleMy = TextEditingController();
  final _bodyMy = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _body, _titleMy, _bodyMy]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final t = L10n.of(context);
    if (_title.text.trim().length < 3 || _body.text.trim().length < 3) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.sendConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('confirmSend'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.send)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).sendAnnouncement(widget.k.orgId, widget.k.eventId, title: _title.text.trim(), body: _body.text.trim(), titleMy: _titleMy.text.trim(), bodyMy: _bodyMy.text.trim());
      for (final c in [_title, _body, _titleMy, _bodyMy]) {
        c.clear();
      }
      ref.invalidate(announcementsProvider(widget.k));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.sent)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final ann = ref.watch(announcementsProvider(widget.k));
    return ann.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _loadError(t, () => ref.invalidate(announcementsProvider(widget.k))),
      data: (a) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(t.announceHint),
        const SizedBox(height: 6),
        Text('${t.recipients(a.ticketHolders)} · ${t.leftToday(a.remainingToday)}', key: const Key('announceCounts'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (!widget.canEdit)
          _readOnly(context, t)
        else if (a.remainingToday > 0 && a.ticketHolders > 0) ...[
          TextField(key: const Key('annTitle'), controller: _title, maxLength: 80, decoration: InputDecoration(labelText: t.heading)),
          TextField(key: const Key('annBody'), controller: _body, maxLength: 500, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: t.message)),
          TextField(controller: _titleMy, maxLength: 80, decoration: InputDecoration(labelText: t.headingMy)),
          TextField(controller: _bodyMy, maxLength: 500, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: t.messageMy)),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          FilledButton.icon(key: const Key('sendAnnouncement'), style: E360Buttons.gold, onPressed: _busy ? null : _send, icon: const Icon(Icons.campaign_outlined), label: Text(t.send)),
        ],
        const SizedBox(height: 16),
        if (a.items.isEmpty) Text(t.noAnnouncements, style: theme.textTheme.bodySmall),
        for (final i in a.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(pickLang(lang, i.title, i.titleMy)),
            subtitle: Text('${pickLang(lang, i.body, i.bodyMy)}\n${formatDayTime(i.createdAt, lang)} · ${t.recipients(i.recipients)}'),
            isThreeLine: true,
          ),
      ]),
    );
  }
}

// ───────────── Promo codes ─────────────

class _Promos extends ConsumerStatefulWidget {
  const _Promos({required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<_Promos> createState() => _PromosState();
}

class _PromosState extends ConsumerState<_Promos> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _max = TextEditingController();
  String _kind = 'PERCENT';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _value, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final value = int.tryParse(_value.text.trim());
    if (_code.text.trim().length < 3 || value == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).createPromoCode(widget.k.orgId, widget.k.eventId, code: _code.text.trim(), kind: _kind, value: value, maxUses: int.tryParse(_max.text.trim()));
      for (final c in [_code, _value, _max]) {
        c.clear();
      }
      ref.invalidate(promoCodesProvider(widget.k));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final promos = ref.watch(promoCodesProvider(widget.k));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t.promosHint),
      const SizedBox(height: 12),
      if (widget.canEdit) ...[
        TextField(key: const Key('promoCode'), controller: _code, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: t.promoCode)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _kind,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'PERCENT', child: Text(t.percent, overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'FIXED', child: Text(t.fixed, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'PERCENT'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(key: const Key('promoValue'), controller: _value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.amount))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.maxUses)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('createPromo'), style: E360Buttons.gold, onPressed: _busy ? null : _create, icon: const Icon(Icons.sell_outlined), label: Text(t.createPromo)),
      ] else
        _readOnly(context, t),
      const SizedBox(height: 12),
      promos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _loadError(t, () => ref.invalidate(promoCodesProvider(widget.k))),
        data: (list) => list.isEmpty
            ? Text(t.noPromos, style: theme.textTheme.bodySmall)
            : Column(children: [
                for (final p in list)
                  ListTile(
                    key: Key('promo-${p.code}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p.code} · ${p.kind == 'PERCENT' ? '${p.value}%' : formatMmk(p.value, lang)}${p.isActive ? '' : ' · ${t.off}'}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: p.isActive ? null : theme.disabledColor)),
                    subtitle: Text('${t.used(p.maxUses == null ? '${p.used}' : '${p.used} / ${p.maxUses}')} · ${t.discounts}: ${formatMmk(p.discountGivenMmk, lang)}'),
                    trailing: widget.canEdit
                        ? TextButton(
                            onPressed: () async {
                              await ref.read(apiProvider).setPromoActive(widget.k.orgId, widget.k.eventId, p.id, !p.isActive).catchError((_) {});
                              ref.invalidate(promoCodesProvider(widget.k));
                            },
                            child: Text(p.isActive ? t.turnOff : t.turnOn),
                          )
                        : null,
                  ),
              ]),
      ),
    ]);
  }
}
