import 'package:ev3_controller/blueprint/model/controller_layout.dart';
import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:ev3_controller/models/project.dart';
import 'package:ev3_controller/run/run_mode.dart';
import 'package:ev3_controller/services/ev3_brick.dart';
import 'package:ev3_controller/services/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_project_storage.dart';

void main() {
  late Project project;
  late ControllerLayout layout;
  late MockEv3Brick brick;

  setUp(() async {
    final store = ProjectStore(InMemoryProjectStorage());
    await store.load();
    project = await store.create('Test Bot');
    layout = ControllerLayout();
    brick = MockEv3Brick();
  });

  ControllerControl addControl(ControlKind kind, String name,
          {Offset position = const Offset(0.5, 0.5), String? tabId}) =>
      layout.addControl(
        tabId: tabId ?? layout.tabs.first.id,
        kind: kind,
        name: name,
        position: position,
      );

  /// Persists the layout (and optional graph wiring) into the project.
  void seed({void Function(BlueprintGraph graph)? wireUp}) {
    project.controller.addAll(layout.toJson());
    final graph = BlueprintGraph.fromJson(
      {},
      dynamicDefs: {kControllerDefId: layout.buildNodeDef()},
    );
    graph.ensureControllerNode(layout.buildNodeDef(), Offset.zero);
    wireUp?.call(graph);
    project.graph.addAll(graph.toJson());
  }

  Future<void> pumpRunMode(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RunMode(project: project, brick: brick)),
    ));
  }

  testWidgets('renders the designed controls and the practice chip',
      (tester) async {
    addControl(ControlKind.button, 'Go');
    addControl(ControlKind.slider, 'Speed', position: const Offset(0.5, 0.8));
    seed();
    await pumpRunMode(tester);

    expect(find.text('Go'), findsOneWidget);
    expect(find.textContaining('Speed'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining('Practice mode'), findsOneWidget);
  });

  testWidgets('press and release a button drives the brick', (tester) async {
    final go = addControl(ControlKind.button, 'Go');
    seed(wireUp: (graph) {
      final motor = graph.addNode(nodeDefById('motor.run')!, Offset.zero);
      final stop = graph.addNode(nodeDefById('motor.stop')!, Offset.zero);
      graph.connect(
        PinRef(kControllerNodeId, '${go.id}.pressed', isOutput: true),
        PinRef(motor.id, 'run', isOutput: false),
      );
      graph.connect(
        PinRef(kControllerNodeId, '${go.id}.released', isOutput: true),
        PinRef(stop.id, 'stop', isOutput: false),
      );
    });
    await pumpRunMode(tester);

    final gesture =
        await tester.press(find.byKey(Key('run-control-${go.id}')));
    await tester.pump();
    expect(brick.log, ['Motor A: run at 100% forward']);

    await gesture.up();
    await tester.pump();
    expect(brick.log.last, 'Motor A: stop');
  });

  testWidgets('a toggle wired to a light turns it on', (tester) async {
    final power = addControl(ControlKind.toggle, 'Power');
    final lamp =
        addControl(ControlKind.light, 'Lamp', position: const Offset(0.7, 0.5));
    seed(wireUp: (graph) {
      graph.connect(
        PinRef(kControllerNodeId, '${power.id}.state', isOutput: true),
        PinRef(kControllerNodeId, '${lamp.id}.on', isOutput: false),
      );
    });
    await pumpRunMode(tester);

    Color lightColor() => ((tester
            .widget<AnimatedContainer>(find.byKey(Key('run-light-${lamp.id}')))
            .decoration) as BoxDecoration)
        .color!;

    expect(lightColor(), isNot(Colors.amber));
    await tester.tap(find.byKey(Key('run-control-${power.id}')));
    await tester.pump();
    expect(lightColor(), Colors.amber);
  });

  testWidgets('a display shows the slider value live', (tester) async {
    final speed = addControl(ControlKind.slider, 'Speed',
        position: const Offset(0.5, 0.3));
    final readout = addControl(ControlKind.display, 'Readout',
        position: const Offset(0.5, 0.7));
    seed(wireUp: (graph) {
      graph.connect(
        PinRef(kControllerNodeId, '${speed.id}.value', isOutput: true),
        PinRef(kControllerNodeId, '${readout.id}.value', isOutput: false),
      );
    });
    await pumpRunMode(tester);

    String shown() => (tester
            .widget<Text>(find.byKey(Key('run-display-${readout.id}'))))
        .data!;

    expect(shown(), '0'); // slider starts at its minimum
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump();
    expect(int.parse(shown()), greaterThan(0));
  });

  testWidgets('an unwired display shows --', (tester) async {
    addControl(ControlKind.display, 'Readout');
    seed();
    await pumpRunMode(tester);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('a scaled-up control renders bigger on screen', (tester) async {
    final go = addControl(ControlKind.button, 'Go',
        position: const Offset(0.3, 0.5));
    final big = addControl(ControlKind.button, 'Big',
        position: const Offset(0.7, 0.5));
    layout.setControlScale(big.id, 2.0);
    seed();
    await pumpRunMode(tester);

    final normal = tester.getRect(find.byKey(Key('run-control-${go.id}')));
    final scaled = tester.getRect(find.byKey(Key('run-control-${big.id}')));
    expect(scaled.width, closeTo(normal.width * 2, 0.5));
    expect(scaled.height, closeTo(normal.height * 2, 0.5));
  });

  testWidgets('the stage matches the tab orientation', (tester) async {
    addControl(ControlKind.button, 'Go');
    layout.setTabOrientation(layout.tabs.single.id, landscape: false);
    seed();
    await pumpRunMode(tester);

    // The portrait stage is taller than wide, and the control still works.
    final stage = tester.getSize(find.byKey(const Key('run-stage')));
    expect(find.text('Go'), findsOneWidget);
    expect(stage.height, greaterThan(stage.width));
    expect(stage.width / stage.height, closeTo(9 / 16, 0.01));
  });

  testWidgets('tabs switch between control pages', (tester) async {
    addControl(ControlKind.button, 'Drive');
    final arm = layout.addTab('Arm');
    addControl(ControlKind.button, 'Grab', tabId: arm.id);
    seed();
    await pumpRunMode(tester);

    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('Grab'), findsNothing);

    await tester.tap(find.byKey(Key('run-tab-${arm.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Grab'), findsOneWidget);
    expect(find.text('Drive'), findsNothing);
  });

  testWidgets('the command log panel shows brick commands', (tester) async {
    final go = addControl(ControlKind.button, 'Go');
    seed(wireUp: (graph) {
      final motor = graph.addNode(nodeDefById('motor.run')!, Offset.zero);
      graph.connect(
        PinRef(kControllerNodeId, '${go.id}.pressed', isOutput: true),
        PinRef(motor.id, 'run', isOutput: false),
      );
    });
    await pumpRunMode(tester);

    await tester.tap(find.byKey(const Key('toggle-log')));
    await tester.pump();
    expect(find.textContaining('No commands yet'), findsOneWidget);

    final gesture =
        await tester.press(find.byKey(Key('run-control-${go.id}')));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('Motor A: run at 100% forward'), findsOneWidget);
  });

  testWidgets('leaving Run mode stops all motors', (tester) async {
    seed();
    await pumpRunMode(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(brick.log.last, 'All motors: stop');
  });
}
