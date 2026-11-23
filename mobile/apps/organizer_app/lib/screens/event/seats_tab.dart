import 'dart:math' as math;

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/errors.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lang_button.dart' show compactFilled;
import 'common.dart';

/// A count in the app's digit style and with separators, the same as money.
String _n(BuildContext context, int n) => formatAmount(n, Localizations.localeOf(context).languageCode);

/// The server accepts at most this many seats per hold, release or issue.
const maxSeatsPerAction = 200;

/// How the organizer's per-seat status is drawn: the buyer map's existing states, nothing new.
SeatState orgSeatState(String status) => switch (status) {
  'AVAILABLE' => SeatState.available,
  'GUEST_HOLD' => SeatState.held,
  'UNSOLD' => SeatState.unavailable,
  _ => SeatState.taken, // SOLD, CHECKOUT_HOLD, WAITLIST_HOLD
};

bool _selectable(OrgSeat s) =>
    s.status == 'AVAILABLE' || s.status == 'GUEST_HOLD';

/// The server's rule (normalizeMyanmarPhone): spaces, dashes and brackets are ignored; +959…, 959… or 09…,
/// then 7 to 10 more digits. Client-side check only; the server is the authority.
bool isMyanmarMobile(String input) {
  final s = input.replaceAll(RegExp(r'[\s\-()]'), '');
  final m = RegExp(r'^(?:\+959|959|09)(\d+)$').firstMatch(s);
  if (m == null) return false;
  final n = m.group(1)!.length;
  return n >= 7 && n <= 10;
}

/// Reloads everything a seat action can change.
void refreshSeating(ProviderContainer c, EventKey k) {
  c.invalidate(orgSeatingProvider(k));
  c.invalidate(guestTicketsProvider(k));
  c.invalidate(attendeesProvider(k));
  c.invalidate(dashboardProvider(k));
  c.invalidate(attendanceProvider(k));
}

enum _Result { ok, changed, phone, failed }

class _Outcome {
  const _Outcome(this.result, [this.message]);
  final _Result result;
  final String? message;
  bool get closes => result == _Result.ok || result == _Result.changed;
}

/// Seat map with hold, release, guest tickets and revoke. Two views: the map, and the guest tickets.
class SeatsTab extends ConsumerStatefulWidget {
  const SeatsTab({
    super.key,
    required this.k,
    required this.canEdit,
    @visibleForTesting this.initialSelected = const {},
  });
  final EventKey k;
  final bool canEdit;

  /// Seat keys selected at the start (tests only: reaching the 200-seat limit by tapping is impractical).
  final Set<String> initialSelected;
  @override
  ConsumerState<SeatsTab> createState() => _SeatsTabState();
}

