import 'package:ev3_controller/blueprint/blueprint_canvas.dart';
import 'package:ev3_controller/blueprint/canvas_viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CanvasViewport viewport;

  Future<void> pumpCanvas(WidgetTester tester) async {
    viewport = CanvasViewport();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BlueprintCanvas(viewport: viewport)),
    ));
  }

  testWidgets('mouse scroll wheel zooms in at the cursor', (tester) async {
    await pumpCanvas(tester);
    final cursor = tester.getCenter(find.byType(BlueprintCanvas));
    final canvasUnderCursor = viewport.toCanvas(cursor);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(cursor);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();

    expect(viewport.scale, greaterThan(1.0));
    // The canvas point under the cursor must not move while zooming.
    final after = viewport.toCanvas(cursor);
    expect(after.dx, closeTo(canvasUnderCursor.dx, 1e-6));
    expect(after.dy, closeTo(canvasUnderCursor.dy, 1e-6));
  });

  testWidgets('mouse scroll down zooms out', (tester) async {
    await pumpCanvas(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(BlueprintCanvas)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pump();
    expect(viewport.scale, lessThan(1.0));
  });

  testWidgets('right-click drag pans the canvas', (tester) async {
    await pumpCanvas(tester);
    final start = tester.getCenter(find.byType(BlueprintCanvas));

    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(start);
    await gesture.moveBy(const Offset(30, 20));
    await gesture.up();
    await tester.pump();

    expect(viewport.translation.dx, closeTo(30, 1e-6));
    expect(viewport.translation.dy, closeTo(20, 1e-6));
    expect(viewport.scale, 1.0);
  });

  testWidgets('one-finger drag pans the canvas', (tester) async {
    await pumpCanvas(tester);
    await tester.drag(find.byType(BlueprintCanvas), const Offset(-50, 25));
    await tester.pump();
    expect(viewport.translation.dx, closeTo(-50, 1e-6));
    expect(viewport.translation.dy, closeTo(25, 1e-6));
  });

  testWidgets('pinch with two fingers zooms in around the midpoint',
      (tester) async {
    await pumpCanvas(tester);
    final centre = tester.getCenter(find.byType(BlueprintCanvas));
    final midpointCanvas = viewport.toCanvas(centre);

    final finger1 = await tester.createGesture();
    final finger2 = await tester.createGesture();
    await finger1.down(centre - const Offset(40, 0));
    await tester.pump();
    await finger2.down(centre + const Offset(40, 0));
    await tester.pump();
    await finger1.moveBy(const Offset(-40, 0));
    await finger2.moveBy(const Offset(40, 0));
    await tester.pump();
    await finger1.up();
    await finger2.up();
    await tester.pump();

    expect(viewport.scale, closeTo(2.0, 0.01)); // fingers twice as far apart
    // The test moves the fingers one after the other (a real pinch moves them
    // together), so the midpoint wobbles a few pixels — allow for that.
    final after = viewport.toCanvas(centre);
    expect(after.dx, closeTo(midpointCanvas.dx, 5));
    expect(after.dy, closeTo(midpointCanvas.dy, 5));
  });

  testWidgets('zoom is clamped at the limits', (tester) async {
    await pumpCanvas(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(BlueprintCanvas)));
    for (var i = 0; i < 50; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    }
    await tester.pump();
    expect(viewport.scale, CanvasViewport.maxScale);

    for (var i = 0; i < 50; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    }
    await tester.pump();
    expect(viewport.scale, CanvasViewport.minScale);
  });
}
