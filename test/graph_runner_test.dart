import 'package:ev3_controller/blueprint/model/controller_layout.dart';
import 'package:ev3_controller/blueprint/model/graph.dart';
import 'package:ev3_controller/blueprint/model/node_def.dart';
import 'package:ev3_controller/blueprint/model/pins.dart';
import 'package:ev3_controller/run/graph_runner.dart';
import 'package:ev3_controller/services/ev3_brick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ControllerLayout layout;
  late BlueprintGraph graph;
  late MockEv3Brick brick;

  setUp(() {
    layout = ControllerLayout();
    graph = BlueprintGraph();
    brick = MockEv3Brick();
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

  GraphRunner runner() =>
      GraphRunner(graph: graph, layout: layout, brick: brick);

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

  test('d-pad directions fire their own pins', () {
    final drive = addControl(ControlKind.dpad, 'Drive');
    syncController();
    final up = node('motor.run', {'port': 'A'});
    final stop = node('motor.stop', {'port': 'A'});
    wire(kControllerNodeId, '${drive.id}.up', up.id, 'run');
    wire(kControllerNodeId, '${drive.id}.released', stop.id, 'stop');

    final r = runner();
    r.dpadPressed(drive.id, 'up');
    r.dpadReleased(drive.id);
    expect(brick.log,
        ['Motor A: run at 100% forward', 'Motor A: stop']);
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
    brick.distanceValues[2] = 80;
    expect(r.lightOn(near.id), isFalse);
    brick.distanceValues[2] = 20;
    expect(r.lightOn(near.id), isTrue);
  });

  test('a touch sensor drives a light', () {
    final bump = addControl(ControlKind.light, 'Bump');
    syncController();
    final touch = node('sensor.touch', {'port': '1'});
    wire(touch.id, 'pressed', kControllerNodeId, '${bump.id}.on');

    final r = runner();
    expect(r.lightOn(bump.id), isFalse);
    brick.touchValues[1] = true;
    expect(r.lightOn(bump.id), isTrue);
  });

  test('a display shows the slider wired into it', () {
    final speed = addControl(ControlKind.slider, 'Speed');
    final readout = addControl(ControlKind.display, 'Readout');
    syncController();
    wire(kControllerNodeId, '${speed.id}.value', kControllerNodeId,
        '${readout.id}.value');

    final r = runner();
    expect(r.displayValue(readout.id), 0); // slider starts at its minimum
    r.sliderChanged(speed.id, 73);
    expect(r.displayValue(readout.id), 73);
  });

  test('a display shows math over a sensor', () {
    final readout = addControl(ControlKind.display, 'Distance');
    syncController();
    final sensor = node('sensor.distance', {'port': '3'});
    final add = node('math.add');
    final offset = node('value.int', {'value': 5});
    wire(sensor.id, 'distance', add.id, 'a');
    wire(offset.id, 'value', add.id, 'b');
    wire(add.id, 'result', kControllerNodeId, '${readout.id}.value');

    brick.distanceValues[3] = 40;
    expect(runner().displayValue(readout.id), 45);
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
    brick.touchValues[1] = true;
    brick.notifyListeners(); // what a sensor cache update does
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
}
