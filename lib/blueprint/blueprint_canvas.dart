import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'canvas_viewport.dart';
import 'grid_painter.dart';

/// The pannable, zoomable blueprint surface.
///
/// Touch: one-finger drag on empty canvas pans, pinch zooms around the pinch
/// midpoint. Mouse: scroll wheel zooms centred on the cursor, right-click
/// drag pans (UE5 style). All of it stays live regardless of editor state,
/// so wiring mode can never strand the user somewhere they can't navigate
/// out of.
///
/// [children] are laid out in canvas coordinates under the viewport
/// transform — that's where nodes go.
class BlueprintCanvas extends StatefulWidget {
  const BlueprintCanvas(
      {super.key, required this.viewport, this.children = const []});

  final CanvasViewport viewport;
  final List<Widget> children;

  @override
  State<BlueprintCanvas> createState() => _BlueprintCanvasState();
}

class _BlueprintCanvasState extends State<BlueprintCanvas> {
  /// How much one scroll-wheel notch (~100 delta units) zooms.
  static const double _scrollZoomPerUnit = 0.0015;

  double _lastGestureScale = 1;
  bool _rightPanning = false;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton != 0) _rightPanning = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_rightPanning) widget.viewport.panBy(event.delta);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      widget.viewport.zoomAt(event.localPosition,
          math.exp(-event.scrollDelta.dy * _scrollZoomPerUnit));
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    // The recognizer restarts (details.scale resets to 1) whenever a finger
    // joins or leaves, so tracking incremental deltas — rather than anchoring
    // to the gesture's start — keeps focal-point jumps from reading as pans.
    _lastGestureScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_rightPanning) return;
    // Single-finger drags arrive here too (details.scale stays 1), so this
    // one handler covers touch pan, pinch zoom, and both at once.
    widget.viewport
      ..zoomAt(details.localFocalPoint, details.scale / _lastGestureScale)
      ..panBy(details.focalPointDelta);
    _lastGestureScale = details.scale;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _rightPanning = false,
      onPointerCancel: (_) => _rightPanning = false,
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: ClipRect(
          child: CustomPaint(
            painter: GridPainter(viewport: viewport),
            child: ListenableBuilder(
              listenable: viewport,
              builder: (context, _) => Transform.translate(
                offset: viewport.translation,
                child: Transform.scale(
                  scale: viewport.scale,
                  alignment: Alignment.topLeft,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
