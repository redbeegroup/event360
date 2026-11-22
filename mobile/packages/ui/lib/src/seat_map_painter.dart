/// Paints a seat map (layout units, 1 unit = 1 logical pixel at scale 1). Used by the user, crew and organizer apps.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'seat_layout.dart';

/// Draws stage, sections and seats. The caller owns zoom/pan: put this in a child of an `InteractiveViewer`
/// sized [SeatLayout.width] x [SeatLayout.height], and use [SeatLayout.seatAt] / [SeatLayout.sectionAt] on the
/// tap position (already in layout units there) to hit-test.
class SeatMapPainter extends CustomPainter {
  SeatMapPainter({
    required this.layout,
    required this.states,
    required this.colors,
    this.selected = const {},
    this.reserved = const {},
    this.lang = 'en',
    this.scale = 1,
    this.ink = defaultInk,
    this.stageColor = defaultStageColor,
    this.takenColor = defaultTakenColor,
    this.highlightSection,
  });

  static const Color defaultInk = Color(0xFF3A3550);
  static const Color defaultStageColor = Color(0xFFCFCBE0);
  static const Color defaultTakenColor = Color(0xFFBDBDBD);

  final SeatLayout layout;

  /// One per seat, in [SeatLayout.seats] order.
  final List<SeatState> states;

  /// Fill colour per seat (its ticket type's colour); null for seats with no type.
  final List<Color?> colors;

  /// Seat indexes the buyer picked.
  final Set<int> selected;

  /// Seat indexes held for the buyer by a waitlist offer: drawn with a gold ring, selected or not.
  final Set<int> reserved;
  final String lang;

  /// Current zoom (screen px per layout unit); only used to keep labels readable at any zoom.
  final double scale;
  final Color ink;
  final Color stageColor;
  final Color takenColor;
  final String? highlightSection;

  /// Section titles stay about 12 px on screen, within a sane range in layout units.
  double get _labelSize => (12 / math.max(scale, 0.05)).clamp(14.0, 48.0);

  void _text(Canvas canvas, String text, Offset anchor, {double? size, FontWeight weight = FontWeight.w600, Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size ?? _labelSize, fontWeight: weight, color: color ?? ink, fontFamilyFallback: const ['packages/event360_ui/NotoSansMyanmar']),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, anchor - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stage = layout.stage;
    if (stage != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(stage.rect, const Radius.circular(6)), Paint()..color = stageColor);
      if (stage.label != null) _text(canvas, stage.label!, stage.rect.center, size: math.min(stage.rect.height * 0.5, _labelSize));
    }
    for (final s in layout.sections) {
      if (s.standing) {
        canvas.save();
        canvas.translate(s.x, s.y);
        canvas.rotate(s.rotation * math.pi / 180);
        final r = Rect.fromLTWH(0, 0, s.width, s.height);
        canvas.drawRect(r, Paint()..color = const Color(0xFFE8E4F5));
        final dash = Paint()
          ..color = const Color(0xFF8B86A3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(r, dash);
        _text(canvas, '${s.nameFor(lang)}${s.capacity != null ? ' (${s.capacity})' : ''}', r.center);
        canvas.restore();
      } else if (s.key == highlightSection) {
        canvas.drawRRect(RRect.fromRectAndRadius(s.bounds.inflate(6), const Radius.circular(10)), Paint()..color = ink.withValues(alpha: 0.08));
      }
    }

    final fill = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    for (final seat in layout.seats) {
      final i = seat.index;
      final st = i < states.length ? states[i] : SeatState.unavailable;
      final c = i < colors.length ? colors[i] : null;
      final p = seat.pos;
      if (st == SeatState.unavailable || (st == SeatState.available && c == null)) {
        ring.color = takenColor.withValues(alpha: 0.7);
        canvas.drawCircle(p, kSeatRadius - 2, ring);
        continue;
      }
      if (st == SeatState.taken || st == SeatState.held) {
        fill.color = takenColor;
        canvas.drawCircle(p, kSeatRadius - 1, fill);
        if (st == SeatState.held) {
          mark.color = Colors.white;
          canvas.drawLine(p + const Offset(-4, -4), p + const Offset(4, 4), mark);
        }
        continue;
      }
      fill.color = c!;
      canvas.drawCircle(p, kSeatRadius, fill);
      mark.color = Colors.white;
      if (seat.attrs.contains(SeatAttr.wheelchair)) canvas.drawCircle(p, 4, mark);
      if (seat.attrs.contains(SeatAttr.restrictedView)) canvas.drawLine(p + const Offset(-4, 4), p + const Offset(4, -4), mark);
      if (reserved.contains(i)) {
        ring
          ..color = const Color(0xFFE0A800)
          ..strokeWidth = 2.4;
        canvas.drawCircle(p, kSeatRadius + 4, ring);
        ring.strokeWidth = 1.2;
      }
      if (selected.contains(i)) {
        ring
          ..color = ink
          ..strokeWidth = 3;
        canvas.drawCircle(p, kSeatRadius + 1.5, ring);
        ring.strokeWidth = 1.2;
        mark.color = Colors.white;
        final check = Path()
          ..moveTo(p.dx - 4, p.dy)
          ..lineTo(p.dx - 1, p.dy + 3)
          ..lineTo(p.dx + 4, p.dy - 3);
        canvas.drawPath(check, mark..strokeWidth = 2);
        mark.strokeWidth = 1.6;
      }
    }

    for (final s in layout.sections) {
      if (s.standing) continue;
      _text(canvas, s.nameFor(lang), Offset(s.bounds.center.dx, s.bounds.top - _labelSize * 0.9));
    }
  }

  @override
  bool shouldRepaint(SeatMapPainter old) =>
      old.layout != layout ||
      !identical(old.states, states) ||
      !identical(old.colors, colors) ||
      old.selected.length != selected.length ||
      !old.selected.containsAll(selected) ||
      old.reserved.length != reserved.length ||
      !old.reserved.containsAll(reserved) ||
      old.lang != lang ||
      (old.scale - scale).abs() > 0.01 ||
      old.highlightSection != highlightSection ||
      old.ink != ink;
}
