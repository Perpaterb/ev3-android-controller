import 'package:ev3_controller/blueprint/canvas_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen and canvas coordinates round-trip', () {
    final viewport =
        CanvasViewport(translation: const Offset(40, -10), scale: 1.5);
    const screen = Offset(123, 456);
    expect(viewport.toScreen(viewport.toCanvas(screen)), screen);
  });

  test('panBy shifts the view', () {
    final viewport = CanvasViewport();
    viewport.panBy(const Offset(30, 20));
    expect(viewport.translation, const Offset(30, 20));
    expect(viewport.scale, 1.0);
  });

  test('zoomAt keeps the point under the cursor fixed', () {
    final viewport =
        CanvasViewport(translation: const Offset(50, 50), scale: 0.8);
    const cursor = Offset(200, 150);
    final before = viewport.toCanvas(cursor);
    viewport.zoomAt(cursor, 1.5);
    expect(viewport.scale, closeTo(1.2, 1e-9));
    final after = viewport.toCanvas(cursor);
    expect(after.dx, closeTo(before.dx, 1e-6));
    expect(after.dy, closeTo(before.dy, 1e-6));
  });

  test('scale clamps to limits', () {
    final viewport = CanvasViewport();
    viewport.zoomAt(Offset.zero, 1000);
    expect(viewport.scale, CanvasViewport.maxScale);
    viewport.zoomAt(Offset.zero, 1e-6);
    expect(viewport.scale, CanvasViewport.minScale);
  });

  test('constructor clamps a bad saved scale', () {
    expect(CanvasViewport(scale: 99).scale, CanvasViewport.maxScale);
  });

  test('follow pins the canvas focal under the screen focal', () {
    final viewport = CanvasViewport();
    const canvasFocal = Offset(100, 100);
    const screenFocal = Offset(300, 200);
    viewport.follow(
        screenFocal: screenFocal, canvasFocal: canvasFocal, scale: 2);
    expect(viewport.toScreen(canvasFocal), screenFocal);
    expect(viewport.scale, 2.0);
  });

  test('JSON round-trips', () {
    final viewport =
        CanvasViewport(translation: const Offset(-12.5, 88), scale: 1.75);
    final copy = CanvasViewport.fromJson(viewport.toJson());
    expect(copy.translation, viewport.translation);
    expect(copy.scale, viewport.scale);
  });

  test('fromJson(null) gives the default view', () {
    final viewport = CanvasViewport.fromJson(null);
    expect(viewport.translation, Offset.zero);
    expect(viewport.scale, 1.0);
  });
}
