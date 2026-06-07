import 'package:flutter/material.dart';

import 'canvas_viewport.dart';

/// Dark blueprint-style background grid: minor lines every 20 canvas units,
/// major lines every 100, brighter axes through the origin. Minor lines drop
/// out when zoomed far enough that they would clutter.
class GridPainter extends CustomPainter {
  GridPainter({required this.viewport}) : super(repaint: viewport);

  final CanvasViewport viewport;

  static const double minorSpacing = 20;
  static const int majorEvery = 5;

  static const Color backgroundColor = Color(0xFF21262D);
  static const Color _minorColor = Color(0xFF2A3038);
  static const Color _majorColor = Color(0xFF394250);
  static const Color _axisColor = Color(0xFF4A5666);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    if (minorSpacing * viewport.scale >= 8) {
      _drawLines(canvas, size, minorSpacing, Paint()..color = _minorColor);
    }
    _drawLines(canvas, size, minorSpacing * majorEvery,
        Paint()..color = _majorColor);

    // Origin axes, so there's always a landmark to find your way back to.
    final axisPaint = Paint()
      ..color = _axisColor
      ..strokeWidth = 2;
    final origin = viewport.toScreen(Offset.zero);
    if (origin.dx >= 0 && origin.dx <= size.width) {
      canvas.drawLine(
          Offset(origin.dx, 0), Offset(origin.dx, size.height), axisPaint);
    }
    if (origin.dy >= 0 && origin.dy <= size.height) {
      canvas.drawLine(
          Offset(0, origin.dy), Offset(size.width, origin.dy), axisPaint);
    }
  }

  void _drawLines(Canvas canvas, Size size, double spacing, Paint paint) {
    final topLeft = viewport.toCanvas(Offset.zero);
    final bottomRight = viewport.toCanvas(Offset(size.width, size.height));

    for (var i = (topLeft.dx / spacing).floor();
        i <= (bottomRight.dx / spacing).ceil();
        i++) {
      final x = viewport.toScreen(Offset(i * spacing, 0)).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = (topLeft.dy / spacing).floor();
        i <= (bottomRight.dy / spacing).ceil();
        i++) {
      final y = viewport.toScreen(Offset(0, i * spacing)).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) =>
      oldDelegate.viewport != viewport;
}
