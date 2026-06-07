import 'package:flutter/material.dart';

import '../canvas_viewport.dart';
import '../model/graph.dart';
import '../node_geometry.dart';

/// Paints every wire as a UE5-style horizontal-tangent bezier in its pin
/// type's colour. Painted under the nodes (the endpoints hide beneath the
/// node bodies). While wiring mode is active everything fades back, matching
/// the greyed-out nodes.
class WirePainter extends CustomPainter {
  WirePainter({
    required this.graph,
    required this.viewport,
    this.faded = false,
  }) : super(repaint: Listenable.merge([graph, viewport]));

  final BlueprintGraph graph;
  final CanvasViewport viewport;
  final bool faded;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * viewport.scale
      ..strokeCap = StrokeCap.round;

    for (final wire in graph.wires) {
      final fromNode = graph.node(wire.fromNode);
      final toNode = graph.node(wire.toNode);
      final type = graph.pinType(wire.from);
      if (fromNode == null || toNode == null || type == null) continue;

      final start = viewport.toScreen(fromNode.position +
          nodePinOffset(fromNode, wire.fromPin, isOutput: true));
      final end = viewport.toScreen(toNode.position +
          nodePinOffset(toNode, wire.toPin, isOutput: false));

      // Horizontal tangents out of the output and into the input.
      final reach = ((end.dx - start.dx).abs() / 2)
          .clamp(40.0 * viewport.scale, 150.0 * viewport.scale);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + reach, start.dy, end.dx - reach, end.dy,
            end.dx, end.dy);

      paint.color = type.color.withValues(alpha: faded ? 0.15 : 0.9);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(WirePainter oldDelegate) =>
      oldDelegate.graph != graph ||
      oldDelegate.viewport != viewport ||
      oldDelegate.faded != faded;
}
