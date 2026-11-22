import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lang_button.dart' show compactFilled;
import 'common.dart';

/// The server accepts at most this many seats per hold, release or issue.
const maxSeatsPerAction = 200;

/// How the organizer's per-seat status is drawn: the buyer map's existing states, nothing new.
SeatState orgSeatState(String status) => switch (status) {
      'AVAILABLE' => SeatState.available,
      'GUEST_HOLD' => SeatState.held,
      'UNSOLD' => SeatState.unavailable,
      _ => SeatState.taken, // SOLD, CHECKOUT_HOLD, WAITLIST_HOLD
    };

bool _selectable(OrgSeat s) => s.status == 'AVAILABLE' || s.status == 'GUEST_HOLD';

final _myanmarPhone = RegExp(r'^(\+?95|0)9\d{7,9}$');

/// Client-side check only; the server is the authority.
bool isMyanmarMobile(String input) => _myanmarPhone.hasMatch(input.replaceAll(RegExp(r'[\s\-]'), ''));

/// Reloads everything a seat action can change.
void refreshSeating(WidgetRef ref, EventKey k) {
  ref.invalidate(orgSeatingProvider(k));
  ref.invalidate(guestTicketsProvider(k));
  ref.invalidate(attendeesProvider(k));
  ref.invalidate(dashboardProvider(k));
}

/// Seat map with hold, release, guest tickets and revoke.
class SeatsTab extends ConsumerStatefulWidget {
  const SeatsTab({super.key, required this.k, required this.canEdit, @visibleForTesting this.initialSelected = const {}});
  final EventKey k;
  final bool canEdit;

  /// Seat keys selected at the start (tests only: reaching the 200-seat limit by tapping is impractical).
  final Set<String> initialSelected;
  @override
  ConsumerState<SeatsTab> createState() => _SeatsTabState();
}

class _SeatsTabState extends ConsumerState<SeatsTab> {
  final _controller = SeatMapViewController();
  late final Set<String> _selected = {...widget.initialSelected};
  bool _busy = false;

  // Worked out once per fetched OrgSeating.
  OrgSeating? _source;
  SeatLayout? _layout;
  Map<String, OrgSeat> _byKey = const {};
  List<SeatState> _states = const [];
  List<Color?> _colors = const [];

  void _derive(OrgSeating data) {
    if (identical(data, _source)) return;
    _source = data;
    final layout = SeatLayout.fromJson(data.layout!);
    _layout = layout;
    _byKey = {for (final s in data.seats) s.seatKey: s};
    final states = List<SeatState>.filled(layout.seats.length, SeatState.unavailable);
    final colors = List<Color?>.filled(layout.seats.length, null);
    for (final seat in layout.seats) {
      final os = _byKey[seat.seatKey];
      if (os == null) continue;
      states[seat.index] = orgSeatState(os.status);
      colors[seat.index] = os.ticketTypeId == null ? null : parseHexColor(data.colors[os.ticketTypeId]);
    }
    _states = states;
    _colors = colors;
  }

  void _tap(int index, Set<String> selected) {
    if (!widget.canEdit) return;
    final key = _layout!.seats[index].seatKey;
    final os = _byKey[key];
    if (os == null || !_selectable(os)) return;
    setState(() {
      if (!selected.remove(key)) selected.add(key);
      _selected
        ..clear()
        ..addAll(selected);
    });
  }

  void _clear() => setState(_selected.clear);

  Future<void> _refresh() async {
    refreshSeating(ref, widget.k);
    try {
      await ref.read(orgSeatingProvider(widget.k).future);
    } catch (_) {}
  }