class _SeatsTabState extends ConsumerState<SeatsTab> with AutomaticKeepAliveClientMixin {
  final _controller = SeatMapViewController();
  late final Set<String> _selected = {...widget.initialSelected};
  bool _busy = false;
  bool _dialogOpen = false;
  bool _guestsView = false;
  final _barKey = GlobalKey();
  double _barHeight = 0;

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
    final states = List<SeatState>.filled(
      layout.seats.length,
      SeatState.unavailable,
    );
    final colors = List<Color?>.filled(layout.seats.length, null);
    for (final seat in layout.seats) {
      final os = _byKey[seat.seatKey];
      if (os == null) continue;
      states[seat.index] = orgSeatState(os.status);
      colors[seat.index] = os.ticketTypeId == null
          ? null
          : parseHexColor(data.colors[os.ticketTypeId]);
    }
    _states = states;
    _colors = colors;
    // After every refresh only seats that can still be selected stay selected.
    _selected.removeWhere(
      (key) => _byKey[key] == null || !_selectable(_byKey[key]!),
    );
  }

  void _tap(int index) {
    if (!widget.canEdit || _busy) return;
    final key = _layout!.seats[index].seatKey;
    final os = _byKey[key];
    if (os == null || !_selectable(os)) return;
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  void _clear() => setState(_selected.clear);

  Future<void> _refresh() async {
    refreshSeating(ProviderScope.containerOf(context, listen: false), widget.k);
    try {
      await ref.read(orgSeatingProvider(widget.k).future);
    } catch (_) {}
  }

  /// Runs one seat action here, in the tab, so a sheet that goes away cannot lose the refresh or the messages.
  Future<_Outcome> _run(
    Future<void> Function(Event360Api api) call, {
    String Function(L10n t)? okMessage,
    bool phoneOn400 = false,
  }) async {
    if (_busy) return const _Outcome(_Result.failed);
    final api = ref.read(apiProvider);
    final c = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final t = L10n.of(context);
    setState(() => _busy = true);
    try {
      await call(api);
      refreshSeating(c, widget.k);
      if (mounted) setState(_selected.clear);
      if (okMessage != null)
        messenger.showSnackBar(SnackBar(content: Text(okMessage(t))));
      return const _Outcome(_Result.ok);
    } on SeatsChanged catch (e) {
      refreshSeating(c, widget.k);
      if (mounted) setState(() => _selected.removeAll(e.takenSeats));
      messenger.showSnackBar(SnackBar(content: Text(t.seatsChanged)));
      return const _Outcome(_Result.changed);
    } on ApiException catch (e) {
      if (phoneOn400 && e.status == 400)
        return _Outcome(_Result.phone, t.phoneInvalid);
      return _Outcome(_Result.failed, errorText(t, e));
    } catch (_) {
      // Anything unexpected (a parsing error, say) still ends the busy state and lets the sheet close.
      return _Outcome(_Result.failed, t.loadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sheet(Widget Function(BuildContext) builder) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        builder: builder,
      );

  Future<void> _release(List<String> keys) async {
    if (_dialogOpen || _busy) return;
    final t = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _dialogOpen = true;
    final bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(t.releaseConfirm(keys.length, formatAmount(keys.length, ref.read(langProvider)))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              key: const Key('releaseConfirm'),
              style: compactFilled,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.releaseSeats),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    if (ok != true || !mounted) return;
    final out = await _run(
      (api) => api.releaseSeats(widget.k.orgId, widget.k.eventId, keys),
    );
    if (out.result == _Result.failed && out.message != null)
      messenger.showSnackBar(SnackBar(content: Text(out.message!)));
  }

  Future<void> _revoke(GuestTicket g) async {
    if (_dialogOpen || _busy) return;
    final t = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _dialogOpen = true;
    final bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(t.revokeGuestConfirm(g.guestName, pickLang(ref.read(langProvider), g.seatLabel ?? g.seatKey, g.seatLabelMy))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              key: const Key('revokeConfirm'),
              style: compactFilled,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.revoke),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    if (ok != true || !mounted || _busy) return;
    final api = ref.read(apiProvider);
    final c = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await api.revokeGuestTicket(widget.k.orgId, widget.k.eventId, g.id);
      refreshSeating(c, widget.k);
      messenger.showSnackBar(SnackBar(content: Text(t.guestRevoked)));
    } on ApiException catch (e) {
      // Already checked in or already revoked: say so, and show the current state.
      refreshSeating(c, widget.k);
      messenger.showSnackBar(
        SnackBar(content: Text(errorText(t, e))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.loadError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // The selection, the zoom and the open view survive a visit to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final async = ref.watch(orgSeatingProvider(widget.k));
    final data = async.value;
    if (data == null || !data.hasMap) {
      return async.hasError
          ? loadError(t, _refresh, async.error!)
          : const Center(child: CircularProgressIndicator());
    }
    _derive(data);
    final layout = _layout!;

    final selected = _selected;
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
    final guestCount =
        ref.watch(guestTicketsProvider(widget.k)).value?.where((g) => g.status != 'VOID').length ?? 0;

    // The bar floats over the map: its measured height is added below the map's pan boundary, so the last rows can
    // be brought above it. boundaryMargin is in scene units; at low zoom a unit is fewer pixels, so this over-provisions.
    final barShown = widget.canEdit && chosen.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = barShown ? (_barKey.currentContext?.size?.height ?? 0) : 0.0;
      if ((h - _barHeight).abs() > 0.5) setState(() => _barHeight = h);
    });
    final barPx = barShown ? _barHeight : 0.0;
    final extraBottom = barPx / math.max(_controller.scale, 0.5);

    // The selection bar floats over the bottom of the map: the map keeps its size (and its pan and zoom) when it comes and goes.
    final mapView = Stack(
      children: [
        Column(
          children: [
            _Legend(data: data),
            if (!widget.canEdit)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ViewOnly(text: t.viewOnlySeats),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SeatMapView(
                    layout: layout,
                    states: states,
                    colors: colors,
                    selected: indexes,
                    lang: lang,
                    controller: _controller,
                    extraBoundary: EdgeInsets.only(bottom: extraBottom),
                    onScaleChanged: (_) => setState(() {}),
                    onSeatTap: widget.canEdit ? _tap : null,
                    overlayBuilder: (ctx, scale) =>
                        scale >= kSeatTapScale || !widget.canEdit
                        ? const SizedBox.shrink()
                        : Positioned(
                            left: 8,
                            right: 8,
                            bottom: math.max(8, barPx),
                            child: IgnorePointer(
                              child: Container(
                                key: const Key('seatsZoomHint'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    ctx,
                                  ).colorScheme.surface.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  t.seatsZoomHint,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.canEdit && chosen.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KeyedSubtree(
              key: _barKey,
              child: _SelectionBar(
              seats: chosen,
              busy: _busy,
              onClear: _clear,
              onHold: () => _sheet(
                (_) => _HoldSheet(
                  count: chosen.length,
                  submit: (label) => _run(
                    (api) => api.holdSeats(widget.k.orgId, widget.k.eventId, [
                      for (final s in chosen) s.seatKey,
                    ], label),
                  ),
                ),
              ),
              onRelease: () => _release([for (final s in chosen) s.seatKey]),
              onIssue: () {
                final keys = [for (final s in chosen) s.seatKey];
                _sheet(
                  (_) => _IssueSheet(
                    count: keys.length,
                    submit: (name, phone, label) => _run(
                      (api) => api.issueGuestTickets(
                        widget.k.orgId,
                        widget.k.eventId,
                        keys,
                        guestName: name,
                        phone: phone,
                        label: label,
                      ),
                      okMessage: (t) => t.ticketsIssued(keys.length, formatAmount(keys.length, ref.read(langProvider))),
                      phoneOn400: true,
                    ),
                  ),
                );
              },
            ),
            ),
          ),
      ],
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(
                    t.seatsViewMap,
                    key: const Key('seatsViewMap'),
                    textAlign: TextAlign.center,
                  ),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(
                    t.seatsViewGuests(_n(context, guestCount)),
                    key: const Key('seatsViewGuests'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              selected: {_guestsView},
              onSelectionChanged: (s) => setState(() => _guestsView = s.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _guestsView ? 1 : 0,
            children: [
              mapView,
              _GuestTickets(
                k: widget.k,
                canEdit: widget.canEdit,
                lang: lang,
                busy: _busy,
                onRevoke: _revoke,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewOnly extends StatelessWidget {
  const _ViewOnly({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      key: const Key('viewOnlySeats'),
      children: [
        const Icon(Icons.lock_outline, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class _Legend extends StatefulWidget {
  const _Legend({required this.data});
  final OrgSeating data;
  @override
  State<_Legend> createState() => _LegendState();
}

class _LegendState extends State<_Legend> {
  final _scroll = ScrollController();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// True while there is more of the line to scroll to: the fade at the right edge says so.
  void _measure() {
    if (!_scroll.hasClients) return;
    final more = _scroll.position.maxScrollExtent - _scroll.offset > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final t = L10n.of(context);
    final theme = Theme.of(context);
    int sum(int Function(SeatCounts) f) =>
        data.counts.values.fold(0, (a, c) => a + f(c));
    final typeColor =
        data.colors.values.map(parseHexColor).whereType<Color>().firstOrNull ??
        E360Colors.gold;
    Widget item(String key, Widget mark, String label, [int? n]) => Row(
      key: Key(key),
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(n == null ? label : '$label ${_n(context, n)}', style: theme.textTheme.bodySmall),
      ],
    );
    Widget dot(Color c, [IconData? icon]) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: icon == null ? null : Icon(icon, size: 11, color: Colors.white),
    );
    // One scrolling line: the map below keeps the height.
    final line = ScrollConfiguration(
      behavior: dragEverywhere,
      child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          item(
            'legendAvailable',
            dot(typeColor),
            t.legendAvailable,
            sum((c) => c.available),
          ),
          const SizedBox(width: 16),
          item(
            'legendHeld',
            dot(const Color(0xFFBDBDBD), Icons.close),
            t.legendHeld,
            sum((c) => c.guest),
          ),
          const SizedBox(width: 16),
          item(
            'legendSold',
            dot(const Color(0xFFBDBDBD)),
            t.legendSold,
            sum((c) => c.sold),
          ),
          const SizedBox(width: 16),
          item(
            'legendGuest',
            dot(const Color(0xFFBDBDBD), Icons.person),
            t.legendGuest,
            sum((c) => c.comp),
          ),
          const SizedBox(width: 16),
          item(
            'legendSelected',
            dot(theme.colorScheme.onSurface, Icons.check),
            t.legendSelected,
          ),
        ],
      ),
    ));
    // A fade at the right edge while the line goes on.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(children: [
      line,
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 32,
        child: IgnorePointer(
          child: AnimatedOpacity(
            key: const Key('legendFade'),
            opacity: _more ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [bg.withValues(alpha: 0), bg]))),
          ),
        ),
      ),
    ]);
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.seats,
    required this.busy,
    required this.onClear,
    required this.onHold,
    required this.onRelease,
    required this.onIssue,
  });
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
    final tooMany = n > maxSeatsPerAction;
    final noType = held && seats.any((s) => s.ticketTypeId == null);
    final label = n == 1 ? seats.first.holdLabel : null;
    final String? hint = tooMany
        ? t.seatsTooMany
        : (!free && !held)
        ? t.seatsMixedHint
        : noType
        ? t.seatsNoTypeHint
        : null;
    final canAct = !tooMany && !busy;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              key: const Key('selectionBar'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(key: Key('seatsBusy')),
                  ),
                // The text may scroll at huge text sizes; the actions stay in reach.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.seatsSelected(n, _n(context, n)),
                                key: const Key('seatsSelected'),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              key: const Key('seatsClear'),
                              onPressed: busy ? null : onClear,
                              child: Text(t.clear),
                            ),
                          ],
                        ),
                        if (label != null && label.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              t.heldLabel(label),
                              key: const Key('seatsHoldLabel'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        if (hint != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              hint,
                              key: const Key('seatsHint'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (free)
                  FilledButton(
                    key: const Key('seatsHold'),
                    style: E360Buttons.gold,
                    onPressed: canAct ? onHold : null,
                    child: Text(t.holdForGuests),
                  ),
                if (held) ...[
                  FilledButton(
                    key: const Key('seatsIssue'),
                    style: E360Buttons.gold,
                    onPressed: canAct && !noType ? onIssue : null,
                    child: Text(t.issueGuestTickets),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('seatsRelease'),
                    style: E360Buttons.outline,
                    onPressed: canAct ? onRelease : null,
                    child: Text(t.releaseSeats),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The guest tickets as their own list: pull to refresh, Revoke on the ones that can still be revoked.
class _GuestTickets extends ConsumerWidget {
  const _GuestTickets({
    required this.k,
    required this.canEdit,
    required this.lang,
    required this.busy,
    required this.onRevoke,
  });
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
    Future<void> refresh() async {
      ref.invalidate(guestTicketsProvider(k));
      try {
        await ref.read(guestTicketsProvider(k).future);
      } catch (_) {}
    }

    if (list == null) {
      return async.hasError
          ? loadError(t, refresh, async.error!)
          : const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: list.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  t.noGuestTickets,
                  key: const Key('noGuestTickets'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            )
          : ListView.builder(
              key: const Key('guestTicketList'),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final g = list[i];
                final seat = g.seatLabel == null
                    ? g.seatKey
                    : pickLang(lang, g.seatLabel!, g.seatLabelMy);
                final dead = !g.checkedIn && g.status != 'VALID';
                final tile = ListTile(
                  key: Key('guestTicket-${g.id}'),
                  title: Text(
                    g.guestName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          g.phone,
                          seat,
                          if (g.label != null && g.label!.isNotEmpty) g.label!,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      E360Badge(
                        _status(t, g),
                        kind: g.checkedIn
                            ? E360BadgeKind.success
                            : E360BadgeKind.neutral,
                      ),
                      if (canEdit && g.canRevoke)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: OutlinedButton(
                              key: Key('guestRevoke-${g.id}'),
                              style: E360Buttons.outline,
                              onPressed: busy ? null : () => onRevoke(g),
                              child: Text(t.revoke),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                return dead ? Opacity(opacity: 0.6, child: tile) : tile;
              },
            ),
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

/// Sheet asking for the label of a hold. The request runs in the tab ([submit]); while it runs the sheet cannot be dismissed.
class _HoldSheet extends StatefulWidget {
  const _HoldSheet({required this.count, required this.submit});
  final int count;
  final Future<_Outcome> Function(String label) submit;
  @override
  State<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends State<_HoldSheet> {
  final _label = TextEditingController();
  bool _busy = false;
  String? _labelError, _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
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
    final out = await widget.submit(label);
    if (!mounted) return;
    if (out.closes) {
      nav.pop();
    } else {
      setState(() {
        _busy = false;
        _error = out.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.holdForGuests, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              t.seatsSelected(widget.count, _n(context, widget.count)),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('holdLabel'),
              controller: _label,
              enabled: !_busy,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              decoration: InputDecoration(
                labelText: t.holdLabelField,
                errorText: _labelError,
              ),
              onChanged: (_) {
                if (_labelError != null) setState(() => _labelError = null);
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('sheetError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('holdSubmit'),
              style: E360Buttons.gold,
              onPressed: _busy ? null : _submit,
              child: Text(t.holdForGuests),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet collecting the guest's details, then a confirm step that repeats the number. The request runs in the tab.
class _IssueSheet extends StatefulWidget {
  const _IssueSheet({required this.count, required this.submit});
  final int count;
  final Future<_Outcome> Function(String name, String phone, String label)
  submit;
  @override
  State<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends State<_IssueSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;
  bool _confirming = false;
  String? _nameError, _phoneError, _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _confirming) return;
    final t = L10n.of(context);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() {
      _nameError = name.isEmpty ? t.fieldRequired : null;
      _phoneError = phone.isEmpty
          ? t.fieldRequired
          : (!isMyanmarMobile(phone) ? t.phoneInvalid : null);
      _error = null;
    });
    if (_nameError != null || _phoneError != null) return;
    // A mistyped number gives the tickets to a stranger: repeat it before sending.
    _confirming = true;
    final bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            // The number never breaks across lines: its spaces do not wrap
            t.issueConfirmText(widget.count, phone.replaceAll(RegExp(r'\s+'), '\u00A0'), _n(context, widget.count)),
            key: const Key('issueConfirmText'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.cancel),
            ),
            FilledButton(
              key: const Key('issueConfirm'),
              style: compactFilled,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.issueShort),
            ),
          ],
        ),
      );
    } finally {
      _confirming = false;
    }
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final out = await widget.submit(name, phone, _label.text.trim());
    if (!mounted) return;
    if (out.closes) {
      nav.pop();
    } else {
      setState(() {
        _busy = false;
        if (out.result == _Result.phone) {
          _phoneError = out.message;
        } else {
          _error = out.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.issueGuestTickets, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              t.seatsSelected(widget.count, _n(context, widget.count)),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t.issueHelp,
              key: const Key('issueHelp'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('guestName'),
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: InputDecoration(
                labelText: t.guestNameField,
                errorText: _nameError,
              ),
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
              decoration: InputDecoration(
                labelText: t.guestPhoneField,
                errorText: _phoneError,
              ),
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('sheetError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('issueSubmit'),
              style: E360Buttons.gold,
              onPressed: _busy ? null : _submit,
              child: Text(t.issueGuestTickets),
            ),
          ],
        ),
      ),
    );
  }
}
