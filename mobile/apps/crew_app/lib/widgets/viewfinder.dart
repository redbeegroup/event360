import 'dart:math' as math;

import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

/// Aiming frame for the QR camera: the picture outside the square is dimmed and four gold
/// corner brackets mark where to hold the ticket.
class ViewfinderOverlay extends StatelessWidget {
  const ViewfinderOverlay({super.key, this.scrim = true});

  /// Dim everything outside the frame (off on the plain "camera unavailable" backdrop).
  final bool scrim;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(builder: (_, c) {
          final side = math.min(240.0, math.min(c.maxWidth, c.maxHeight) * 0.7);
          return CustomPaint(
            key: const Key('viewfinder'),
            size: Size(c.maxWidth, c.maxHeight),
            painter: _ViewfinderPainter(side: side, scrim: scrim),
          );
        }),
      );
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.side, required this.scrim});
  final double side;
  final bool scrim;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side), const Radius.circular(24));
    if (scrim) {
      final hole = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(box));
      canvas.drawPath(hole, Paint()..color = const Color(0x73000000));
    }
    // Corner brackets: an L at each corner, following the rounded corner.
    const arm = 34.0;
    const r = 24.0;
    final p = Paint()
      ..color = E360Colors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final l = box.left, t = box.top, rt = box.right, b = box.bottom;
    final path = Path()
      ..moveTo(l, t + arm)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
      ..lineTo(l + arm, t)
      ..moveTo(rt - arm, t)
      ..lineTo(rt - r, t)
      ..arcToPoint(Offset(rt, t + r), radius: const Radius.circular(r))
      ..lineTo(rt, t + arm)
      ..moveTo(rt, b - arm)
      ..lineTo(rt, b - r)
      ..arcToPoint(Offset(rt - r, b), radius: const Radius.circular(r))
      ..lineTo(rt - arm, b)
      ..moveTo(l + arm, b)
      ..lineTo(l + r, b)
      ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
      ..lineTo(l, b - arm);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.side != side || old.scrim != scrim;
}