  /// Some seats changed under the organizer: reload, forget them and say so.
  void _changed(SeatsChanged e) {
    refreshSeating(ref, widget.k);
    if (!mounted) return;
    setState(() => _selected.removeAll(e.takenSeats));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).seatsChanged)));
  }

  Future<void> _sheet(Widget Function(BuildContext) builder) async {
    final out = await showModalBottomSheet<Object>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: builder);
    if (!mounted) return;
    if (out is SeatsChanged) {
      _changed(out);
    } else if (out == true) {
      setState(_selected.clear);
    }
  }

  Future<void> _release(List<String> keys) async {
    final t = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.releaseConfirm(keys.length)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('releaseConfirm'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.releaseSeats)),
        ],
      ),
    );
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).releaseSeats(widget.k.orgId, widget.k.eventId, keys);
      refreshSeating(ref, widget.k);
      if (mounted) setState(_selected.clear);
    } on SeatsChanged catch (e) {
      _changed(e);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetwork ? t.loadError : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(GuestTicket g) async {
    final t = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.revokeGuestConfirm(g.guestName)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('revokeConfirm'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.revoke)),
        ],
      ),
    );
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).revokeGuestTicket(widget.k.orgId, widget.k.eventId, g.id);
      refreshSeating(ref, widget.k);
      messenger.showSnackBar(SnackBar(content: Text(t.guestRevoked)));
    } on ApiException catch (e) {
      // Already checked in or already revoked: say so, and show the current state.
      refreshSeating(ref, widget.k);
      messenger.showSnackBar(SnackBar(content: Text(e.isNetwork ? t.loadError : e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final async = ref.watch(orgSeatingProvider(widget.k));
    final data = async.value;
    if (data == null || !data.hasMap) {
      return async.hasError ? loadError(t, _refresh) : const Center(child: CircularProgressIndicator());
    }
    _derive(data);
    final layout = _layout!;

    // Only seats that can still be selected stay selected after a refresh.
    final selected = {for (final key in _selected) if (_byKey[key] != null && _selectable(_byKey[key]!)) key};
    var states = _states;
    var colors = _colors;
    final indexes = <int>{};
    for (final key in selected) {
      final seat = layout.seatByKey(key);
      if (seat == null) continue;
      indexes.add(seat.index);
      if (states[seat.index] == SeatState.held) {
        // The map draws no selection mark on grey seats, so a selected held seat is drawn as a grey free one.
        if (identical(states, _states)) {
          states = [..._states];
          colors = [..._colors];
        }
        states[seat.index] = SeatState.available;
        colors[seat.index] = const Color(0xFF8E8E99);
      }
    }
    final chosen = [for (final key in selected) _byKey[key]!];

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _Legend(data: data)),
            if (!widget.canEdit) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ViewOnly(text: t.viewOnlySeats))),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: LayoutBuilder(builder: (context, c) {
                  final h = (c.maxWidth * layout.height / layout.width).clamp(320.0, 520.0);
                  return SizedBox(
                    height: h,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SeatMapView(
                        layout: layout,
                        states: states,
                        colors: colors,
                        selected: indexes,
                        lang: lang,
                        controller: _controller,
                        onSeatTap: widget.canEdit ? (i) => _tap(i, selected) : null,
                        overlayBuilder: (ctx, scale) => scale >= kSeatTapScale || !widget.canEdit
                            ? const SizedBox.shrink()
                            : Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: IgnorePointer(
                                  child: Container(
                                    key: const Key('seatsZoomHint'),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                                    child: Text(t.seatsZoomHint, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(t.guestList, style: Theme.of(context).textTheme.titleMedium))),
            _GuestTickets(k: widget.k, canEdit: widget.canEdit, lang: lang, busy: _busy, onRevoke: _revoke),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ]),
        ),
      ),
      if (widget.canEdit && chosen.isNotEmpty)
        _SelectionBar(
          seats: chosen,
          busy: _busy,
          onClear: _clear,
          onHold: () => _sheet((_) => _HoldSheet(k: widget.k, keys: [for (final s in chosen) s.seatKey])),
          onRelease: () => _release([for (final s in chosen) s.seatKey]),
          onIssue: () => _sheet((_) => _IssueSheet(k: widget.k, keys: [for (final s in chosen) s.seatKey])),
        ),
    ]);
  }
}

