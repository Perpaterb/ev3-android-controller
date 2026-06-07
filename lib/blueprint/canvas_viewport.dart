import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The camera over the infinite blueprint canvas: where we're looking and
/// how far we're zoomed in.
///
/// Screen and canvas coordinates relate by `screen = canvas * scale + translation`.
class CanvasViewport extends ChangeNotifier {
  CanvasViewport({Offset translation = Offset.zero, double scale = 1.0})
      // ignore: prefer_initializing_formals — the fields are private.
      : _translation = translation,
        _scale = scale.clamp(minScale, maxScale);

  factory CanvasViewport.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CanvasViewport();
    return CanvasViewport(
      translation: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      scale: (json['scale'] as num).toDouble(),
    );
  }

  static const double minScale = 0.25;
  static const double maxScale = 3.0;

  Offset _translation;
  double _scale;

  Offset get translation => _translation;
  double get scale => _scale;

  Offset toCanvas(Offset screen) => (screen - _translation) / _scale;
  Offset toScreen(Offset canvas) => canvas * _scale + _translation;

  void panBy(Offset screenDelta) {
    _translation += screenDelta;
    notifyListeners();
  }

  /// Zooms by [factor], keeping the canvas point under [screenFocal] fixed
  /// on screen (scroll-wheel zoom at the cursor).
  void zoomAt(Offset screenFocal, double factor) {
    follow(
      screenFocal: screenFocal,
      canvasFocal: toCanvas(screenFocal),
      scale: _scale * factor,
    );
  }

  /// Pins [canvasFocal] under [screenFocal] at [scale] (clamped). This is the
  /// core of pinch gestures: as the fingers' focal point moves and spreads,
  /// the canvas point grabbed at gesture start stays under it.
  void follow({
    required Offset screenFocal,
    required Offset canvasFocal,
    required double scale,
  }) {
    _scale = scale.clamp(minScale, maxScale);
    _translation = screenFocal - canvasFocal * _scale;
    notifyListeners();
  }

  Map<String, dynamic> toJson() =>
      {'x': _translation.dx, 'y': _translation.dy, 'scale': _scale};
}
