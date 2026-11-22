import 'dart:async';
import 'dart:math';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/promo_text.dart';
import '../app/providers.dart';
import '../app/waitlist_text.dart';
import '../l10n/app_localizations.dart';
import '../widgets/discount_lines.dart';
import '../widgets/total_amounts.dart';
import '../widgets/waitlist_offer.dart';

/// Seats are tappable from this zoom (screen px per layout unit); below it a tap on a section zooms into it.
const double kSeatTapScale = 1.6;

/// The API accepts at most this many seats in one order.
const int kMaxSeatsPerOrder = 20;

/// Pick seats on the venue map (pinch-zoom), or let the server choose the best ones, then continue to checkout.
class SeatPickerScreen extends ConsumerStatefulWidget {
  const SeatPickerScreen({super.key, required this.idOrSlug, this.offerEntryId, this.pollInterval = const Duration(seconds: 5)});
  final String idOrSlug;

  /// The buyer's waitlist offer being bought (`/me/waitlist` entry id): its seats are shown as theirs and preselected.
  final String? offerEntryId;

  /// How often availability is refreshed while the screen is open and in the foreground.
  final Duration pollInterval;

  @override
  ConsumerState<SeatPickerScreen> createState() => _SeatPickerScreenState();
}

class _SeatPickerScreenState extends ConsumerState<SeatPickerScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  static String _newSalt() => List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  /// Retries of the same seats reuse an order; renewed after each order so picking them again (say after
  /// cancelling that order in checkout) makes a new one instead of reopening the dead order.
  String _idempotencyKey = _newSalt();

  SeatMapData? _data;
  SeatLayout? _layout;
  List<SeatState> _states = const [];
  List<Color?> _colors = const [];
  List<int?> _typeOf = const [];
  List<int> _selected = []; // seat indexes, in the order they were picked
  Set<int> _reserved = {}; // seats a live waitlist offer holds for this buyer (the public map shows them taken)
  bool _preselected = false; // the offered seats were put in the selection once
  bool _hadOffer = false;
  bool _boughtFromOffer = false; // this app just made an order from the offer: its seats leaving the map is expected

  // Promo: the entered code, the last check for the current seats (null while pending), and a debounce for re-checks
  final _promoCtl = TextEditingController();
  bool _promoOpen = false;
  String _promoCode = ''; // applied code; empty = none
  PromoCheck? _promo;
  String? _promoError; // the last check failed for a non-validation reason (rate limit, network, 5xx): Continue stays off
  bool _promoChecking = false;
  Timer? _promoDebounce;
  int _promoSeq = 0; // answers to older checks are ignored

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
  bool _reloadQueued = false;
  Animation<Matrix4>? _zoomAnim;
  VoidCallback? _zoomTick;

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
    _promoDebounce?.cancel();
    _promoCtl.dispose();
    if (_zoomTick != null) _zoomAnim?.removeListener(_zoomTick!);
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

  // ───── Waitlist offer ─────

  /// The live offer this screen was opened for, if it is still live.
  WaitlistEntry? get _offer {
    final id = widget.offerEntryId;
    if (id == null) return null;
    final entries = ref.read(waitlistProvider).value ?? const <WaitlistEntry>[];
    return entries.where((e) => e.id == id && e.isOffered).firstOrNull;
  }

  // ───── Data ─────

  /// [force] repaints even if the response looks unchanged. If a load is already running, one follow-up
  /// load is queued instead, so the older (possibly stale) response can't stand in for it.
  Future<void> _load({bool force = false}) async {
    if (_loading) {
      if (force) _reloadQueued = true;
      return;
    }
    _loading = true;
    try {
      final d = await ref.read(apiProvider).seatMap(widget.idOrSlug);
      if (!mounted) return;
      _apply(d, force: force);
    } catch (_) {
      // Network, API or parse errors: keep what we have; only a first load that fails shows the error
      if (mounted && _data == null) setState(() => _loadFailed = true);
    } finally {
      _loading = false;
    }
    if (_reloadQueued && mounted) {
      _reloadQueued = false;
      await _load(force: true);
    }
  }

  static bool _sameTypes(List<SeatTypeInfo> a, List<SeatTypeInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name || a[i].nameMy != b[i].nameMy || a[i].priceMmk != b[i].priceMmk || a[i].color != b[i].color) return false;
    }
    return true;
  }

  void _apply(SeatMapData d, {bool force = false}) {
    final old = _data;
    if (!force && old != null && old.versionId == d.versionId && old.status == d.status && old.seatTypes == d.seatTypes && _sameTypes(old.types, d.types)) return; // nothing changed: no repaint
    // A different map version has different seats: the old picks mean nothing
    if (old != null && old.versionId != d.versionId) {
      _selected = [];
      _preselected = false;
    }
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
    // The seats reserved for this buyer look taken on the public map; here they are theirs
    final offer = _offer;
    final reserved = <int>{};
    if (offer != null) {
      for (final k in offer.seatKeys) {
        final seat = layout.seatByKey(k);
        if (seat != null && seat.index < states.length && typeOf[seat.index] != null) {
          reserved.add(seat.index);
          states[seat.index] = SeatState.available;
        }
      }
    }
    // An offer that ended because it was bought (by this app just now, or the server says PURCHASED) is not "ended"
    final entry = (ref.read(waitlistProvider).value ?? const <WaitlistEntry>[]).where((e) => e.id == widget.offerEntryId).firstOrNull;
    final bought = _boughtFromOffer || entry?.status == 'PURCHASED';
    final offerEnded = _hadOffer && offer == null && widget.offerEntryId != null && !bought;
    // Seats the buyer picked that someone else took meanwhile (or whose reservation ended)
    final lost = [for (final i in _selected) if (states[i] != SeatState.available) i];
    final lang = ref.read(langProvider);
    setState(() {
      if (offer != null) _hadOffer = true;
      _reserved = reserved;
      if (reserved.isNotEmpty && !_preselected) {
        _preselected = true;
        _selected = [..._selected, for (final i in reserved) if (!_selected.contains(i)) i];
      }
      _data = d;
      _layout = layout;
      _states = states;
      _colors = colors;
      _typeOf = typeOf;
      _loadFailed = false;
      if (lost.isNotEmpty) {
        _selected = [for (final i in _selected) if (!lost.contains(i)) i];
        _notice = bought && offer == null
            ? null
            : offerEnded
                ? L10n.of(context).offerEnded
                : L10n.of(context).seatsJustTaken([for (final i in lost) layout.seats[i].labelFor(lang)].join(', '));
      } else if (offerEnded) {
        _notice = L10n.of(context).offerEnded;
      }
    });
    final repriced = old != null && old.versionId == d.versionId && (old.seatTypes != d.seatTypes || !_sameTypes(old.types, d.types));
    if (lost.isNotEmpty || (old != null && old.versionId != d.versionId) || (repriced && _selected.isNotEmpty)) _seatsChanged();
  }

  // ───── Promo ─────

  List<String> get _seatKeys => [for (final i in _selected) _layout!.seats[i].seatKey];

  /// The seats changed: the old discount no longer applies, so hide it and re-check shortly (debounced).
  void _seatsChanged() {
    _promoDebounce?.cancel();
    _promoSeq++;
    if (_promoCode.isEmpty) return;
    setState(() {
      _promo = null;
      _promoError = null;
      _promoChecking = _selected.isNotEmpty;
    });
    if (_selected.isEmpty) return;
    _promoDebounce = Timer(const Duration(milliseconds: 300), _checkPromo);
  }

  void _applyPromo() {
    final code = _promoCtl.text.trim();
    if (code.isEmpty) return;
    _promoDebounce?.cancel();
    setState(() {
      _promoCode = code;
      _promo = null;
      _promoError = null;
      _promoChecking = _selected.isNotEmpty;
    });
    if (_selected.isNotEmpty) _checkPromo();
  }

  void _removePromo() {
    _promoDebounce?.cancel();
    _promoSeq++;
    setState(() {
      _promoCode = '';
      _promo = null;
      _promoError = null;
      _promoChecking = false;
      _promoOpen = false;
      _promoCtl.clear();
    });
  }

  Future<void> _checkPromo() async {
    final event = ref.read(eventProvider(widget.idOrSlug)).value;
    final keys = _seatKeys;
    final code = _promoCode;
    if (code.isEmpty || keys.isEmpty) {
      if (mounted) setState(() => _promoChecking = false);
      return;
    }
    if (event == null) return; // still pending: the event listener in build re-runs this once it loads
    final seq = ++_promoSeq;
    PromoCheck? r;
    String? failure;
    try {
      r = await ref.read(apiProvider).checkPromo(event.id, code, const {}, seats: keys);
    } on ApiException catch (e) {
      final status = e.status;
      if (status != null && status >= 400 && status < 500 && status != 429) {
        r = PromoCheck(valid: false, discountMmk: 0, totalMmk: _total); // the server rejected the request itself
      } else {
        failure = e.message; // rate limit, network or server error: unknown, so never fall back to full price
      }
    } catch (_) {
      failure = L10n.of(context).loadError;
    }
    if (!mounted || seq != _promoSeq) return; // seats changed (or code removed) meanwhile
    setState(() {
      _promo = r;
      _promoError = failure;
      _promoChecking = false;
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
      _seatsChanged();
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
    _seatsChanged();
  }

  void _snack(String text) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  /// A code is entered for the chosen seats and its answer is not in yet (or the check failed): Continue stays off.
  bool get _codePending => _promoCode.isNotEmpty && _selected.isNotEmpty && (_promoChecking || _promo == null);

  /// Seats of paid types: the only ones a group discount counts.
  int get _paidSeats => _selected.where((i) => _typeOf[i] != null && _data!.types[_typeOf[i]!].priceMmk > 0).length;
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
    // One listener at a time: a new zoom replaces the running one
    if (_zoomTick != null) _zoomAnim?.removeListener(_zoomTick!);
    _zoomAnim = tween;
    _zoomTick = () => _controller.value = tween.value;
    tween.addListener(_zoomTick!);
    _anim.forward(from: 0);
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
      builder: (_) => _BestSheet(idOrSlug: widget.idOrSlug, types: d.types, event: event, available: _availableByType(), offerEntryId: _offer?.id),
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
    _seatsChanged();
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
    if (_promoCode.isNotEmpty && (_promoChecking || _promo == null)) return; // wait for the re-check
    final code = _promo?.valid == true ? _promoCode : null;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final key = '$_idempotencyKey-${Object.hashAll([...([...keys]..sort()), code ?? '']).toRadixString(16)}';
      // Only an order that includes the offered seats draws on the offer
      final offer = _offer;
      final fromOffer = offer != null && _selected.any(_reserved.contains);
      final o = await ref.read(apiProvider).createOrder(event.id, const {}, idempotencyKey: key, seats: keys, promoCode: code, waitlistEntryId: fromOffer ? offer.id : null);
      _idempotencyKey = _newSalt();
      if (fromOffer) _boughtFromOffer = true;
      ref.invalidate(waitlistProvider);
      ref.invalidate(eventProvider(event.id));
      ref.invalidate(pendingOrdersProvider);
      if (!mounted) return;
      if (o.isPaid) {
        ref.invalidate(myTicketsProvider);
        _snack(t.registered);
        context.go('/tickets');
      } else {
        setState(() => _selected = []);
        _seatsChanged();
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
        _seatsChanged();
        await _load(force: true); // the map may look unchanged to us, but those seats are gone
      } else if (e.reasonCode == 'OFFER_CLOSED') {
        // The offer ran out or was used meanwhile: explained in our own text; the offer list is refreshed
        setState(() => _error = waitlistErrorText(t, e));
        ref.invalidate(waitlistProvider);
      } else if (e.reasonCode != null) {
        // The promo code was rejected at order time (e.g. used up meanwhile): it is no longer applied, and its
        // reason shows under the code in our own (Myanmar) text. Continue now buys at full price.
        _promoDebounce?.cancel();
        _promoSeq++;
        setState(() {
          _promo = PromoCheck(valid: false, reasonCode: e.reasonCode, discountMmk: 0, totalMmk: _total);
          _promoError = null;
          _promoChecking = false;
        });
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
    ref.listen(waitlistProvider, (_, __) {
      final cur = _data;
      if (cur != null && widget.offerEntryId != null) _apply(cur, force: true); // the offer arrived, changed or ended
    });
    ref.listen(eventProvider(widget.idOrSlug), (_, next) {
      if (next.value != null && _promoCode.isNotEmpty && _selected.isNotEmpty && _promo == null && _promoError == null) _checkPromo();
    });

    Widget body;
    if (d == null || l == null) {
      body = _loadFailed
          ? MessageView(icon: Icons.error_outline, message: t.loadError, actionLabel: t.retry, onAction: () {
              setState(() => _loadFailed = false);
              _load();
            })
          : const Center(child: CircularProgressIndicator());
    } else {
      final offer = _offer;
      body = Column(children: [
        if (offer != null) OfferCountdown(entry: offer, onExpired: () => ref.invalidate(waitlistProvider)),
        _Legend(types: d.types, lang: lang, reserved: _reserved.isNotEmpty),
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
                          reserved: _reserved,
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
          // While a code's check is pending no discount is shown (not even the group one): the total is the plain total
          view: _codePending
              ? DiscountView(source: null, discountMmk: 0, totalMmk: _total, promoLost: false, nextTier: null)
              : resolveDiscount(
                  tiers: event?.groupDiscounts ?? const [],
                  paidQty: _paidSeats,
                  paidSubtotalMmk: _total,
                  totalMmk: _total,
                  promo: _promo,
                ),
          checkingCode: _codePending && _promoError == null,
          notice: _notice,
          error: _error,
          busy: _busy,
          canContinue: event != null && !_codePending,
          onRemove: (i) {
            setState(() => _selected = [for (final s in _selected) if (s != i) s]);
            _seatsChanged();
          },
          promo: _promo,
          promoChecking: _promoChecking,
          promoError: _promoError,
          promoOpen: _promoOpen,
          promoController: _promoCtl,
          onOpenPromo: () => setState(() => _promoOpen = true),
          onApplyPromo: _applyPromo,
          onRemovePromo: _removePromo,
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
  const _Legend({required this.types, required this.lang, this.reserved = false});
  final List<SeatTypeInfo> types;
  final String lang;

  /// A waitlist offer holds seats for the buyer: add "Reserved for you".
  final bool reserved;

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
    return Container(
      height: 44,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final ty in types)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: dot(parseHexColor(ty.color) ?? Colors.deepPurple, [
                '${ty.label(lang)} · ${t.mmk(formatAmount(ty.priceMmk, lang))}',
                if (priceRiseText(t, lang, ty.priceMmk, ty.nextPrice) != null) priceRiseText(t, lang, ty.priceMmk, ty.nextPrice)!,
              ].join(' · '))),
            ),
          if (reserved) Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: dot(const Color(0xFFE0A800), t.reservedForYou, icon: Icons.star))),
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
    required this.view,
    required this.checkingCode,
    required this.notice,
    required this.error,
    required this.busy,
    required this.canContinue,
    required this.onRemove,
    required this.promo,
    required this.promoChecking,
    required this.promoError,
    required this.promoOpen,
    required this.promoController,
    required this.onOpenPromo,
    required this.onApplyPromo,
    required this.onRemovePromo,
    required this.onBest,
    required this.onContinue,
  });
  final SeatLayout layout;
  final List<int> selected;
  final String lang;
  final int totalMmk;
  final DiscountView view;
  final bool checkingCode;
  final String? notice;
  final String? error;
  final bool busy;
  final bool canContinue;
  final void Function(int seatIndex) onRemove;
  final PromoCheck? promo; // null while unchecked or being re-checked
  final bool promoChecking;
  final String? promoError;
  final bool promoOpen;
  final TextEditingController promoController;
  final VoidCallback onOpenPromo;
  final VoidCallback onApplyPromo;
  final VoidCallback onRemovePromo;
  final VoidCallback onBest;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final List<Widget> top = [
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
                      backgroundColor: theme.colorScheme.primaryContainer,
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                      deleteIconColor: theme.colorScheme.onPrimaryContainer,
                      onDeleted: () => onRemove(i),
                    ),
                ]),
              ),
            ),
          if (!promoOpen)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(key: const Key('addPromo'), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero), onPressed: onOpenPromo, child: Text(t.addPromoCode)),
            )
          else ...[
            if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) ...[
              // Large text: the code field gets its own line and the buttons wrap below it
              TextField(
                key: const Key('promoField'),
                controller: promoController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: t.promoCode, isDense: true),
                onSubmitted: (_) => onApplyPromo(),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton(key: const Key('promoApply'), style: E360Buttons.outline, onPressed: promoChecking ? null : onApplyPromo, child: Text(t.apply)),
                TextButton(key: const Key('promoRemove'), onPressed: onRemovePromo, child: Text(t.removePromo)),
              ]),
            ] else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    key: const Key('promoField'),
                    controller: promoController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: t.promoCode, isDense: true),
                    onSubmitted: (_) => onApplyPromo(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(key: const Key('promoApply'), style: E360Buttons.outline, onPressed: promoChecking ? null : onApplyPromo, child: Text(t.apply)),
                const SizedBox(width: 4),
                TextButton(key: const Key('promoRemove'), onPressed: onRemovePromo, child: Text(t.removePromo)),
              ]),
            if (promoError != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(promoError!, key: const Key('promoError'), style: TextStyle(color: theme.colorScheme.error))),
            if (promo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: promo!.valid
                    ? (promo!.promoApplied
                        ? Text(t.promoApplied(t.mmk(formatAmount(promo!.discountMmk, lang))), key: const Key('promoResult'), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))
                        : const SizedBox.shrink()) // lost to the group discount: DiscountLines says so
                    : Text(promoReasonText(t, promo!.reasonCode), key: const Key('promoResult'), style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
          if (checkingCode) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.promoChecking, key: const Key('promoCheckingNote'), style: theme.textTheme.bodySmall)),
          if (selected.isNotEmpty && !checkingCode) DiscountLines(view: view, lang: lang),
          const SizedBox(height: 6),
          TotalRow(
            label: Text('${t.seatsChosen(selected.length)} · ${t.total}', style: theme.textTheme.bodyMedium),
            original: view.discountMmk > 0 ? t.mmk(formatAmount(totalMmk, lang)) : null,
            total: t.mmk(formatAmount(view.totalMmk, lang)),
            totalKey: const Key('seatTotal'),
          ),
          const SizedBox(height: 8),
    ];
    final Widget actions = Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('bestAvailable'),
              style: E360Buttons.outline.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52))),
              onPressed: busy ? null : onBest,
              child: Text(t.bestAvailable),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const Key('seatContinue'),
              style: E360Buttons.gold,
              onPressed: busy || selected.isEmpty || !canContinue ? null : onContinue,
              child: busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.continueLabel),
            ),
          ),
        ]);
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: large
              // Large text: only the part above the buttons scrolls (inside half the screen); the buttons stay pinned
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: top))),
                    actions,
                  ]),
                )
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [...top, actions]),
        ),
      ),
    );
  }
}