class _ViewOnly extends StatelessWidget {
  const _ViewOnly({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(key: const Key('viewOnlySeats'), children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.data});
  final OrgSeating data;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    int sum(int Function(SeatCounts) f) => data.counts.values.fold(0, (a, c) => a + f(c));
    final typeColor = data.colors.values.map(parseHexColor).whereType<Color>().firstOrNull ?? E360Colors.gold;
    Widget item(String key, Widget mark, String label, int n) => Row(key: Key(key), mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 6),
          Flexible(child: Text('$label $n', style: Theme.of(context).textTheme.bodySmall)),
        ]);
    Widget dot(Color c, [IconData? icon]) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: icon == null ? null : Icon(icon, size: 11, color: Colors.white),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 16, runSpacing: 6, children: [
        item('legendAvailable', dot(typeColor), t.legendAvailable, sum((c) => c.available)),
        item('legendHeld', dot(const Color(0xFFBDBDBD), Icons.close), t.legendHeld, sum((c) => c.guest)),
        item('legendSold', dot(const Color(0xFFBDBDBD)), t.legendSold, sum((c) => c.sold)),
        item('legendGuest', dot(const Color(0xFFBDBDBD), Icons.person), t.legendGuest, sum((c) => c.comp)),
      ]),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.seats, required this.busy, required this.onClear, required this.onHold, required this.onRelease, required this.onIssue});
  final List<OrgSeat> seats;
  final bool busy;
  final VoidCallback onClear, onHold, onRelease, onIssue;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final n = seats.length;
    final free = seats.every((s) => s.status == 'AVAILABLE');
    final held = seats.every((s) => s.status == 'GUEST_HOLD');
    final noType = held && seats.any((s) => s.ticketTypeId == null);
    final label = n == 1 ? seats.first.holdLabel : null;
    final String? hint = n > maxSeatsPerAction
        ? t.seatsTooMany
        : (!free && !held)
            ? t.seatsMixedHint
            : noType
                ? t.seatsNoTypeHint
                : null;
    final canAct = n <= maxSeatsPerAction && !busy;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(key: const Key('selectionBar'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              // The text may scroll at huge text sizes; the actions stay in reach.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(t.seatsSelected(n), key: const Key('seatsSelected'), style: theme.textTheme.titleMedium)),
                      TextButton(key: const Key('seatsClear'), onPressed: onClear, child: Text(t.clear)),
                    ]),
                    if (label != null && label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t.heldLabel(label), key: const Key('seatsHoldLabel'), style: theme.textTheme.bodyMedium)),
                    if (hint != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(hint, key: const Key('seatsHint'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
                  ]),
                ),
              ),
              if (free && n <= maxSeatsPerAction)
                FilledButton(key: const Key('seatsHold'), style: E360Buttons.gold, onPressed: canAct ? onHold : null, child: Text(t.holdForGuests)),
              if (held && n <= maxSeatsPerAction) ...[
                FilledButton(key: const Key('seatsIssue'), style: E360Buttons.gold, onPressed: canAct && !noType ? onIssue : null, child: Text(t.issueGuestTickets)),
                const SizedBox(height: 8),
                OutlinedButton(key: const Key('seatsRelease'), style: E360Buttons.outline, onPressed: canAct ? onRelease : null, child: Text(t.releaseSeats)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _GuestTickets extends ConsumerWidget {
  const _GuestTickets({required this.k, required this.canEdit, required this.lang, required this.busy, required this.onRevoke});
  final EventKey k;
  final bool canEdit, busy;
  final String lang;
  final void Function(GuestTicket) onRevoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(guestTicketsProvider(k));
    final list = async.value;
    if (list == null) {
      return SliverToBoxAdapter(
        child: async.hasError ? loadError(t, () => ref.invalidate(guestTicketsProvider(k))) : const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      );
    }
    if (list.isEmpty) {
      return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text(t.noGuestTickets, key: const Key('noGuestTickets'), style: theme.textTheme.bodyMedium)));
    }
    return SliverList.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final g = list[i];
        final seat = g.seatLabel == null ? g.seatKey : pickLang(lang, g.seatLabel!, g.seatLabelMy);
        final dead = !g.checkedIn && g.status != 'VALID';
        final tile = ListTile(
          key: Key('guestTicket-${g.id}'),
          title: Text(g.guestName, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([g.phone, seat, if (g.label != null && g.label!.isNotEmpty) g.label!].where((s) => s.isNotEmpty).join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            E360Badge(_status(t, g), kind: g.checkedIn ? E360BadgeKind.success : E360BadgeKind.neutral),
            if (canEdit && g.canRevoke)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton(key: Key('guestRevoke-${g.id}'), style: E360Buttons.outline, onPressed: busy ? null : () => onRevoke(g), child: Text(t.revoke)),
                ),
              ),
          ]),
        );
        return dead ? Opacity(opacity: 0.6, child: tile) : tile;
      },
    );
  }
}

