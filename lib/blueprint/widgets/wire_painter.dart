import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas_viewport.dart';
import '../model/graph.dart';
import '../model/pins.dart';
import '../node_geometry.dart';
import 'node_chrome.dart';

/// Paints every wire as a UE5-style horizontal-tangent bezier in its pin
/// type's colour. Painted under the nodes (the endpoints hide beneath the
/// node bodies). While wiring mode is active everything fades back — except
/// the wires of the [selected] pin, which glow.
class WirePainter extends CustomPainter {
  WirePainter({
    required this.graph,
    required this.viewport,
    this.faded = false,
    this.selected,
  }) : super(repaint: Listenable.merge([graph, viewport]));

  final BlueprintGraph graph;
  final CanvasViewport viewport;
  final bool faded;

  /// The pin currently picked for wiring; its wires stay bright and glow.
  final PinRef? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = PinDot.linkColor.withValues(alpha: 0.5)
      ..strokeWidth = 9 * viewport.scale
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (final wire in graph.wires) {
      final fromNode = graph.node(wire.fromNode);
      final toNode = graph.node(wire.toNode);
      final type = graph.pinType(wire.from);
      if (fromNode == null || toNode == null || type == null) continue;

      final start = viewport.toScreen(fromNode.position +
          nodePinOffset(fromNode, wire.fromPin, isOutput: true));
      final end = viewport.toScreen(toNode.position +
          nodePinOffset(toNode, wire.toPin, isOutput: false));

      // Horizontal tangents out of the output and into the input. A generous
      // minimum reach keeps the wire from hugging straight back behind the
      // node — it always bows out far enough to be seen.
      final reach = math
          .max(95.0 * viewport.scale, (end.dx - start.dx).abs() * 0.6)
          .clamp(95.0 * viewport.scale, 260.0 * viewport.scale);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + reach, start.dy, end.dx - reach, end.dy,
            end.dx, end.dy);

      final onSelected = selected != null &&
          (wire.from == selected || wire.to == selected);
      if (onSelected) canvas.drawPath(path, glowPaint); // orange halo

      paint
        ..strokeWidth = (onSelected ? 4.5 : 3) * viewport.scale
        ..color = type.color
            .withValues(alpha: faded && !onSelected ? 0.15 : 0.95);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(WirePainter oldDelegate) =>
      oldDelegate.graph != graph ||
      oldDelegate.viewport != viewport ||
      oldDelegate.faded != faded ||
      oldDelegate.selected != selected;
}