/// "Best available": choose a ticket type and how many; the server picks adjacent seats. Pops with the seat keys.
class _BestSheet extends ConsumerStatefulWidget {
  const _BestSheet({required this.idOrSlug, required this.types, required this.event, required this.available, this.offerEntryId});
  final String idOrSlug;
  final String? offerEntryId; // the buyer's live offer: its seats count as free
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
      final seats = await ref.read(apiProvider).bestSeats(widget.idOrSlug, widget.types[_type].id, min(_qty, _max), waitlistEntryId: widget.offerEntryId);
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
          StepperButton(key: const Key('bestMinus'), icon: Icons.remove, semanticLabel: t.fewerTickets(widget.types[_type].label(lang)), onPressed: qty > 1 ? () => setState(() => _qty = qty - 1) : null),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$qty', key: const Key('bestQty'), style: theme.textTheme.titleLarge)),
          StepperButton(key: const Key('bestPlus'), icon: Icons.add, semanticLabel: t.moreTickets(widget.types[_type].label(lang)), onPressed: qty < _max ? () => setState(() => _qty = qty + 1) : null),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('bestError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('bestFind'),
          style: E360Buttons.gold,
          onPressed: _busy || widget.available.every((n) => n == 0) ? null : _find,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.findSeats),
        ),
      ]),
    );
  }
}