String _status(L10n t, GuestTicket g) => g.checkedIn
    ? t.statusIn
    : g.status == 'VALID'
        ? t.statusNotIn
        : g.status == 'VOID'
            ? t.revoked
            : t.statusCancelled;

/// Sheet asking for the label of a hold; pops `true` when the seats were held.
class _HoldSheet extends ConsumerStatefulWidget {
  const _HoldSheet({required this.k, required this.keys});
  final EventKey k;
  final List<String> keys;
  @override
  ConsumerState<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends ConsumerState<_HoldSheet> {
  final _label = TextEditingController();
  bool _busy = false;
  String? _labelError, _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = L10n.of(context);
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _labelError = t.fieldRequired);
      return;
    }
    setState(() {
      _busy = true;
      _labelError = null;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).holdSeats(widget.k.orgId, widget.k.eventId, widget.keys, label);
      refreshSeating(ref, widget.k);
      nav.pop(true);
    } on SeatsChanged catch (e) {
      nav.pop(e);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? t.loadError : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(t.holdForGuests, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(t.seatsSelected(widget.keys.length), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        TextField(
          key: const Key('holdLabel'),
          controller: _label,
          enabled: !_busy,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          decoration: InputDecoration(labelText: t.holdLabelField, errorText: _labelError),
          onChanged: (_) {
            if (_labelError != null) setState(() => _labelError = null);
          },
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('sheetError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('holdSubmit'), style: E360Buttons.gold, onPressed: _busy ? null : _submit, child: Text(t.holdForGuests)),
      ]),
    );
  }
}

/// Sheet collecting the guest's details, then a confirm step that repeats the number; pops `true` when issued.
class _IssueSheet extends ConsumerStatefulWidget {
  const _IssueSheet({required this.k, required this.keys});
  final EventKey k;
  final List<String> keys;
  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  String? _nameError, _phoneError, _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final t = L10n.of(context);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() {
      _nameError = name.isEmpty ? t.fieldRequired : null;
      _phoneError = phone.isEmpty ? t.fieldRequired : (!isMyanmarMobile(phone) ? t.phoneInvalid : null);
      _error = null;
    });
    if (_nameError != null || _phoneError != null) return;
    // A mistyped number gives the tickets to a stranger: repeat it before sending.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.issueConfirmText(widget.keys.length, phone), key: const Key('issueConfirmText')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('issueConfirm'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.issueGuestTickets)),
        ],
      ),
    );
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await ref.read(apiProvider).issueGuestTickets(widget.k.orgId, widget.k.eventId, widget.keys, guestName: name, phone: phone, label: _label.text.trim());
      refreshSeating(ref, widget.k);
      nav.pop(true);
    } on SeatsChanged catch (e) {
      nav.pop(e);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 400) {
          _phoneError = t.phoneInvalid;
        } else {
          _error = e.isNetwork ? t.loadError : e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(t.issueGuestTickets, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(t.seatsSelected(widget.keys.length), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(t.issueHelp, key: const Key('issueHelp'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(
          key: const Key('guestName'),
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
          decoration: InputDecoration(labelText: t.guestNameField, errorText: _nameError),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('guestPhone'),
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: t.guestPhoneField, errorText: _phoneError),
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('guestLabel'),
          controller: _label,
          enabled: !_busy,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          decoration: InputDecoration(labelText: t.guestLabelField),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('sheetError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(key: const Key('issueSubmit'), style: E360Buttons.gold, onPressed: _busy ? null : _submit, child: Text(t.issueGuestTickets)),
      ]),
    );
  }
}
