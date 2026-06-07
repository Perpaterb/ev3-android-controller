import 'pins.dart';

/// Definition id of the controller node. Its [NodeDef] is built dynamically
/// from the [ControllerLayout] rather than living in the catalog.
const String kControllerDefId = 'controller';

/// Extra setting a node carries besides its pins.
enum NodeConfigKind {
  none,
  motorPort, // which EV3 output port (A-D)
  sensorPort, // which EV3 input port (1-4)
  intValue, // a number the user types
  boolValue, // a yes/no the user toggles
}

/// A node type in the catalog: what it's called, how it's coloured, and the
/// pins it exposes. Inputs render on the left, outputs on the right.
class NodeDef {
  const NodeDef({
    required this.id,
    required this.title,
    required this.category,
    this.inputs = const [],
    this.outputs = const [],
    this.configKind = NodeConfigKind.none,
  });

  final String id;
  final String title;
  final NodeCategory category;
  final List<PinSpec> inputs;
  final List<PinSpec> outputs;
  final NodeConfigKind configKind;

  PinSpec? pin(String pinId, {required bool isOutput}) {
    for (final spec in isOutput ? outputs : inputs) {
      if (spec.id == pinId) return spec;
    }
    return null;
  }

  List<String>? get portChoices => switch (configKind) {
        NodeConfigKind.motorPort => const ['A', 'B', 'C', 'D'],
        NodeConfigKind.sensorPort => const ['1', '2', '3', '4'],
        _ => null,
      };

  Map<String, dynamic> defaultConfig() => switch (configKind) {
        NodeConfigKind.none => {},
        NodeConfigKind.motorPort => {'port': 'A'},
        NodeConfigKind.sensorPort => {'port': '1'},
        NodeConfigKind.intValue => {'value': 0},
        NodeConfigKind.boolValue => {'value': false},
      };
}

/// Every node the user can add from the add-node menu. The controller node
/// (Epic 4) is special-cased and doesn't live here.
const List<NodeDef> nodeCatalog = [
  // Motors
  NodeDef(
    id: 'motor.run',
    title: 'Motor',
    category: NodeCategory.motor,
    configKind: NodeConfigKind.motorPort,
    inputs: [
      PinSpec('run', 'Run', PinType.power),
      PinSpec('speed', 'Speed', PinType.integer),
      PinSpec('forward', 'Forward?', PinType.boolean),
    ],
    outputs: [
      PinSpec('then', 'Then', PinType.power),
      PinSpec('angle', 'Angle', PinType.integer),
    ],
  ),
  NodeDef(
    id: 'motor.stop',
    title: 'Stop Motor',
    category: NodeCategory.motor,
    configKind: NodeConfigKind.motorPort,
    inputs: [PinSpec('stop', 'Stop', PinType.power)],
    outputs: [PinSpec('then', 'Then', PinType.power)],
  ),
  // Sensors
  NodeDef(
    id: 'sensor.touch',
    title: 'Touch Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [PinSpec('pressed', 'Pressed?', PinType.boolean)],
  ),
  NodeDef(
    id: 'sensor.distance',
    title: 'Distance Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [PinSpec('distance', 'Distance', PinType.integer)],
  ),
  // Math
  NodeDef(
    id: 'math.add',
    title: 'Add',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A + B', PinType.integer)],
  ),
  NodeDef(
    id: 'math.subtract',
    title: 'Subtract',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A - B', PinType.integer)],
  ),
  NodeDef(
    id: 'math.multiply',
    title: 'Multiply',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A × B', PinType.integer)],
  ),
  NodeDef(
    id: 'math.greater',
    title: 'Is Bigger?',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A > B', PinType.boolean)],
  ),
  // Logic
  NodeDef(
    id: 'logic.and',
    title: 'And',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Both?', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.or',
    title: 'Or',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Either?', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.not',
    title: 'Not',
    category: NodeCategory.logic,
    inputs: [PinSpec('value', 'Value', PinType.boolean)],
    outputs: [PinSpec('result', 'Opposite', PinType.boolean)],
  ),
  // Flow
  NodeDef(
    id: 'flow.branch',
    title: 'If / Branch',
    category: NodeCategory.flow,
    inputs: [
      PinSpec('exec', 'Do', PinType.power),
      PinSpec('condition', 'Yes?', PinType.boolean),
    ],
    outputs: [
      PinSpec('ifTrue', 'If yes', PinType.power),
      PinSpec('ifFalse', 'If no', PinType.power),
    ],
  ),
  NodeDef(
    id: 'flow.sequence',
    title: 'Sequence',
    category: NodeCategory.flow,
    inputs: [PinSpec('exec', 'Do', PinType.power)],
    outputs: [
      PinSpec('then1', 'First', PinType.power),
      PinSpec('then2', 'Second', PinType.power),
    ],
  ),
  // Values
  NodeDef(
    id: 'value.int',
    title: 'Integer',
    category: NodeCategory.value,
    configKind: NodeConfigKind.intValue,
    outputs: [PinSpec('value', 'Value', PinType.integer)],
  ),
  NodeDef(
    id: 'value.bool',
    title: 'Boolean True / False',
    category: NodeCategory.value,
    configKind: NodeConfigKind.boolValue,
    outputs: [PinSpec('value', 'Value', PinType.boolean)],
  ),
];

final Map<String, NodeDef> _defIndex = {
  for (final def in nodeCatalog) def.id: def,
};

NodeDef? nodeDefById(String id) => _defIndex[id];
