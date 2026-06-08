import 'package:ev3_controller/blueprint/model/controller_layout.dart';
import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:ev3_controller/blueprint/model/variables.dart';
import 'package:ev3_controller/run/graph_runner.dart';
import 'package:ev3_controller/services/ev3_brick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ControllerLayout layout;
  late BlueprintGraph graph;
  late MockEv3Brick brick;
  late VariableSet variables;

  setUp(() {
    layout = ControllerLayout();
    graph = BlueprintGraph();
    brick = MockEv3Brick();
    variables = VariableSet();
  });

  ControllerControl addControl(ControlKind kind, String name) =>
      layout.addControl(
        tabId: layout.tabs.first.id,
        kind: kind,
        name: name,
        position: const Offset(0.5, 0.5),
      );

  /// Call after the layout is final, before wiring controller pins.
  void syncController() =>
      graph.ensureControllerNode(layout.buildNodeDef(), Offset.zero);

  GraphNode node(String defId, [Map<String, Object>? config]) {
    final n = graph.addNode(nodeDefById(defId)!, Offset.zero);
    config?.forEach((k, v) => graph.setConfig(n.id, k, v));
    return n;
  }

  void wire(String fromNode, String fromPin, String toNode, String toPin) {
    expect(
      graph.connect(
        PinRef(fromNode, fromPin, isOutput: true),
        PinRef(toNode, toPin, isOutput: false),
      ),
      isTrue,
      reason: 'failed to wire $fromNode.$fromPin -> $toNode.$toPin',
    );
  }

  GraphRunner runner() => GraphRunner(
      graph: graph, layout: layout, brick: brick, variables: variables);

  test('button press runs a motor with wired speed and direction', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final motor = node('motor.run', {'port': 'B'});
    final speed = node('value.int', {'value': 42});
    final reverse = node('value.bool', {'value': false});
    wire(kControllerNodeId, '${go.id}.pressed', motor.id, 'run');
    wire(speed.id, 'value', motor.id, 'speed');
    wire(reverse.id, 'value', motor.id, 'forward');

    runner().buttonPressed(go.id);
    expect(brick.log, ['Motor B: run at 42% backward']);
  });

  test('unwired motor inputs default to full speed forward', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final motor = node('motor.run');
    wire(kControllerNodeId, '${go.id}.pressed', motor.id, 'run');

    runner().buttonPressed(go.id);
    expect(brick.log, ['Motor A: run at 100% forward']);
  });

  test('button release stops the motor', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final run = node('motor.run', {'port': 'C'});
    final stop = node('motor.stop', {'port': 'C'});
    wire(kControllerNodeId, '${go.id}.pressed', run.id, 'run');
    wire(kControllerNodeId, '${go.id}.released', stop.id, 'stop');

    final r = runner();
    r.buttonPressed(go.id);
    r.buttonReleased(go.id);
    expect(brick.log,
        ['Motor C: run at 100% forward', 'Motor C: stop']);
  });

  test('slider value flows through math into the motor', () {
    final go = addControl(ControlKind.button, 'Go');
    final speed = addControl(ControlKind.slider, 'Speed');
    syncController();
    final motor = node('motor.run');
    final add = node('math.add');
    final ten = node('value.int', {'value': 10});
    wire(kControllerNodeId, '${go.id}.pressed', motor.id, 'run');
    wire(kControllerNodeId, '${speed.id}.value', add.id, 'a');
    wire(ten.id, 'value', add.id, 'b');
    wire(add.id, 'result', motor.id, 'speed');

    final r = runner();
    r.sliderChanged(speed.id, 32);
    r.buttonPressed(go.id);
    expect(brick.log.last, 'Motor A: run at 42% forward');
  });

  test('motor speed clamps to 0-100', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final motor = node('motor.run');
    final big = node('value.int', {'value': 9000});
    wire(kControllerNodeId, '${go.id}.pressed', motor.id, 'run');
    wire(big.id, 'value', motor.id, 'speed');

    runner().buttonPressed(go.id);
    expect(brick.log, ['Motor A: run at 100% forward']);
  });

  test('branch routes power on a toggle condition', () {
    final go = addControl(ControlKind.button, 'Go');
    final fast = addControl(ControlKind.toggle, 'Fast');
    syncController();
    final branch = node('flow.branch');
    final run = node('motor.run');
    final stop = node('motor.stop');
    wire(kControllerNodeId, '${go.id}.pressed', branch.id, 'exec');
    wire(kControllerNodeId, '${fast.id}.state', branch.id, 'condition');
    wire(branch.id, 'ifTrue', run.id, 'run');
    wire(branch.id, 'ifFalse', stop.id, 'stop');

    final r = runner();
    r.buttonPressed(go.id); // toggle starts false
    expect(brick.log, ['Motor A: stop']);

    r.toggleChanged(fast.id, true);
    r.buttonPressed(go.id);
    expect(brick.log.last, 'Motor A: run at 100% forward');
  });

  test('sequence fires its outputs in order', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final seq = node('flow.sequence');
    final run = node('motor.run', {'port': 'B'});
    final stop = node('motor.stop', {'port': 'D'});
    wire(kControllerNodeId, '${go.id}.pressed', seq.id, 'exec');
    wire(seq.id, 'then1', run.id, 'run');
    wire(seq.id, 'then2', stop.id, 'stop');

    runner().buttonPressed(go.id);
    expect(brick.log,
        ['Motor B: run at 100% forward', 'Motor D: stop']);
  });

  test('each d-pad direction has its own pressed and released pins', () {
    final drive = addControl(ControlKind.dpad, 'Drive');
    syncController();
    final up = node('motor.run', {'port': 'A'});
    final stop = node('motor.stop', {'port': 'A'});
    wire(kControllerNodeId, '${drive.id}.up', up.id, 'run');
    wire(kControllerNodeId, '${drive.id}.upReleased', stop.id, 'stop');

    final r = runner();
    r.dpadPressed(drive.id, 'up');
    r.dpadReleased(drive.id, 'up');
    expect(brick.log,
        ['Motor A: run at 100% forward', 'Motor A: stop']);
  });

  test('steering: tapping left never disturbs the held forward direction',
      () {
    final drive = addControl(ControlKind.dpad, 'Drive');
    syncController();
    // up drives motor B; left/leftReleased steer motor C.
    final forward = node('motor.run', {'port': 'B'});
    final steer = node('motor.run', {'port': 'C'});
    final straighten = node('motor.stop', {'port': 'C'});
    final stopForward = node('motor.stop', {'port': 'B'});
    wire(kControllerNodeId, '${drive.id}.up', forward.id, 'run');
    wire(kControllerNodeId, '${drive.id}.upReleased', stopForward.id, 'stop');
    wire(kControllerNodeId, '${drive.id}.left', steer.id, 'run');
    wire(kControllerNodeId, '${drive.id}.leftReleased',
        straighten.id, 'stop');

    final r = runner();
    r.dpadPressed(drive.id, 'up'); // drive forward…
    r.dpadPressed(drive.id, 'left'); // …steer…
    r.dpadReleased(drive.id, 'left'); // …straighten, still driving
    expect(brick.log, [
      'Motor B: run at 100% forward',
      'Motor C: run at 100% forward',
      'Motor C: stop',
    ]);
    r.dpadReleased(drive.id, 'up');
    expect(brick.log.last, 'Motor B: stop');
  });

  test('two buttons can be held at the same time', () {
    final left = addControl(ControlKind.button, 'Left');
    final right = addControl(ControlKind.button, 'Right');
    syncController();
    final motorB = node('motor.run', {'port': 'B'});
    final motorC = node('motor.run', {'port': 'C'});
    final stopB = node('motor.stop', {'port': 'B'});
    wire(kControllerNodeId, '${left.id}.pressed', motorB.id, 'run');
    wire(kControllerNodeId, '${right.id}.pressed', motorC.id, 'run');
    wire(kControllerNodeId, '${left.id}.released', stopB.id, 'stop');

    final r = runner();
    r.buttonPressed(left.id);
    r.buttonPressed(right.id); // both held now
    expect(brick.log, [
      'Motor B: run at 100% forward',
      'Motor C: run at 100% forward',
    ]);
    r.buttonReleased(left.id); // releasing one doesn't affect the other
    expect(brick.log.last, 'Motor B: stop');
  });

  test('a light reflects a sensor comparison live', () {
    final near = addControl(ControlKind.light, 'Near');
    syncController();
    final sensor = node('sensor.distance', {'port': '2'});
    final limit = node('value.int', {'value': 50});
    final greater = node('math.greater');
    final not = node('logic.not');
    // light on when distance is NOT greater than 50 (i.e. close)
    wire(sensor.id, 'distance', greater.id, 'a');
    wire(limit.id, 'value', greater.id, 'b');
    wire(greater.id, 'result', not.id, 'value');
    wire(not.id, 'result', kControllerNodeId, '${near.id}.on');

    final r = runner();
    brick.setSensor(2, SensorReading.distanceCm, 80);
    expect(r.lightOn(near.id), isFalse);
    brick.setSensor(2, SensorReading.distanceCm, 20);
    expect(r.lightOn(near.id), isTrue);
  });

  test('comparison nodes: bigger, smaller, equal', () {
    final lamp = addControl(ControlKind.light, 'Lamp');
    syncController();

    for (final (defId, a, b, expected) in [
      ('math.greater', 5, 3, true),
      ('math.greater', 3, 5, false),
      ('math.less', 3, 5, true),
      ('math.less', 5, 3, false),
      ('math.equals', 4, 4, true),
      ('math.equals', 4, 5, false),
    ]) {
      final compare = node(defId);
      final left = node('value.int', {'value': a});
      final right = node('value.int', {'value': b});
      wire(left.id, 'value', compare.id, 'a');
      wire(right.id, 'value', compare.id, 'b');
      wire(compare.id, 'result', kControllerNodeId, '${lamp.id}.on');
      expect(runner().lightOn(lamp.id), expected,
          reason: '$defId($a, $b) should be $expected');
    }
  });

  test('is close to: true within the tolerance, default ±5', () {
    final lamp = addControl(ControlKind.light, 'Lamp');
    syncController();

    for (final (a, b, within, expected) in [
      (50, 53, 5, true),
      (50, 56, 5, false),
      (50, 70, 25, true),
    ]) {
      final near = node('math.near');
      final left = node('value.int', {'value': a});
      final right = node('value.int', {'value': b});
      final tol = node('value.int', {'value': within});
      wire(left.id, 'value', near.id, 'a');
      wire(right.id, 'value', near.id, 'b');
      wire(tol.id, 'value', near.id, 'within');
      wire(near.id, 'result', kControllerNodeId, '${lamp.id}.on');
      expect(runner().lightOn(lamp.id), expected,
          reason: '|$a - $b| <= $within should be $expected');
    }
  });

  test('every two-input logic gate', () {
    final lamp = addControl(ControlKind.light, 'Lamp');
    syncController();

    for (final (defId, a, b, expected) in [
      ('logic.and', true, false, false),
      ('logic.or', true, false, true),
      ('logic.xor', true, false, true),
      ('logic.xor', true, true, false),
      ('logic.same', false, false, true), // matches even when both false
      ('logic.same', true, false, false),
      ('logic.nand', true, true, false),
      ('logic.nand', true, false, true),
      ('logic.nor', false, false, true),
      ('logic.nor', true, false, false),
      ('logic.imply', true, false, false), // A but not B → fails the promise
      ('logic.imply', false, false, true), // A false → promise holds
      ('logic.imply', true, true, true),
      ('logic.nimply', true, false, true),
      ('logic.nimply', true, true, false),
    ]) {
      final gate = node(defId);
      final left = node('value.bool', {'value': a});
      final right = node('value.bool', {'value': b});
      wire(left.id, 'value', gate.id, 'a');
      wire(right.id, 'value', gate.id, 'b');
      wire(gate.id, 'result', kControllerNodeId, '${lamp.id}.on');
      expect(runner().lightOn(lamp.id), expected,
          reason: '$defId($a, $b) should be $expected');
    }
  });

  test('a grown sequence fires all its outputs in order', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final seq = node('flow.sequence');
    final first = node('motor.run', {'port': 'A'});
    final second = node('motor.run', {'port': 'B'});
    final third = node('motor.run', {'port': 'C'});
    wire(kControllerNodeId, '${go.id}.pressed', seq.id, 'exec');
    wire(seq.id, 'then1', first.id, 'run');
    wire(seq.id, 'then2', second.id, 'run');
    wire(seq.id, 'then3', third.id, 'run'); // exists because then2 is wired

    runner().buttonPressed(go.id);
    expect(brick.log, [
      'Motor A: run at 100% forward',
      'Motor B: run at 100% forward',
      'Motor C: run at 100% forward',
    ]);
  });

  test('every sensor output reads its brick value', () {
    final lamp = addControl(ControlKind.light, 'L'); // unused, just a control
    syncController();
    expect(lamp.id, isNotEmpty);

    // Each (node, pin, reading) round-trips an injected value.
    final cases = <(String, String, SensorReading, int)>[
      ('sensor.colour', 'colour', SensorReading.colourId, 4),
      ('sensor.colour', 'reflected', SensorReading.reflectedLight, 60),
      ('sensor.colour', 'ambient', SensorReading.ambientLight, 12),
      ('sensor.distance', 'distance', SensorReading.distanceCm, 33),
      ('sensor.gyro', 'angle', SensorReading.gyroAngle, -90),
      ('sensor.gyro', 'rate', SensorReading.gyroRate, 15),
      ('sensor.infrared', 'distance', SensorReading.irProximity, 70),
      ('sensor.infrared', 'heading', SensorReading.beaconHeading, -5),
      ('sensor.infrared', 'beacon', SensorReading.beaconDistance, 40),
      ('sensor.sound', 'level', SensorReading.soundLevel, 55),
      ('sensor.light', 'reflected', SensorReading.nxtLightReflected, 80),
      ('sensor.light', 'ambient', SensorReading.nxtLightAmbient, 20),
    ];
    for (final (defId, pin, reading, value) in cases) {
      final readout = addControl(ControlKind.display, '$defId.$pin');
      syncController();
      final sensor = node(defId, {'port': '2'});
      final toText = node('text.fromInt');
      wire(sensor.id, pin, toText.id, 'number');
      wire(toText.id, 'result', kControllerNodeId, '${readout.id}.value');
      brick.setSensor(2, reading, value);
      expect(runner().displayValue(readout.id), '$value',
          reason: '$defId.$pin should read $value');
    }
  });

  test('a touch sensor reads pressed as a boolean', () {
    final bump = addControl(ControlKind.light, 'Bump');
    syncController();
    final touch = node('sensor.touch', {'port': '4'});
    wire(touch.id, 'pressed', kControllerNodeId, '${bump.id}.on');

    final r = runner();
    expect(r.lightOn(bump.id), isFalse);
    brick.setSensor(4, SensorReading.touch, 1);
    expect(r.lightOn(bump.id), isTrue);
  });

  test('a touch sensor drives a light', () {
    final bump = addControl(ControlKind.light, 'Bump');
    syncController();
    final touch = node('sensor.touch', {'port': '1'});
    wire(touch.id, 'pressed', kControllerNodeId, '${bump.id}.on');

    final r = runner();
    expect(r.lightOn(bump.id), isFalse);
    brick.setSensor(1, SensorReading.touch, 1);
    expect(r.lightOn(bump.id), isTrue);
  });

  test('a display shows the slider wired in through Int → String', () {
    final speed = addControl(ControlKind.slider, 'Speed');
    final readout = addControl(ControlKind.display, 'Readout');
    syncController();
    final convert = node('text.fromInt');
    wire(kControllerNodeId, '${speed.id}.value', convert.id, 'number');
    wire(convert.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), '0'); // slider starts at its minimum
    r.sliderChanged(speed.id, 73);
    expect(r.displayValue(readout.id), '73');
  });

  test('append builds a label around a sensor value', () {
    final readout = addControl(ControlKind.display, 'Distance');
    syncController();
    final sensor = node('sensor.distance', {'port': '3'});
    final convert = node('text.fromInt');
    final prefix = node('text.string', {'value': 'Distance: '});
    final append = node('text.append');
    wire(sensor.id, 'distance', convert.id, 'number');
    wire(prefix.id, 'value', append.id, 'a');
    wire(convert.id, 'result', append.id, 'b');
    wire(append.id, 'result', kControllerNodeId, '${readout.id}.value');

    brick.setSensor(3, SensorReading.distanceCm, 40);
    expect(runner().displayValue(readout.id), 'Distance: 40');
  });

  test('pick string chooses by a boolean', () {
    final fast = addControl(ControlKind.toggle, 'Fast');
    final readout = addControl(ControlKind.display, 'Mode');
    syncController();
    final pick = node('text.pick');
    final yes = node('text.string', {'value': 'Turbo!'});
    final no = node('text.string', {'value': 'Slow'});
    wire(kControllerNodeId, '${fast.id}.state', pick.id, 'condition');
    wire(yes.id, 'value', pick.id, 'a');
    wire(no.id, 'value', pick.id, 'b');
    wire(pick.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), 'Slow');
    r.toggleChanged(fast.id, true);
    expect(r.displayValue(readout.id), 'Turbo!');
  });

  test('bool → string says true or false', () {
    final fast = addControl(ControlKind.toggle, 'Fast');
    final readout = addControl(ControlKind.display, 'Mode');
    syncController();
    final convert = node('text.fromBool');
    wire(kControllerNodeId, '${fast.id}.state', convert.id, 'value');
    wire(convert.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), 'false');
    r.toggleChanged(fast.id, true);
    expect(r.displayValue(readout.id), 'true');
  });

  test('power → string is 1 while a button is held (isDown), 0 when not', () {
    final go = addControl(ControlKind.button, 'Go');
    final readout = addControl(ControlKind.display, 'Held');
    syncController();
    final probe = node('text.fromPower');
    wire(kControllerNodeId, '${go.id}.isDown', probe.id, 'power');
    wire(probe.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), '0'); // nothing pressed yet
    r.buttonPressed(go.id);
    expect(r.displayValue(readout.id), '1');
    r.buttonReleased(go.id);
    expect(r.displayValue(readout.id), '0');
  });

  test('power → string follows a held d-pad direction (isDown)', () {
    final drive = addControl(ControlKind.dpad, 'Drive');
    final readout = addControl(ControlKind.display, 'Up?');
    syncController();
    final probe = node('text.fromPower');
    wire(kControllerNodeId, '${drive.id}.upIsDown', probe.id, 'power');
    wire(probe.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), '0');
    r.dpadPressed(drive.id, 'up');
    expect(r.displayValue(readout.id), '1');
    r.dpadReleased(drive.id, 'up');
    expect(r.displayValue(readout.id), '0');
  });

  test('power → string blinks 1 for pulse-only sources', () async {
    final fast = addControl(ControlKind.toggle, 'Fast');
    final readout = addControl(ControlKind.display, 'Blink');
    syncController();
    final probe = node('text.fromPower');
    wire(kControllerNodeId, '${fast.id}.switched', probe.id, 'power');
    wire(probe.id, 'result', kControllerNodeId, '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), '0');
    r.toggleChanged(fast.id, true); // the switch pulse
    expect(r.displayValue(readout.id), '1');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(r.displayValue(readout.id), '0');
    r.dispose();
  });

  test('a display cannot take an int wire directly', () {
    final readout = addControl(ControlKind.display, 'Readout');
    syncController();
    final number = node('value.int', {'value': 9});
    expect(
      graph.canConnect(
        PinRef(number.id, 'value', isOutput: true),
        PinRef(kControllerNodeId, '${readout.id}.value', isOutput: false),
      ),
      isFalse,
    );
  });

  test('an unwired display has no value', () {
    final readout = addControl(ControlKind.display, 'Readout');
    syncController();
    expect(runner().displayValue(readout.id), isNull);
  });

  test('brick sensor updates re-broadcast through the runner', () {
    addControl(ControlKind.light, 'Bump');
    syncController();
    final r = runner();
    var notified = 0;
    r.addListener(() => notified++);
    brick.setSensor(1, SensorReading.touch, 1); // notifies, like a poll update
    expect(notified, 1);
  });

  test('an unwired light is off', () {
    final lamp = addControl(ControlKind.light, 'Lamp');
    syncController();
    expect(runner().lightOn(lamp.id), isFalse);
  });

  test('a data cycle evaluates to defaults instead of hanging', () {
    final go = addControl(ControlKind.button, 'Go');
    syncController();
    final motor = node('motor.run');
    final a1 = node('math.add');
    final a2 = node('math.add');
    wire(a1.id, 'result', a2.id, 'a');
    wire(a2.id, 'result', a1.id, 'a'); // cycle
    wire(a2.id, 'result', motor.id, 'speed');
    wire(kControllerNodeId, '${go.id}.pressed', motor.id, 'run');

    runner().buttonPressed(go.id);
    expect(brick.log, ['Motor A: run at 0% forward']);
  });

  test('slider state starts at its minimum', () {
    final speed = addControl(ControlKind.slider, 'Speed');
    syncController();
    expect(runner().sliderValue(speed.id), 0);
  });

  group('tick model', () {
    test('Every Tick fires power each tick', () {
      final go = addControl(ControlKind.button, 'Go'); // just to have a brick
      syncController();
      final tick = node('event.tick');
      final motor = node('motor.run', {'port': 'A'});
      wire(tick.id, 'tick', motor.id, 'run');
      // Unrelated button so syncController has something; silence unused.
      expect(go.id, isNotEmpty);

      final r = runner();
      expect(brick.log, isEmpty); // nothing runs until the clock ticks
      r.tick();
      expect(brick.log, ['Motor A: run at 100% forward']);
      r.tick(); // identical command deduped — no new log line
      expect(brick.log, hasLength(1));
    });

    test('On Start fires once at start()', () {
      syncController();
      final start = node('event.start');
      final motor = node('motor.run', {'port': 'B'});
      wire(start.id, 'started', motor.id, 'run');

      final r = runner();
      expect(brick.log, isEmpty);
      r.start();
      expect(brick.log, ['Motor B: run at 100% forward']);
      r.start(); // only the first start fires
      expect(brick.log, hasLength(1));
    });

    test('a button held pin powers a motor every tick while held', () {
      final go = addControl(ControlKind.button, 'Go');
      syncController();
      final motor = node('motor.run', {'port': 'A'});
      final stop = node('motor.stop', {'port': 'A'});
      wire(kControllerNodeId, '${go.id}.isDown', motor.id, 'run');
      wire(kControllerNodeId, '${go.id}.released', stop.id, 'stop');

      final r = runner();
      r.tick(); // not held → nothing
      expect(brick.log, isEmpty);

      r.buttonPressed(go.id);
      r.tick();
      expect(brick.log, ['Motor A: run at 100% forward']);
      r.tick(); // still held, deduped
      expect(brick.log, hasLength(1));

      r.buttonReleased(go.id); // released fires stop immediately
      expect(brick.log.last, 'Motor A: stop');
      r.tick();
      expect(brick.log, hasLength(2)); // not held → no more runs
    });

    test('Gate only passes Enter while open', () {
      final open = addControl(ControlKind.button, 'Open');
      final close = addControl(ControlKind.button, 'Close');
      syncController();
      final tick = node('event.tick');
      final gate = node('flow.gate'); // starts closed (default false)
      final motor = node('motor.run', {'port': 'A'});
      wire(tick.id, 'tick', gate.id, 'enter');
      wire(kControllerNodeId, '${open.id}.pressed', gate.id, 'open');
      wire(kControllerNodeId, '${close.id}.pressed', gate.id, 'close');
      wire(gate.id, 'exit', motor.id, 'run');

      final r = runner();
      r.tick();
      expect(brick.log, isEmpty); // closed → blocked

      r.buttonPressed(open.id);
      r.tick();
      expect(brick.log, ['Motor A: run at 100% forward']);

      r.buttonPressed(close.id);
      r.tick();
      r.tick();
      expect(brick.log, hasLength(1)); // closed again → blocked
    });

    test('Gate can start open', () {
      syncController();
      final tick = node('event.tick');
      final gate = node('flow.gate', {'value': true}); // start open
      final motor = node('motor.run', {'port': 'A'});
      wire(tick.id, 'tick', gate.id, 'enter');
      wire(gate.id, 'exit', motor.id, 'run');

      final r = runner();
      r.tick();
      expect(brick.log, ['Motor A: run at 100% forward']);
    });

    test('Do Once passes power one time until reset', () {
      final go = addControl(ControlKind.button, 'Go');
      final rst = addControl(ControlKind.button, 'Reset');
      syncController();
      final doOnce = node('flow.doOnce');
      final seq = node('flow.sequence'); // counts fires via two motors
      final motor = node('motor.run', {'port': 'A'});
      final stop = node('motor.stop', {'port': 'A'});
      wire(kControllerNodeId, '${go.id}.pressed', doOnce.id, 'exec');
      wire(kControllerNodeId, '${rst.id}.pressed', doOnce.id, 'reset');
      // Alternate run/stop so repeated fires would show in the log.
      wire(doOnce.id, 'completed', seq.id, 'exec');
      wire(seq.id, 'then1', motor.id, 'run');
      wire(seq.id, 'then2', stop.id, 'stop');

      final r = runner();
      r.buttonPressed(go.id);
      expect(brick.log, ['Motor A: run at 100% forward', 'Motor A: stop']);
      r.buttonReleased(go.id);
      r.buttonPressed(go.id); // blocked — already fired
      expect(brick.log, hasLength(2));

      r.buttonPressed(rst.id); // reset re-arms it
      r.buttonReleased(go.id);
      r.buttonPressed(go.id);
      expect(brick.log, hasLength(4));
    });

    test('Do N Times passes power N times and exposes its count', () {
      final go = addControl(ControlKind.button, 'Go');
      final count = addControl(ControlKind.display, 'Count');
      syncController();
      final doN = node('flow.doN', {'value': 2});
      final motor = node('motor.run', {'port': 'A'});
      final stop = node('motor.stop', {'port': 'A'});
      final seq = node('flow.sequence');
      final toText = node('text.fromInt');
      wire(kControllerNodeId, '${go.id}.pressed', doN.id, 'exec');
      wire(doN.id, 'exit', seq.id, 'exec');
      wire(seq.id, 'then1', motor.id, 'run');
      wire(seq.id, 'then2', stop.id, 'stop');
      wire(doN.id, 'counter', toText.id, 'number');
      wire(toText.id, 'result', kControllerNodeId, '${count.id}.value');

      final r = runner();
      expect(r.displayValue(count.id), '0');
      r.buttonPressed(go.id);
      r.buttonReleased(go.id);
      r.buttonPressed(go.id);
      r.buttonReleased(go.id);
      r.buttonPressed(go.id); // third press blocked
      expect(brick.log, hasLength(4)); // only two run/stop pairs
      expect(r.displayValue(count.id), '2'); // counter capped at N
    });

    test('Reset Angle zeroes the counter', () {
      final go = addControl(ControlKind.button, 'Go');
      syncController();
      final reset = node('motor.reset', {'port': 'A'});
      wire(kControllerNodeId, '${go.id}.pressed', reset.id, 'reset');

      brick.motorAngles['A'] = 250;
      final r = runner();
      r.buttonPressed(go.id);
      expect(brick.motorAngle('A'), 0);
      expect(brick.log.last, 'Motor A: reset angle');
    });

    test('Turn to Angle drives to an absolute position and holds', () {
      final left = addControl(ControlKind.dpad, 'Steer');
      syncController();
      final toAngle = node('motor.toAngle', {'port': 'A'});
      final target = node('value.int', {'value': 90});
      final speed = node('value.int', {'value': 100});
      wire(kControllerNodeId, '${left.id}.left', toAngle.id, 'run');
      wire(target.id, 'value', toAngle.id, 'angle');
      wire(speed.id, 'value', toAngle.id, 'speed');

      final r = runner();
      r.dpadPressed(left.id, 'left');
      expect(brick.log.last, 'Motor A: turn to 90° at 100%');
      // The sim drives toward the target and brakes there.
      for (var i = 0; i < 60; i++) {
        r.tick();
      }
      expect(brick.motorAngle('A'), 90);
    });

    test('Set writes a variable on power; Get reads it', () {
      final go = addControl(ControlKind.button, 'Go');
      final readout = addControl(ControlKind.display, 'Score');
      syncController();
      final score = variables.create('Score', VarType.integer);
      // Set Score = 42 when Go is pressed.
      final setNode = graph.addDynamicNode(
          varSetDef(score), Offset.zero, {'var': score.id});
      final fortyTwo = node('value.int', {'value': 42});
      wire(kControllerNodeId, '${go.id}.pressed', setNode.id, 'set');
      wire(fortyTwo.id, 'value', setNode.id, 'value');
      // Get Score → display.
      final getNode = graph.addDynamicNode(
          varGetDef(score), Offset.zero, {'var': score.id});
      final toText = node('text.fromInt');
      wire(getNode.id, 'value', toText.id, 'number');
      wire(toText.id, 'result', kControllerNodeId, '${readout.id}.value');

      final r = runner();
      expect(r.displayValue(readout.id), '0'); // default before Set runs
      r.buttonPressed(go.id);
      expect(r.displayValue(readout.id), '42');
    });

    test('a Get without a Set returns the type default', () {
      final readout = addControl(ControlKind.display, 'Score');
      syncController();
      final score = variables.create('Score', VarType.integer);
      final getNode = graph.addDynamicNode(
          varGetDef(score), Offset.zero, {'var': score.id});
      final toText = node('text.fromInt');
      wire(getNode.id, 'value', toText.id, 'number');
      wire(toText.id, 'result', kControllerNodeId, '${readout.id}.value');

      expect(runner().displayValue(readout.id), '0');
    });

    test('steering: a tick loop stops the motor at the angle limit', () {
      syncController();
      // Each tick: if angle < 90 keep turning, else stop.
      final tick = node('event.tick');
      final branch = node('flow.branch');
      final motor = node('motor.run', {'port': 'A'});
      final limit = node('value.int', {'value': 90});
      final less = node('math.less');
      final stop = node('motor.stop', {'port': 'A'});
      final speed = node('value.int', {'value': 100});
      wire(motor.id, 'angle', less.id, 'a');
      wire(limit.id, 'value', less.id, 'b');
      wire(less.id, 'result', branch.id, 'condition');
      wire(tick.id, 'tick', branch.id, 'exec');
      wire(branch.id, 'ifTrue', motor.id, 'run');
      wire(branch.id, 'ifFalse', stop.id, 'stop');
      wire(speed.id, 'value', motor.id, 'speed');

      final r = runner();
      // Tick until the simulated angle crosses the limit.
      for (var i = 0; i < 30; i++) {
        r.tick();
      }
      expect(brick.motorAngle('A'), greaterThanOrEqualTo(90));
      expect(brick.log.last, 'Motor A: stop'); // it stopped itself
    });
  });
}
