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
  stringValue, // a piece of text the user types
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
    this.configLabel,
    this.configDefault,
  });

  final String id;
  final String title;
  final NodeCategory category;
  final List<PinSpec> inputs;
  final List<PinSpec> outputs;
  final NodeConfigKind configKind;

  /// Label shown next to the config editor (defaults to a generic one).
  final String? configLabel;

  /// Starting value for a value-style config (number/yes-no/text).
  final Object? configDefault;

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
        NodeConfigKind.intValue => {'value': configDefault ?? 0},
        NodeConfigKind.boolValue => {'value': configDefault ?? false},
        NodeConfigKind.stringValue => {'value': configDefault ?? ''},
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
  // Drives to an exact angle and holds — great for steering to a limit.
  NodeDef(
    id: 'motor.toAngle',
    title: 'Turn to Angle',
    category: NodeCategory.motor,
    configKind: NodeConfigKind.motorPort,
    inputs: [
      PinSpec('run', 'Go', PinType.power),
      PinSpec('angle', 'Angle', PinType.integer),
      PinSpec('speed', 'Speed', PinType.integer),
    ],
    outputs: [PinSpec('then', 'Then', PinType.power)],
  ),
  // Zeroes the angle counter so it measures from here.
  NodeDef(
    id: 'motor.reset',
    title: 'Reset Angle',
    category: NodeCategory.motor,
    configKind: NodeConfigKind.motorPort,
    inputs: [PinSpec('reset', 'Reset', PinType.power)],
    outputs: [PinSpec('then', 'Then', PinType.power)],
  ),
  // Sensors — EV3
  NodeDef(
    id: 'sensor.touch',
    title: 'Touch Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [PinSpec('pressed', 'Pressed?', PinType.boolean)],
  ),
  NodeDef(
    id: 'sensor.colour',
    title: 'Colour Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [
      PinSpec('colour', 'Colour (0-7)', PinType.integer),
      PinSpec('reflected', 'Reflected light', PinType.integer),
      PinSpec('ambient', 'Ambient light', PinType.integer),
    ],
  ),
  NodeDef(
    id: 'sensor.distance', // kept id for save-compat; was "Distance Sensor"
    title: 'Ultrasonic Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [PinSpec('distance', 'Distance (cm)', PinType.integer)],
  ),
  NodeDef(
    id: 'sensor.gyro',
    title: 'Gyro Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [
      PinSpec('angle', 'Angle', PinType.integer),
      PinSpec('rate', 'Turn rate', PinType.integer),
    ],
  ),
  NodeDef(
    id: 'sensor.infrared',
    title: 'Infrared Sensor',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [
      PinSpec('distance', 'Distance', PinType.integer),
      PinSpec('heading', 'Beacon heading', PinType.integer),
      PinSpec('beacon', 'Beacon distance', PinType.integer),
    ],
  ),
  // Sensors — NXT
  NodeDef(
    id: 'sensor.sound',
    title: 'Sound Sensor (NXT)',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [PinSpec('level', 'Loudness', PinType.integer)],
  ),
  NodeDef(
    id: 'sensor.light',
    title: 'Light Sensor (NXT)',
    category: NodeCategory.sensor,
    configKind: NodeConfigKind.sensorPort,
    outputs: [
      PinSpec('reflected', 'Reflected light', PinType.integer),
      PinSpec('ambient', 'Ambient light', PinType.integer),
    ],
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
  NodeDef(
    id: 'math.less',
    title: 'Is Smaller?',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A < B', PinType.boolean)],
  ),
  NodeDef(
    id: 'math.equals',
    title: 'Is Equal?',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A = B', PinType.boolean)],
  ),
  // Jitter-friendly equality: true when A is within ± the tolerance of B.
  NodeDef(
    id: 'math.near',
    title: 'Is Close To?',
    category: NodeCategory.math,
    inputs: [
      PinSpec('a', 'A', PinType.integer),
      PinSpec('b', 'B', PinType.integer),
      PinSpec('within', 'Within ±', PinType.integer),
    ],
    outputs: [PinSpec('result', 'A ≈ B', PinType.boolean)],
  ),
  // Logic
  NodeDef(
    id: 'logic.and',
    title: 'Both? (AND)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Both?', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.or',
    title: 'Either? (OR)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Either?', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.not',
    title: 'Opposite (NOT)',
    category: NodeCategory.logic,
    inputs: [PinSpec('value', 'Value', PinType.boolean)],
    outputs: [PinSpec('result', 'Opposite', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.xor',
    title: 'Different? (XOR)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'A ≠ B', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.same',
    title: 'Same? (XNOR)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'A = B', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.nand',
    title: 'Not Both? (NAND)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Not both', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.nor',
    title: 'Neither? (NOR)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'Neither', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.imply',
    title: 'If A then B? (IMPLY)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'A → B', PinType.boolean)],
  ),
  NodeDef(
    id: 'logic.nimply',
    title: 'A but not B? (NIMPLY)',
    category: NodeCategory.logic,
    inputs: [
      PinSpec('a', 'A', PinType.boolean),
      PinSpec('b', 'B', PinType.boolean),
    ],
    outputs: [PinSpec('result', 'A and not B', PinType.boolean)],
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
  // Gate: lets power through `Enter` only while open; Open/Close/Toggle
  // change its state, like UE5's Gate.
  NodeDef(
    id: 'flow.gate',
    title: 'Gate',
    category: NodeCategory.flow,
    configKind: NodeConfigKind.boolValue,
    configLabel: 'Start open',
    inputs: [
      PinSpec('enter', 'Enter', PinType.power),
      PinSpec('open', 'Open', PinType.power),
      PinSpec('close', 'Close', PinType.power),
      PinSpec('toggle', 'Toggle', PinType.power),
    ],
    outputs: [PinSpec('exit', 'Exit', PinType.power)],
  ),
  // Do Once: passes power through the first time only, until Reset.
  NodeDef(
    id: 'flow.doOnce',
    title: 'Do Once',
    category: NodeCategory.flow,
    configKind: NodeConfigKind.boolValue,
    configLabel: 'Start closed',
    inputs: [
      PinSpec('exec', 'Do', PinType.power),
      PinSpec('reset', 'Reset', PinType.power),
    ],
    outputs: [PinSpec('completed', 'Done', PinType.power)],
  ),
  // Do N Times: passes power through up to N times, until Reset.
  NodeDef(
    id: 'flow.doN',
    title: 'Do N Times',
    category: NodeCategory.flow,
    configKind: NodeConfigKind.intValue,
    configLabel: 'Times',
    configDefault: 3,
    inputs: [
      PinSpec('exec', 'Do', PinType.power),
      PinSpec('reset', 'Reset', PinType.power),
    ],
    outputs: [
      PinSpec('exit', 'Then', PinType.power),
      PinSpec('counter', 'Count', PinType.integer),
    ],
  ),
  // Events
  NodeDef(
    id: 'event.tick',
    title: 'Every Tick',
    category: NodeCategory.event,
    outputs: [PinSpec('tick', 'Each frame', PinType.power)],
  ),
  NodeDef(
    id: 'event.start',
    title: 'On Start',
    category: NodeCategory.event,
    outputs: [PinSpec('started', 'At launch', PinType.power)],
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
  // Text
  NodeDef(
    id: 'text.string',
    title: 'String',
    category: NodeCategory.text,
    configKind: NodeConfigKind.stringValue,
    outputs: [PinSpec('value', 'Value', PinType.string)],
  ),
  NodeDef(
    id: 'text.pick',
    title: 'Pick String',
    category: NodeCategory.text,
    inputs: [
      PinSpec('condition', 'Yes?', PinType.boolean),
      PinSpec('a', 'If yes', PinType.string),
      PinSpec('b', 'If no', PinType.string),
    ],
    outputs: [PinSpec('result', 'Picked', PinType.string)],
  ),
  NodeDef(
    id: 'text.fromInt',
    title: 'Int → String',
    category: NodeCategory.text,
    inputs: [PinSpec('number', 'Number', PinType.integer)],
    outputs: [PinSpec('result', 'Text', PinType.string)],
  ),
  NodeDef(
    id: 'text.append',
    title: 'Append String',
    category: NodeCategory.text,
    inputs: [
      PinSpec('a', 'A', PinType.string),
      PinSpec('b', 'B', PinType.string),
    ],
    outputs: [PinSpec('result', 'A + B', PinType.string)],
  ),
  NodeDef(
    id: 'text.fromBool',
    title: 'Bool → String',
    category: NodeCategory.text,
    inputs: [PinSpec('value', 'Value', PinType.boolean)],
    outputs: [PinSpec('result', 'Text', PinType.string)],
  ),
  // "1" while power is flowing, "0" when it isn't: wired to a button or
  // d-pad it reads the held state live; other power sources blink a short 1
  // per pulse.
  NodeDef(
    id: 'text.fromPower',
    title: 'Power → String',
    category: NodeCategory.text,
    inputs: [PinSpec('power', 'Power', PinType.power)],
    outputs: [PinSpec('result', '0 / 1', PinType.string)],
  ),
];

final Map<String, NodeDef> _defIndex = {
  for (final def in nodeCatalog) def.id: def,
};

NodeDef? nodeDefById(String id) => _defIndex[id];

String _ordinal(int i) => switch (i) {
      1 => 'First',
      2 => 'Second',
      3 => 'Third',
      4 => 'Fourth',
      5 => 'Fifth',
      6 => 'Sixth',
      _ => 'Step $i',
    };

/// A Sequence definition with [outs] power outputs. Sequence nodes grow a
/// fresh output whenever the last one gets wired (and shrink back when
/// trailing outputs are freed), so there's always a spare to plug into.
NodeDef sequenceDef(int outs) => NodeDef(
      id: 'flow.sequence',
      title: 'Sequence',
      category: NodeCategory.flow,
      inputs: const [PinSpec('exec', 'Do', PinType.power)],
      outputs: [
        for (var i = 1; i <= outs; i++)
          PinSpec('then$i', _ordinal(i), PinType.power),
      ],
    );
