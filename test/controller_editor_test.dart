import 'package:ev3_controller/blueprint/blueprint_editor.dart';
import 'package:ev3_controller/blueprint/model/controller_layout.dart';
import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:ev3_controller/models/project.dart';
import 'package:ev3_controller/services/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_project_storage.dart';

void main() {
  late ProjectStore store;
  late Project project;

  setUp(() async {
    store = ProjectStore(InMemoryProjectStorage());
    await store.load();
    project = await store.create('Test Bot');
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    // The controller node is big; give the editor a desktop-sized window.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlueprintEditor(store: store, project: project),
      ),
    ));
  }

  Future<Map<String, dynamic>> saved(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    return project.graph;
  }

  /// Seeds the project with a layout (and optionally graph extras) before
  /// the editor opens.
  ControllerControl seedButton(String name) {
    final layout = ControllerLayout();
    final control = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.button,
      name: name,
      position: const Offset(0.5, 0.5),
    );
    project.controller.addAll(layout.toJson());
    return control;
  }

  testWidgets('a new project shows the controller node', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Controller'), findsOneWidget);
    expect(find.byKey(const Key('controller-layout-area')), findsOneWidget);
    expect(find.textContaining('Hold here'), findsOneWidget);
  });

  testWidgets('long-press in the layout area adds a named control with pins',
      (tester) async {
    await pumpEditor(tester);
    await tester.longPressAt(
        tester.getCenter(find.byKey(const Key('controller-layout-area'))));
    await tester.pumpAndSettle();
    expect(find.text('Add a control'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-control-button')));
    await tester.pumpAndSettle();
    expect(find.text('Button 1'), findsOneWidget); // pre-filled default

    await tester.enterText(find.byType(TextField), 'Forward');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Control visual plus its pins on the node edge.
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Forward touched'), findsOneWidget);
    expect(find.text('Forward released'), findsOneWidget);
    expect(find.text('Forward down'), findsOneWidget);

    await saved(tester);
    final tabs = project.controller['tabs'] as List;
    expect((tabs.first as Map)['controls'], hasLength(1));
  });

  testWidgets('a controller pin wires to a motor node', (tester) async {
    final control = seedButton('Go');
    final graph = BlueprintGraph();
    final motor =
        graph.addNode(nodeDefById('motor.run')!, const Offset(320, -40));
    project.graph.addAll(graph.toJson());
    await pumpEditor(tester);

    await tester
        .tap(find.byKey(Key('pin-controller-${control.id}.pressed-out')));
    await tester.pump();
    expect(find.byKey(const Key('cancel-wiring')), findsOneWidget);

    await tester.tap(find.byKey(Key('pin-${motor.id}-run-in')));
    await tester.pump();

    final json = await saved(tester);
    final wires = json['wires'] as List;
    expect(wires, hasLength(1));
    expect(wires.single['fromNode'], kControllerNodeId);
    expect(wires.single['fromPin'], '${control.id}.pressed');
    expect(wires.single['toNode'], motor.id);
  });

  testWidgets('deleting a control removes its pins and wires',
      (tester) async {
    final control = seedButton('Go');
    final layout = ControllerLayout.fromJson(project.controller);
    final graph = BlueprintGraph.fromJson(
      {},
      dynamicDefs: {kControllerDefId: layout.buildNodeDef()},
    );
    graph.ensureControllerNode(layout.buildNodeDef(), const Offset(-230, -150));
    final motor =
        graph.addNode(nodeDefById('motor.run')!, const Offset(320, -40));
    graph.connect(
      PinRef(kControllerNodeId, '${control.id}.pressed', isOutput: true),
      PinRef(motor.id, 'run', isOutput: false),
    );
    project.graph.addAll(graph.toJson());
    await pumpEditor(tester);

    await tester.tap(find.byKey(Key('control-${control.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('control-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete')); // confirm dialog
    await tester.pumpAndSettle();

    expect(find.text('Go touched'), findsNothing);
    final json = await saved(tester);
    expect(json['wires'], isEmpty);
    expect(project.controller['tabs'], isNotEmpty);
    expect(
        ((project.controller['tabs'] as List).first as Map)['controls'],
        isEmpty);
  });

  testWidgets(
      'wiring an int output into a string display auto-inserts Int → String',
      (tester) async {
    // A display control (string input) on the controller…
    final layout = ControllerLayout();
    final readout = layout.addControl(
      tabId: layout.tabs.single.id,
      kind: ControlKind.display,
      name: 'Readout',
      position: const Offset(0.5, 0.5),
    );
    project.controller.addAll(layout.toJson());
    // …and an Integer node off to the left.
    final graph = BlueprintGraph();
    final number =
        graph.addNode(nodeDefById('value.int')!, const Offset(-760, -40));
    project.graph.addAll(graph.toJson());
    await pumpEditor(tester);

    await tester.tap(find.byKey(Key('pin-${number.id}-value-out')));
    await tester.pump();
    // The string pin glows as connectable despite the type mismatch.
    await tester
        .tap(find.byKey(Key('pin-controller-${readout.id}.value-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cancel-wiring')), findsNothing);
    final json = await saved(tester);
    final wires = json['wires'] as List;
    expect(wires, hasLength(2));
    final nodes = (json['nodes'] as List).cast<Map>();
    final converter =
        nodes.singleWhere((n) => n['def'] == 'text.fromInt');
    // int → converter → display, joined through the new node.
    expect(
      wires.any((w) =>
          w['fromNode'] == number.id && w['toNode'] == converter['id']),
      isTrue,
    );
    expect(
      wires.any((w) =>
          w['fromNode'] == converter['id'] &&
          w['toPin'] == '${readout.id}.value'),
      isTrue,
    );
  });

  testWidgets('turning off a capability removes its pin and prunes wires',
      (tester) async {
    final go = seedButton('Go');
    final def = ControllerLayout.fromJson(project.controller).buildNodeDef();
    final graph = BlueprintGraph.fromJson(
      {},
      dynamicDefs: {kControllerDefId: def},
    );
    graph.ensureControllerNode(def, const Offset(-230, -150));
    final motor =
        graph.addNode(nodeDefById('motor.run')!, const Offset(360, -40));
    // Wire the "held" pin to the motor, then turn "held" off.
    graph.connect(
      PinRef(kControllerNodeId, '${go.id}.isDown', isOutput: true),
      PinRef(motor.id, 'run', isOutput: false),
    );
    project.graph.addAll(graph.toJson());
    await pumpEditor(tester);

    final heldPin = find.byKey(Key('pin-controller-${go.id}.isDown-out'));
    expect(heldPin, findsOneWidget);

    await tester.tap(find.byKey(Key('control-${go.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('control-cap-isDown')));
    await tester.pumpAndSettle();

    expect(heldPin, findsNothing); // pin removed from the node
    final json = await saved(tester);
    expect(json['wires'], isEmpty); // its wire was pruned
  });

  testWidgets('renaming a control relabels its pins but keeps wires',
      (tester) async {
    final control = seedButton('Go');
    await pumpEditor(tester);

    await tester.tap(find.byKey(Key('control-${control.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('control-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Launch');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(find.text('Launch touched'), findsOneWidget);
    expect(find.text('Go touched'), findsNothing);
  });

  testWidgets('tabs: add, switch, and controls stay per-tab', (tester) async {
    final control = seedButton('Go');
    await pumpEditor(tester);
    expect(find.text('Go'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ctrl-add-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // New tab is shown and empty; Main's control hidden but pins remain.
    await tester.tap(find.text('Tab 2'));
    await tester.pumpAndSettle();
    expect(find.text('Go'), findsNothing);
    expect(find.text('Go touched'), findsOneWidget);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    expect(find.text('Go'), findsOneWidget);
    expect(find.byKey(Key('control-${control.id}')), findsOneWidget);
  });

  testWidgets('dragging a control moves it within the tab', (tester) async {
    final control = seedButton('Go');
    await pumpEditor(tester);

    await tester.drag(
        find.byKey(Key('control-${control.id}')), const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 500));

    final tabs = project.controller['tabs'] as List;
    final savedControl =
        ((tabs.first as Map)['controls'] as List).first as Map;
    expect(savedControl['x'], greaterThan(0.5));
    expect(savedControl['y'], greaterThan(0.5));
  });
}
