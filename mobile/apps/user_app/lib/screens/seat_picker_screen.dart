import 'dart:async';
import 'dart:math';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Seats are tappable from this zoom (screen px per layout unit); below it a tap on a section zooms into it.
const double kSeatTapScale = 1.6;

/// The API accepts at most this many seats in one order.
const int kMaxSeatsPerOrder = 20;

/// Pick seats on the venue map (pinch-zoom), or let the server choose the best ones, then continue to checkout.
class SeatPickerScreen extends ConsumerStatefulWidget {
  const SeatPickerScreen({super.key, required this.idOrSlug, this.pollInterval = const Duration(seconds: 5)});
  final String idOrSlug;

  /// How often availability is refreshed while the screen is open and in the foreground.
  final Duration pollInterval;

  @override
  ConsumerState<SeatPickerScreen> createState() => _SeatPickerScreenState();
}

class _SeatPickerScreenState extends ConsumerState<SeatPickerScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  final String _idempotencyKey = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  SeatMapData? _data;
  SeatLayout? _layout;
  List<SeatState> _states = const [];
  List<Color?> _colors = const [];
  List<int?> _typeOf = const [];
  List<int> _selected = []; // seat indexes, in the order they were picked

  Timer? _poll;
  bool _loading = false;
  bool _busy = false;
  bool _loadFailed = false;
  String? _notice; // e.g. "just taken"
  String? _error;
  Size _viewport = Size.zero;
  double _fit = 0.3;
  double _scale = 0.3;
  bool _placed = false;
  bool _forceNext = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onTransform);
    _load();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _anim.dispose();
    _controller
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _startPolling();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(widget.pollInterval, (_) => _load());
  }

  /// Screen px per layout unit. (Not getMaxScaleOnAxis: it includes the z axis, which stays 1.)
  double get _zoom => _controller.value.entry(0, 0);

  void _onTransform() {
    final s = _zoom;
    if ((s - _scale).abs() > 0.02 && mounted) setState(() => _scale = s);
  }

  // ───── Data ─────

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final d = await ref.read(apiProvider).seatMap(widget.idOrSlug);
      if (!mounted) return;
      _apply(d);
    } on ApiException {
      if (mounted && _data == null) setState(() => _loadFailed = true);
    } finally {
      _loading = false;
    }
  }

  void _apply(SeatMapData d) {
    final old = _data;
    final force = _forceNext;
    _forceNext = false;
    if (!force && old != null && old.versionId == d.versionId && old.status == d.status && old.seatTypes == d.seatTypes) return; // nothing changed: no repaint
    final layout = (old != null && old.versionId == d.versionId) ? _layout! : SeatLayout.fromJson(d.layout);
    final colors = <Color?>[];
    final typeOf = <int?>[];
    final states = <SeatState>[];
    for (var i = 0; i < layout.seats.length; i++) {
      final ti = i < d.seatTypes.length ? seatTypeIndex(d.seatTypes[i]) : null;
      final valid = ti != null && ti < d.types.length;
      typeOf.add(valid ? ti : null);
      colors.add(valid ? (parseHexColor(d.types[ti].color) ?? Colors.deepPurple) : null);
      states.add(i < d.status.length ? SeatState.fromChar(d.status[i]) : SeatState.unavailable);
    }
    // Seats the buyer picked that someone else took meanwhile
    final lost = [for (final i in _selected) if (states[i] != SeatState.available) i];
    final lang = ref.read(langProvider);
    setState(() {
      _data = d;
      _layout = layout;
      _states = states;
      _colors = colors;
      _typeOf = typeOf;
      _loadFailed = false;
      if (lost.isNotEmpty) {
        _selected = [for (final i in _selected) if (!lost.contains(i)) i];
        _notice = L10n.of(context).seatsJustTaken([for (final i in lost) layout.seats[i].labelFor(lang)].join(', '));
      }
    });
  }

  // ───── Selection ─────

  /// The smallest per-person limit among the given seats' ticket types (and never more than the API accepts).
  int _cap(Iterable<int> seatIdx) {
    final event = ref.read(eventProvider(widget.idOrSlug)).value;
    var cap = kMaxSeatsPerOrder;
    for (final i in seatIdx) {
      final ti = _typeOf[i];
      if (ti == null) continue;
      final id = _data!.types[ti].id;
      final tt = event?.ticketTypes.where((x) => x.id == id).firstOrNull;
      if (tt != null) cap = min(cap, tt.maxPerOrder);
    }
    return cap;
  }

  void _toggle(MapSeat seat) {
    final t = L10n.of(context);
    final i = seat.index;
    setState(() {
      _error = null;
      _notice = null;
    });
    if (_selected.contains(i)) {
      setState(() => _selected = [for (final s in _selected) if (s != i) s]);
      return;
    }
    if (_states[i] != SeatState.available || _typeOf[i] == null) {
      _snack(t.seatNotAvailable);
      return;
    }
    final cap = _cap([..._selected, i]);
    if (_selected.length >= cap) {
      _snack(t.seatLimit(cap));
      return;
    }
    setState(() => _selected = [..._selected, i]);
  }

  void _snack(String text) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  int get _total => _selected.fold(0, (sum, i) => sum + (_typeOf[i] == null ? 0 : _data!.types[_typeOf[i]!].priceMmk));

  // ───── Zoom ─────

  void _place(Size viewport) {
    final l = _layout;
    if (l == null) return;
    final fit = min(viewport.width / l.width, viewport.height / l.height);
    if (_placed && viewport == _viewport) return;
    _viewport = viewport;
    _fit = fit;
    if (!_placed) {
      _placed = true;
      final dx = (viewport.width - l.width * fit) / 2;
      final dy = (viewport.height - l.height * fit) / 2;
      _scale = fit; // before the controller notifies, so the listener doesn't setState during build
      _controller.value = Matrix4.diagonal3Values(fit, fit, 1)..setTranslationRaw(dx, dy, 0);
    }
  }

  /// Zooms to fit [r], but never below the zoom where seats are tappable; when [r] is too big for that
  /// (a large section) it centres on [focus] (the tap) instead.
  void _zoomTo(Rect r, {Offset? focus}) {
    if (_viewport == Size.zero) return;
    const pad = 24.0;
    final fitScale = min(_viewport.width / (r.width + pad * 2), _viewport.height / (r.height + pad * 2));
    const minTappable = kSeatTapScale + 0.2;
    final s = fitScale.clamp(minTappable, 6.0);
    var c = r.center;
    if (fitScale < minTappable && focus != null) {
      // keep the whole viewport inside the section where possible
      final halfW = _viewport.width / s / 2, halfH = _viewport.height / s / 2;
      c = Offset(focus.dx.clamp(r.left + min(halfW, r.width / 2), r.right - min(halfW, r.width / 2)), focus.dy.clamp(r.top + min(halfH, r.height / 2), r.bottom - min(halfH, r.height / 2)));
    }
    final end = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(_viewport.width / 2 - c.dx * s, _viewport.height / 2 - c.dy * s, 0);
    final tween = Matrix4Tween(begin: _controller.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    void tick() => _controller.value = tween.value;
    tween.addListener(tick);
    _anim.forward(from: 0).whenComplete(() => tween.removeListener(tick));
  }

  void _onTap(Offset p) {
    final l = _layout;
    if (l == null) return;
    if (_zoom >= kSeatTapScale) {
      final seat = l.seatAt(p);
      if (seat != null) _toggle(seat);
    } else {
      final sec = l.sectionAt(p);
      if (sec != null) _zoomTo(sec.bounds, focus: p);
    }
  }

  // ───── Actions ─────

  Future<void> _best() async {
    final d = _data!;
    final event = ref.read(eventProvider(widget.idOrSlug)).value;
    final keys = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BestSheet(idOrSlug: widget.idOrSlug, types: d.types, event: event, available: _availableByType()),
    );
    final l = _layout;
    if (keys == null || l == null || !mounted) return;
    final picked = [for (final k in keys) if (l.seatByKey(k) != null) l.seatByKey(k)!];
    if (picked.isEmpty) return;
    setState(() {
      _selected = [for (final s in picked) s.index];
      _notice = null;
      _error = null;
    });
    _zoomTo(picked.map((s) => Rect.fromCircle(center: s.pos, radius: kSeatRadius)).reduce((a, b) => a.expandToInclude(b)).inflate(40));
  }

  List<int> _availableByType() {
    final d = _data!;
    final n = List.filled(d.types.length, 0);
    for (var i = 0; i < _states.length; i++) {
      final ti = _typeOf[i];
      if (ti != null && _states[i] == SeatState.available) n[ti]++;
    }
    return n;
  }

  Future<void> _continue() async {
    final t = L10n.of(context);
    final l = _layout!;
    final event = ref.read(eventProvider(widget.idOrSlug)).value;
    if (event == null || _selected.isEmpty) return;
    final me = await ref.read(sessionProvider.future);
    if (!mounted) return;
    if (me == null) {
      await context.push('/login?from=${Uri.encodeComponent('/event/${event.id}/seats')}');
      return;
    }
    final keys = [for (final i in _selected) l.seats[i].seatKey];
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final key = '$_idempotencyKey-${Object.hashAll([...keys]..sort()).toRadixString(16)}';
      final o = await ref.read(apiProvider).createOrder(event.id, const {}, idempotencyKey: key, seats: keys);
      ref.invalidate(eventProvider(event.id));
      ref.invalidate(pendingOrdersProvider);
      if (!mounted) return;
      if (o.isPaid) {
        ref.invalidate(myTicketsProvider);
        _snack(t.registered);
        context.go('/tickets');
      } else {
        setState(() => _selected = []);
        await context.push('/checkout/${o.id}');
        if (mounted) _load();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409 && e.takenSeats.isNotEmpty) {
        final lang = ref.read(langProvider);
        final taken = [for (final k in e.takenSeats) if (l.seatByKey(k) != null) l.seatByKey(k)!];
        setState(() {
          _selected = [for (final i in _selected) if (!taken.any((s) => s.index == i)) i];
          _notice = t.seatsJustTaken([for (final s in taken) s.labelFor(lang)].join(', '));
        });
        _forceNext = true; // the map may look unchanged to us, but those seats are gone
        await _load();
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───── UI ─────

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final d = _data;
    final l = _layout;
    final event = ref.watch(eventProvider(widget.idOrSlug)).value;

    Widget body;
    if (d == null || l == null) {
      body = _loadFailed
          ? MessageView(icon: Icons.error_outline, message: t.loadError, actionLabel: t.retry, onAction: () {
              setState(() => _loadFailed = false);
              _load();
            })
          : const Center(child: CircularProgressIndicator());
    } else {
      body = Column(children: [
        _Legend(types: d.types, lang: lang),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            _place(Size(c.maxWidth, c.maxHeight));
            return Stack(children: [
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: InteractiveViewer(
                    transformationController: _controller,
                    constrained: false,
                    minScale: _fit,
                    maxScale: max(6, _fit),
                    boundaryMargin: const EdgeInsets.all(120),
                    child: GestureDetector(
                      key: const Key('seatMap'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _onTap(details.localPosition),
                      child: CustomPaint(
                        size: Size(l.width, l.height),
                        painter: SeatMapPainter(
                          layout: l,
                          states: _states,
                          colors: _colors,
                          selected: _selected.toSet(),
                          lang: lang,
                          scale: _scale,
                          ink: theme.colorScheme.onSurface,
                          highlightSection: null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_scale < kSeatTapScale)
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Center(
                      child: Material(
                        color: theme.colorScheme.inverseSurface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Text(t.zoomToPick, key: const Key('zoomHint'), style: TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        ),
        _BottomBar(
          layout: l,
          selected: _selected,
          lang: lang,
          totalMmk: _total,
          notice: _notice,
          error: _error,
          busy: _busy,
          canContinue: event != null,
          onRemove: (i) => setState(() => _selected = [for (final s in _selected) if (s != i) s]),
          onBest: _best,
          onContinue: _continue,
        ),
      ]);
    }
    return Scaffold(
      appBar: AppBar(title: Text(event == null ? t.seatPickerTitle : pickLang(lang, event.title, event.titleMy), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: body,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.types, required this.lang});
  final List<SeatTypeInfo> types;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    Widget dot(Color c, String text, {IconData? icon}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            child: icon == null ? null : Icon(icon, size: 10, color: Colors.white),
          ),
          const SizedBox(width: 5),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final ty in types)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: dot(parseHexColor(ty.color) ?? Colors.deepPurple, '${ty.label(lang)} · ${t.mmk(formatAmount(ty.priceMmk, lang))}')),
            ),
          Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: dot(const Color(0xFFBDBDBD), t.legendTaken))),
          Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: dot(Colors.grey, t.legendWheelchair, icon: Icons.accessible))),
          Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: dot(Colors.grey, t.legendRestricted, icon: Icons.visibility_off))),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.layout,
    required this.selected,
    required this.lang,
    required this.totalMmk,
    required this.notice,
    required this.error,
    required this.busy,
    required this.canContinue,
    required this.onRemove,
    required this.onBest,
    required this.onContinue,
  });
  final SeatLayout layout;
  final List<int> selected;
  final String lang;
  final int totalMmk;
  final String? notice;
  final String? error;
  final bool busy;
  final bool canContinue;
  final void Function(int seatIndex) onRemove;
  final VoidCallback onBest;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (notice != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(notice!, key: const Key('seatNotice'), style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600))),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, key: const Key('seatError'), style: TextStyle(color: theme.colorScheme.error))),
            if (selected.isEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t.tapSeatHint, style: theme.textTheme.bodyMedium))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 76),
                child: SingleChildScrollView(
                  child: Wrap(spacing: 6, runSpacing: 0, children: [
                    for (final i in selected)
                      InputChip(
                        key: Key('chip-${layout.seats[i].seatKey}'),
                        label: Text(layout.seats[i].labelFor(lang), style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onDeleted: () => onRemove(i),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('${t.seatsChosen(selected.length)} · ${t.total}', style: theme.textTheme.bodyMedium)),
              Text(t.mmk(formatAmount(totalMmk, lang)), key: const Key('seatTotal'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('bestAvailable'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: busy ? null : onBest,
                  child: Text(t.bestAvailable),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('seatContinue'),
                  onPressed: busy || selected.isEmpty || !canContinue ? null : onContinue,
                  child: busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.continueLabel),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// "Best available": choose a ticket type and how many; the server picks adjacent seats. Pops with the seat keys.
class _BestSheet extends ConsumerStatefulWidget {
  const _BestSheet({required this.idOrSlug, required this.types, required this.event, required this.available});
  final String idOrSlug;
  final List<SeatTypeInfo> types;
  final EventSummary? event;
  final List<int> available; // free seats per type, same order as [types]

  @override
  ConsumerState<_BestSheet> createState() => _BestSheetState();
}

class _BestSheetState extends ConsumerState<_BestSheet> {
  late int _type = max(0, widget.available.indexWhere((n) => n > 0));
  int _qty = 2;
  bool _busy = false;
  String? _error;

  int get _max {
    final id = widget.types[_type].id;
    final tt = widget.event?.ticketTypes.where((x) => x.id == id).firstOrNull;
    return min(min(kMaxSeatsPerOrder, tt?.maxPerOrder ?? kMaxSeatsPerOrder), max(1, widget.available[_type]));
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final seats = await ref.read(apiProvider).bestSeats(widget.idOrSlug, widget.types[_type].id, min(_qty, _max));
      if (mounted) Navigator.of(context).pop(seats);
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
    final qty = min(_qty, _max);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.bestAvailable, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(t.bestAvailableHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(t.ticketTypeLabel, style: theme.textTheme.labelLarge),
        for (var i = 0; i < widget.types.length; i++)
          RadioListTile<int>(
            key: Key('best-type-$i'),
            contentPadding: EdgeInsets.zero,
            value: i,
            groupValue: _type,
            onChanged: widget.available[i] > 0 && !_busy ? (v) => setState(() => _type = v!) : null,
            title: Text(widget.types[i].label(lang)),
            subtitle: Text(t.remaining(widget.available[i])),
            secondary: Text(t.mmk(formatAmount(widget.types[i].priceMmk, lang)), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        Row(children: [
          Expanded(child: Text(t.quantity)),
          IconButton.outlined(key: const Key('bestMinus'), onPressed: qty > 1 ? () => setState(() => _qty = qty - 1) : null, icon: const Icon(Icons.remove)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$qty', key: const Key('bestQty'), style: theme.textTheme.titleLarge)),
          IconButton.outlined(key: const Key('bestPlus'), onPressed: qty < _max ? () => setState(() => _qty = qty + 1) : null, icon: const Icon(Icons.add)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('bestError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('bestFind'),
          onPressed: _busy || widget.available.every((n) => n == 0) ? null : _find,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.findSeats),
        ),
      ]),
    );
  }
}
