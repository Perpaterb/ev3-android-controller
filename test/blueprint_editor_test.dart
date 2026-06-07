import 'package:ev3_controller/blueprint/blueprint_editor.dart';
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
    // Desktop-sized window: the controller node occupies the canvas centre,
    // so test nodes live to its left (negative canvas x) and the empty-canvas
    // gestures land well away from it.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlueprintEditor(store: store, project: project),
      ),
    ));
  }

  /// Lets the debounced autosave (400 ms) fire and checks the saved graph.
  Future<Map<String, dynamic>> savedGraph(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    return project.graph;
  }

  /// Seeds the project with a prebuilt graph before the editor opens.
  /// The default viewport centres canvas (0,0) on screen — which is where
  /// the controller node sits — so test nodes go left of it.
  BlueprintGraph seed() {
    final graph = BlueprintGraph();
    project.graph.addAll(graph.toJson());
    return graph;
  }

  void persist(BlueprintGraph graph) => project.graph.addAll(graph.toJson());

  /// Saved nodes minus the ever-present controller node.
  List<Map> userNodes(Map<String, dynamic> saved) => [
        for (final n in (saved['nodes'] as List? ?? const []))
          if ((n as Map)['id'] != kControllerNodeId) n,
      ];

  Finder pin(GraphNode node, String pinId, {required bool isOutput}) =>
      find.byKey(Key('pin-${node.id}-$pinId-${isOutput ? 'out' : 'in'}'));

  testWidgets('long-press on empty canvas adds a node via the menu',
      (tester) async {
    await pumpEditor(tester);
    await tester.longPressAt(const Offset(200, 1000)); // empty canvas, clear of the controller
    await tester.pumpAndSettle();
    expect(find.text('Add a node'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-node-math.add')));
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsOneWidget); // the node's header
    final saved = await savedGraph(tester);
    expect(userNodes(saved), hasLength(1));
    expect(userNodes(saved).single['def'], 'math.add');
  });

  testWidgets('dragging the header moves the node', (tester) async {
    final graph = seed();
    final node = graph.addNode(nodeDefById('math.add')!, const Offset(-700, -400));
    persist(graph);
    await pumpEditor(tester);

    await tester.drag(
        find.byKey(Key('node-header-${node.id}')), const Offset(40, 30));
    final saved = await savedGraph(tester);
    final savedNode = userNodes(saved).single;
    expect(savedNode['x'], closeTo(-660, 1));
    expect(savedNode['y'], closeTo(-370, 1));
  });

  testWidgets('tap pin, tap compatible pin: wire created', (tester) async {
    final graph = seed();
    final number =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -200));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(pin(number, 'value', isOutput: true));
    await tester.pump();
    expect(find.byKey(const Key('cancel-wiring')), findsOneWidget);

    await tester.tap(pin(add, 'a', isOutput: false));
    await tester.pump();
    expect(find.byKey(const Key('cancel-wiring')), findsNothing);

    final saved = await savedGraph(tester);
    final wires = saved['wires'] as List;
    expect(wires, hasLength(1));
    expect(wires.single['fromNode'], number.id);
    expect(wires.single['toPin'], 'a');
  });

  testWidgets('tapping an incompatible pin is ignored, wiring stays active',
      (tester) async {
    final graph = seed();
    final flag =
        graph.addNode(nodeDefById('value.bool')!, const Offset(-700, -200));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(pin(flag, 'value', isOutput: true)); // boolean out
    await tester.pump();
    await tester.tap(pin(add, 'a', isOutput: false)); // integer in
    await tester.pump();

    expect(find.byKey(const Key('cancel-wiring')), findsOneWidget);
    final saved = await savedGraph(tester);
    expect(saved['wires'] ?? [], isEmpty);
  });

  testWidgets('the red X cancels wiring mode', (tester) async {
    final graph = seed();
    final number =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -200));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(pin(number, 'value', isOutput: true));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-wiring')));
    await tester.pump();
    expect(find.byKey(const Key('cancel-wiring')), findsNothing);

    // The pin that would have been the target connects nothing now.
    await tester.tap(pin(add, 'a', isOutput: false));
    await tester.pump();
    final saved = await savedGraph(tester);
    expect(saved['wires'] ?? [], isEmpty);
  });

  testWidgets('a new wire replaces the one already in the input',
      (tester) async {
    final graph = seed();
    final first =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -320));
    final second =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -80));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    graph.connect(PinRef(first.id, 'value', isOutput: true),
        PinRef(add.id, 'a', isOutput: false));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(pin(second, 'value', isOutput: true));
    await tester.pump();
    await tester.tap(pin(add, 'a', isOutput: false));
    await tester.pump();

    final saved = await savedGraph(tester);
    final wires = saved['wires'] as List;
    expect(wires, hasLength(1));
    expect(wires.single['fromNode'], second.id);
  });

  testWidgets('long-press on a pin disconnects its wires', (tester) async {
    final graph = seed();
    final number =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -200));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    graph.connect(PinRef(number.id, 'value', isOutput: true),
        PinRef(add.id, 'a', isOutput: false));
    persist(graph);
    await pumpEditor(tester);

    await tester.longPress(pin(add, 'a', isOutput: false));
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
    final saved = await savedGraph(tester);
    expect(saved['wires'], isEmpty);
  });

  testWidgets('selecting a node allows rename', (tester) async {
    final graph = seed();
    final node = graph.addNode(nodeDefById('motor.run')!, const Offset(-700, -400));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(find.byKey(Key('node-header-${node.id}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('node-edit-${node.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Left Wheel');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Left Wheel'), findsOneWidget);
    final saved = await savedGraph(tester);
    expect(userNodes(saved).single['label'], 'Left Wheel');
  });

  testWidgets('deleting a node removes it and its wires', (tester) async {
    final graph = seed();
    final number =
        graph.addNode(nodeDefById('value.int')!, const Offset(-700, -200));
    final add = graph.addNode(nodeDefById('math.add')!, const Offset(-400, -200));
    graph.connect(PinRef(number.id, 'value', isOutput: true),
        PinRef(add.id, 'a', isOutput: false));
    persist(graph);
    await pumpEditor(tester);

    await tester.tap(find.byKey(Key('node-header-${number.id}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('node-delete-${number.id}')));
    await tester.pump();

    final saved = await savedGraph(tester);
    expect(userNodes(saved), hasLength(1));
    expect(saved['wires'], isEmpty);
  });
}
