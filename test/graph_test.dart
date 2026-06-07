import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BlueprintGraph graph;

  setUp(() => graph = BlueprintGraph());

  NodeDef def(String id) => nodeDefById(id)!;

  test('addNode applies defaults from the definition', () {
    final motor = graph.addNode(def('motor.run'), const Offset(10, 20));
    expect(motor.label, 'Motor');
    expect(motor.position, const Offset(10, 20));
    expect(motor.config['port'], 'A');

    final number = graph.addNode(def('value.int'), Offset.zero);
    expect(number.config['value'], 0);
  });

  test('moveNode shifts position by a delta', () {
    final node = graph.addNode(def('math.add'), const Offset(100, 100));
    graph.moveNode(node.id, const Offset(15, -5));
    expect(node.position, const Offset(115, 95));
  });

  test('renameNode trims and rejects empty names', () {
    final node = graph.addNode(def('math.add'), Offset.zero);
    graph.renameNode(node.id, '  Adder  ');
    expect(node.label, 'Adder');
    graph.renameNode(node.id, '   ');
    expect(node.label, 'Adder');
  });

  test('connect joins matching types regardless of tap order', () {
    final number = graph.addNode(def('value.int'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    final out = PinRef(number.id, 'value', isOutput: true);
    final inA = PinRef(add.id, 'a', isOutput: false);

    expect(graph.canConnect(inA, out), isTrue); // input tapped first
    expect(graph.connect(inA, out), isTrue);
    expect(graph.wires, hasLength(1));
    expect(graph.wires.single.from, out);
    expect(graph.wires.single.to, inA);
  });

  test('mismatched types cannot connect', () {
    final flag = graph.addNode(def('value.bool'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    final out = PinRef(flag.id, 'value', isOutput: true);
    final inA = PinRef(add.id, 'a', isOutput: false);
    expect(graph.canConnect(out, inA), isFalse);
    expect(graph.connect(out, inA), isFalse);
    expect(graph.wires, isEmpty);
  });

  test('two outputs or two inputs cannot connect', () {
    final a = graph.addNode(def('value.int'), Offset.zero);
    final b = graph.addNode(def('value.int'), Offset.zero);
    expect(
      graph.canConnect(
        PinRef(a.id, 'value', isOutput: true),
        PinRef(b.id, 'value', isOutput: true),
      ),
      isFalse,
    );
  });

  test('a node cannot wire to itself', () {
    final add = graph.addNode(def('math.add'), Offset.zero);
    expect(
      graph.canConnect(
        PinRef(add.id, 'result', isOutput: true),
        PinRef(add.id, 'a', isOutput: false),
      ),
      isFalse,
    );
  });

  test('a new wire into an input replaces the old one', () {
    final first = graph.addNode(def('value.int'), Offset.zero);
    final second = graph.addNode(def('value.int'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    final inA = PinRef(add.id, 'a', isOutput: false);

    graph.connect(PinRef(first.id, 'value', isOutput: true), inA);
    graph.connect(PinRef(second.id, 'value', isOutput: true), inA);

    expect(graph.wires, hasLength(1));
    expect(graph.wires.single.fromNode, second.id);
  });

  test('a power output drives only one target', () {
    final branch = graph.addNode(def('flow.branch'), Offset.zero);
    final motorA = graph.addNode(def('motor.run'), Offset.zero);
    final motorB = graph.addNode(def('motor.run'), Offset.zero);
    final ifTrue = PinRef(branch.id, 'ifTrue', isOutput: true);

    graph.connect(ifTrue, PinRef(motorA.id, 'run', isOutput: false));
    graph.connect(ifTrue, PinRef(motorB.id, 'run', isOutput: false));

    expect(graph.wires, hasLength(1));
    expect(graph.wires.single.toNode, motorB.id);
  });

  test('a data output fans out to many inputs', () {
    final number = graph.addNode(def('value.int'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    final out = PinRef(number.id, 'value', isOutput: true);

    graph.connect(out, PinRef(add.id, 'a', isOutput: false));
    graph.connect(out, PinRef(add.id, 'b', isOutput: false));

    expect(graph.wires, hasLength(2));
  });

  test('removeNode cascades its wires', () {
    final number = graph.addNode(def('value.int'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    graph.connect(PinRef(number.id, 'value', isOutput: true),
        PinRef(add.id, 'a', isOutput: false));

    graph.removeNode(number.id);
    expect(graph.node(number.id), isNull);
    expect(graph.wires, isEmpty);
    expect(graph.node(add.id), isNotNull);
  });

  test('disconnectPin removes only that pin\'s wires', () {
    final number = graph.addNode(def('value.int'), Offset.zero);
    final add = graph.addNode(def('math.add'), Offset.zero);
    final out = PinRef(number.id, 'value', isOutput: true);
    graph.connect(out, PinRef(add.id, 'a', isOutput: false));
    graph.connect(out, PinRef(add.id, 'b', isOutput: false));

    graph.disconnectPin(PinRef(add.id, 'a', isOutput: false));
    expect(graph.wires, hasLength(1));
    expect(graph.wires.single.toPin, 'b');

    graph.disconnectPin(out); // output side removes everything it drives
    expect(graph.wires, isEmpty);
  });

  test('JSON round-trips nodes, wires, labels and config', () {
    final motor = graph.addNode(def('motor.run'), const Offset(5, 7));
    graph.renameNode(motor.id, 'Left Wheel');
    graph.setConfig(motor.id, 'port', 'C');
    final number = graph.addNode(def('value.int'), const Offset(-50, 12));
    graph.setConfig(number.id, 'value', 42);
    graph.connect(PinRef(number.id, 'value', isOutput: true),
        PinRef(motor.id, 'speed', isOutput: false));

    final copy = BlueprintGraph.fromJson(graph.toJson());
    expect(copy.nodes, hasLength(2));
    final motorCopy = copy.node(motor.id)!;
    expect(motorCopy.label, 'Left Wheel');
    expect(motorCopy.position, const Offset(5, 7));
    expect(motorCopy.config['port'], 'C');
    expect(copy.node(number.id)!.config['value'], 42);
    expect(copy.wires, hasLength(1));
    expect(copy.wires.single.toPin, 'speed');
  });

  test('fromJson skips unknown defs and orphaned wires', () {
    final json = {
      'nodes': [
        {
          'id': 'n1',
          'def': 'no.such.node',
          'label': 'Ghost',
          'x': 0.0,
          'y': 0.0,
          'config': <String, dynamic>{},
        },
        {
          'id': 'n2',
          'def': 'math.add',
          'label': 'Add',
          'x': 0.0,
          'y': 0.0,
          'config': <String, dynamic>{},
        },
      ],
      'wires': [
        {'fromNode': 'n1', 'fromPin': 'value', 'toNode': 'n2', 'toPin': 'a'},
      ],
    };
    final graph = BlueprintGraph.fromJson(json);
    expect(graph.nodes, hasLength(1));
    expect(graph.wires, isEmpty);
  });
}
