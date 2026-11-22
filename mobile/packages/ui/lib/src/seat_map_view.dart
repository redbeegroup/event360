/// Pan / zoom / tap seat map viewer shared by the buyer and organizer apps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'seat_layout.dart';
import 'seat_map_painter.dart';

/// Seats are tappable from this zoom (screen px per layout unit); below it a tap on a section zooms into it.
const double kSeatTapScale = 1.6;

// Same as the SeatMapPainter constructor defaults.
const Color _defaultStage = Color(0xFFCFCBE0);
const Color _defaultTaken = Color(0xFFBDBDBD);

/// Lets the owner of a [SeatMapView] move its camera and read the zoom.
class SeatMapViewController {
  _SeatMapViewState? _state;

  /// Animates to [layoutRect] (layout units), never below the zoom where seats are tappable; when the rect is
  /// too big for that (a large section) it centres on [focus] instead. No-op before the first layout.
  /// Must not be called during build.
  void zoomTo(Rect layoutRect, {Offset? focus}) => _state?._zoomTo(layoutRect, focus: focus);

  /// Jumps back to the whole map fitted in the viewport. Must not be called during build.
  void fit() => _state?._fitAll();

  /// Live zoom, screen px per layout unit (0 while not attached).
  double get scale => _state?._zoom ?? 0;
}

/// Draws a [SeatLayout] in an `InteractiveViewer`. First layout fits the whole map; a tap below
/// [kSeatTapScale] zooms into the tapped section, a tap at or above it on a seat calls [onSeatTap].
class SeatMapView extends StatefulWidget {
  const SeatMapView({
    super.key,
    required this.layout,
    required this.states,
    required this.colors,
    this.selected = const {},
    this.reserved = const {},
    this.lang = 'en',
    this.controller,
    this.onSeatTap,
    this.onScaleChanged,
    this.overlayBuilder,
    this.highlightSection,
    this.ink,
    this.stageColor,
    this.takenColor,
  });

  final SeatLayout layout;
  final List<SeatState> states;
  final List<Color?> colors;
  final Set<int> selected;
  final Set<int> reserved;
  final String lang;
  final SeatMapViewController? controller;

  /// Index in [SeatLayout.seats]; only called when zoomed in to [kSeatTapScale] or more.
  final void Function(int seatIndex)? onSeatTap;

  /// The zoom changed (screen px per layout unit).
  final void Function(double scale)? onScaleChanged;

  /// Drawn over the map (a direct child of the view's Stack, so it may return a `Positioned`) and rebuilt with
  /// the current zoom, already correct on the first frame. Taps pass through only if it ignores pointers.
  final Widget Function(BuildContext context, double scale)? overlayBuilder;
  final String? highlightSection;

  /// Defaults: the theme's onSurface, and the painter's own stage / taken colours.
  final Color? ink;
  final Color? stageColor;
  final Color? takenColor;

  @override
  State<SeatMapView> createState() => _SeatMapViewState();
}

class _SeatMapViewState extends State<SeatMapView> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Size _viewport = Size.zero;
  double _fit = 0.3;
  double _scale = 0.3;
  bool _placed = false;
  Animation<Matrix4>? _zoomAnim;
  VoidCallback? _zoomTick;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _transform.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(SeatMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller!._state = null;
    if (_zoomTick != null) _zoomAnim?.removeListener(_zoomTick!);
    _anim.dispose();
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  /// Screen px per layout unit. (Not getMaxScaleOnAxis: it includes the z axis, which stays 1.)
  double get _zoom => _transform.value.entry(0, 0);

  void _onTransform() {
    final s = _zoom;
    if ((s - _scale).abs() > 0.02 && mounted) {
      setState(() => _scale = s);
      widget.onScaleChanged?.call(s);
    }
  }

  void _place(Size viewport) {
    final l = widget.layout;
    final fit = math.min(viewport.width / l.width, viewport.height / l.height);
    if (_placed && viewport == _viewport) return;
    _viewport = viewport;
    _fit = fit;
    if (!_placed) {
      _placed = true;
      _scale = fit; // before the controller notifies, so the listener doesn't setState during build
      _transform.value = _fitMatrix();
    }
  }

  Matrix4 _fitMatrix() {
    final l = widget.layout;
    final dx = (_viewport.width - l.width * _fit) / 2;
    final dy = (_viewport.height - l.height * _fit) / 2;
    return Matrix4.diagonal3Values(_fit, _fit, 1)..setTranslationRaw(dx, dy, 0);
  }

  void _stopZoom() {
    if (_zoomTick != null) _zoomAnim?.removeListener(_zoomTick!);
    _zoomTick = null;
    _anim.stop();
  }

  void _fitAll() {
    if (_viewport == Size.zero) return;
    _stopZoom();
    _transform.value = _fitMatrix();
  }

  void _zoomTo(Rect r, {Offset? focus}) {
    if (_viewport == Size.zero) return;
    const pad = 24.0;
    final fitScale = math.min(_viewport.width / (r.width + pad * 2), _viewport.height / (r.height + pad * 2));
    const minTappable = kSeatTapScale + 0.2;
    final s = fitScale.clamp(minTappable, 6.0);
    var c = r.center;
    if (fitScale < minTappable && focus != null) {
      // keep the whole viewport inside the section where possible
      final halfW = _viewport.width / s / 2, halfH = _viewport.height / s / 2;
      c = Offset(focus.dx.clamp(r.left + math.min(halfW, r.width / 2), r.right - math.min(halfW, r.width / 2)), focus.dy.clamp(r.top + math.min(halfH, r.height / 2), r.bottom - math.min(halfH, r.height / 2)));
    }
    final end = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(_viewport.width / 2 - c.dx * s, _viewport.height / 2 - c.dy * s, 0);
    final tween = Matrix4Tween(begin: _transform.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    // One listener at a time: a new zoom replaces the running one
    if (_zoomTick != null) _zoomAnim?.removeListener(_zoomTick!);
    _zoomAnim = tween;
    _zoomTick = () => _transform.value = tween.value;
    tween.addListener(_zoomTick!);
    _anim.forward(from: 0);
  }

  void _onTap(Offset p) {
    final l = widget.layout;
    if (_zoom >= kSeatTapScale) {
      final seat = l.seatAt(p);
      if (seat != null) widget.onSeatTap?.call(seat.index);
    } else {
      final sec = l.sectionAt(p);
      if (sec != null) _zoomTo(sec.bounds, focus: p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layout;
    return LayoutBuilder(builder: (context, c) {
      _place(Size(c.maxWidth, c.maxHeight));
      final viewer = InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        minScale: _fit,
        maxScale: math.max(6, _fit),
        boundaryMargin: const EdgeInsets.all(120),
        child: GestureDetector(
          key: const Key('seatMap'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTap(details.localPosition),
          child: CustomPaint(
            size: Size(l.width, l.height),
            painter: SeatMapPainter(
              layout: l,
              states: widget.states,
              colors: widget.colors,
              selected: widget.selected,
              reserved: widget.reserved,
              lang: widget.lang,
              scale: _scale,
              ink: widget.ink ?? Theme.of(context).colorScheme.onSurface,
              stageColor: widget.stageColor ?? _defaultStage,
              takenColor: widget.takenColor ?? _defaultTaken,
              highlightSection: widget.highlightSection,
            ),
          ),
        ),
      );
      final overlay = widget.overlayBuilder;
      if (overlay == null) return viewer;
      return Stack(fit: StackFit.expand, children: [viewer, overlay(context, _scale)]);
    });
  }
}
