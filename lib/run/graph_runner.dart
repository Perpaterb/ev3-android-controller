import 'dart:async';

import 'package:flutter/foundation.dart';

import '../blueprint/model/controller_layout.dart';
import '../blueprint/model/graph.dart';
import '../blueprint/model/pins.dart';
import '../blueprint/model/variables.dart';
import '../services/ev3_brick.dart';

/// Executes a blueprint graph, UE5-style:
///
/// * Controller events (button pressed, slider changed, …) fire *power* out
///   of the controller node's output pins. Power follows its wire to a
///   powered node (motor, branch, sequence), which acts and then fires its
///   own power outputs.
/// * *Data* pins are evaluated on demand, pulled backwards through the
///   graph: pure nodes (math, logic) compute from their inputs, value nodes
///   return their constant, controller pins return live control state, and
///   sensor pins read the brick.
///
/// Unwired data inputs fall back to friendly defaults (speed 100, forward
/// true) so a single wire from a button to a motor "just works".
class GraphRunner extends ChangeNotifier {
  GraphRunner({
    required this.graph,
    required this.layout,
    required Ev3Brick brick,
    this.variables,
    // ignore: prefer_initializing_formals — the field is private.
  }) : _brick = brick {
    _attachBrick();
    for (final v in variables?.variables ?? const <ProjectVariable>[]) {
      _varStore[v.id] = switch (v.type) {
        VarType.integer => 0,
        VarType.boolean => false,
        VarType.text => '',
      };
    }
    for (final tab in layout.tabs) {
      for (final control in tab.controls) {
        switch (control.kind) {
          case ControlKind.slider:
            _controlValues[control.id] = control.sliderDefault;
          case ControlKind.toggle:
            _controlValues[control.id] = false;
          default:
            break;
        }
      }
    }
    // Seed stateful flow nodes from their configured starting state.
    for (final node in graph.nodes) {
      switch (node.defId) {
        case 'flow.gate':
          _gateOpen[node.id] = node.config['value'] == true;
        case 'flow.doOnce':
          _doOnceFired[node.id] = node.config['value'] == true;
        case 'flow.doN':
          _doNCount[node.id] = 0;
      }
    }
  }

  final BlueprintGraph graph;
  final ControllerLayout layout;
  final VariableSet? variables;

  /// Runtime values of project variables, keyed by variable id.
  final Map<String, Object> _varStore = {};

  Ev3Brick _brick;
  Ev3Brick get brick => _brick;

  /// Swappable mid-run: connecting/disconnecting the real brick replaces
  /// this without rebuilding the runner (control state survives).
  set brick(Ev3Brick value) {
    if (identical(value, _brick)) return;
    _detachBrick();
    _brick = value;
    _lastMotorCommand.clear(); // the new brick hasn't heard any command yet
    _attachBrick();
    notifyListeners();
  }

  // Sensor caches changing on the brick must re-render lights and displays,
  // so brick notifications are re-broadcast as runner notifications.
  void _attachBrick() {
    final b = _brick;
    if (b is Listenable) (b as Listenable).addListener(notifyListeners);
  }

  void _detachBrick() {
    final b = _brick;
    if (b is Listenable) (b as Listenable).removeListener(notifyListeners);
  }

  @override
  void dispose() {
    for (final timer in _pulseTimers.values) {
      timer.cancel();
    }
    _detachBrick();
    super.dispose();
  }

  /// Live state of stateful controls: sliderId → int, toggleId → bool.
  final Map<String, Object> _controlValues = {};

  /// Sliders the user currently has a finger on — their physics (spring
  /// return, set-position) are suspended while held.
  final Set<String> _touchingSliders = {};

  /// Per-node runtime state for stateful nodes (Power → String).
  final Map<String, Object> _nodeState = {};

  /// Gate open/closed by node id.
  final Map<String, bool> _gateOpen = {};

  /// Do Once "already fired" flag by node id.
  final Map<String, bool> _doOnceFired = {};

  /// Do N Times counter by node id.
  final Map<String, int> _doNCount = {};

  /// Last motor command sent per port, so a 60 fps tick that keeps firing the
  /// same Run doesn't spam Bluetooth (or the practice log) — only changes go
  /// out.
  final Map<String, String> _lastMotorCommand = {};

  // Motors started by a per-tick source (a "down" pin or Every Tick) run
  // only while that power keeps arriving: each tick records which ports were
  // commanded, and any tick-driven port that goes a tick without power is
  // stopped. A one-shot "touched" Run isn't tick-driven, so it persists.
  bool _inTick = false;
  final Set<String> _tickRunMotors = {};
  final Set<String> _motorsRunThisTick = {};

  /// Which momentary controls are currently held: button ids, plus
  /// `<dpadId>.<direction>` entries.
  final Set<String> _held = {};

  /// Decay timers for Power → String pulses from non-held sources.
  final Map<String, Timer> _pulseTimers = {};

  bool _started = false;

  /// Power chains longer than this are cut — a kid can't build an infinite
  /// loop that hangs the app.
  static const int _maxPowerDepth = 64;

  // ---- control state -----------------------------------------------------

  int sliderValue(String controlId) => _controlValues[controlId] as int? ?? 0;

  bool toggleValue(String controlId) => _controlValues[controlId] == true;

  /// The EV3 colour code (0-7) a light should show, from whatever is wired
  /// into its `colour` input. 0 = off.
  int lightColour(String controlId) {
    final wire = _wireInto(
        PinRef(kControllerNodeId, '$controlId.colour', isOutput: false));
    if (wire == null) return 0;
    return _toInt(_evalOutput(wire.from, {}), 0).clamp(0, 7);
  }

  /// A light's brightness (0-100). Defaults to full when nothing is wired,
  /// so setting just a colour lights it up.
  int lightBrightness(String controlId) {
    final wire = _wireInto(
        PinRef(kControllerNodeId, '$controlId.brightness', isOutput: false));
    if (wire == null) return 100;
    return _toInt(_evalOutput(wire.from, {}), 100).clamp(0, 100);
  }

  /// The text a display control should show: evaluates whatever is wired
  /// into its `value` input right now, or null when nothing is wired.
  /// Tolerant of pre-string saves that wired an int straight in.
  String? displayValue(String controlId) {
    final wire = _wireInto(
        PinRef(kControllerNodeId, '$controlId.value', isOutput: false));
    if (wire == null) return null;
    return _evalOutput(wire.from, {})?.toString();
  }

  // ---- controller events ---------------------------------------------------

  void buttonPressed(String controlId) {
    _held.add(controlId);
    _fireControl('$controlId.pressed');
  }

  void buttonReleased(String controlId) {
    _held.remove(controlId);
    _fireControl('$controlId.released');
  }

  /// [direction] is one of up/down/left/right.
  void dpadPressed(String controlId, String direction) {
    _held.add('$controlId.$direction');
    _fireControl('$controlId.$direction');
  }

  /// Each direction is independent: releasing "left" fires only left's
  /// released pin and never disturbs a direction still being held.
  void dpadReleased(String controlId, String direction) {
    _held.remove('$controlId.$direction');
    _fireControl('$controlId.${direction}Released');
  }

  void sliderChanged(String controlId, int value) {
    _controlValues[controlId] = value;
    _fireControl('$controlId.changed');
  }

  /// The user put a finger on / lifted off a slider. While touched, spring
  /// return and set-position are suspended.
  void sliderTouchStart(String controlId) => _touchingSliders.add(controlId);
  void sliderTouchEnd(String controlId) => _touchingSliders.remove(controlId);
  bool sliderTouched(String controlId) =>
      _touchingSliders.contains(controlId);

  void toggleChanged(String controlId, bool value) {
    _controlValues[controlId] = value;
    _fireControl('$controlId.switched');
  }

  void _fireControl(String pinId) {
    _firePower(PinRef(kControllerNodeId, pinId, isOutput: true), 0);
    notifyListeners(); // lights and the command log may have changed
  }

  // ---- the clock -----------------------------------------------------------

  /// Fires every `On Start` node once. Call when Run mode opens.
  void start() {
    if (_started) return;
    _started = true;
    for (final node in graph.nodes) {
      if (node.defId == 'event.start') {
        _firePower(PinRef(node.id, 'started', isOutput: true), 0);
      }
    }
    notifyListeners();
  }

  /// One frame of the UE5-style game loop: advance the practice simulation,
  /// pour power out of every held control's `held` pin and every `Every
  /// Tick` node, and repaint. Driven by a Ticker in Run mode; called
  /// directly in tests.
  void tick() {
    final b = _brick;
    if (b is MockEv3Brick) b.advanceSimulation();

    _inTick = true;
    _motorsRunThisTick.clear();
    for (final h in _held) {
      // button id (no dot) → `<id>.isDown`; dpad `<id>.<dir>` → `<id>.<dir>IsDown`.
      final pinId = h.contains('.') ? '${h}IsDown' : '$h.isDown';
      _firePower(PinRef(kControllerNodeId, pinId, isOutput: true), 0);
    }
    for (final node in graph.nodes) {
      if (node.defId == 'event.tick') {
        _firePower(PinRef(node.id, 'tick', isOutput: true), 0);
      }
    }
    // Stop any motor that was running from a per-tick source but wasn't
    // commanded this tick (the button was released / the branch flipped).
    for (final port in _tickRunMotors.toList()) {
      if (!_motorsRunThisTick.contains(port)) {
        _sendMotor(port, 'stop', () => brick.stopMotor(port));
        _tickRunMotors.remove(port);
      }
    }
    _tickRunMotors.addAll(_motorsRunThisTick);
    _stepSliderPhysics();
    _inTick = false;
    notifyListeners();
  }

  // ---- slider physics ------------------------------------------------------

  /// Each tick, powered sliders that aren't being touched ease back toward
  /// their home position — linearly (constant speed) or sprung (faster the
  /// further from home).
  void _stepSliderPhysics() {
    for (final tab in layout.tabs) {
      for (final control in tab.controls) {
        if (control.kind != ControlKind.slider) continue;
        if (_touchingSliders.contains(control.id)) continue;
        if (!_sliderPowered(control.id)) continue;

        final home = _sliderHome(control.id);
        final current = sliderValue(control.id);
        final delta = home - current;
        if (delta == 0) continue;

        final strength = _sliderStrength(control.id).clamp(0, 100);
        if (strength == 0) continue;
        final sprung = _sliderSprung(control.id);
        // Linear: a constant step. Sprung: proportional to the distance.
        final raw = sprung
            ? delta.abs() * strength / 100 * 0.3
            : strength * 0.15;
        final step = raw.round().clamp(1, delta.abs());
        _controlValues[control.id] = current + delta.sign * step;
        _firePower(
            PinRef(kControllerNodeId, '${control.id}.changed', isOutput: true),
            0);
      }
    }
  }

  /// Reads a slider setting from its wired pin if present, else its option
  /// default.
  int _sliderHome(String controlId) =>
      _sliderIntSetting(controlId, 'home', (c) => c.sliderHome);
  int _sliderStrength(String controlId) =>
      _sliderIntSetting(controlId, 'strength', (c) => c.sliderStrength);
  bool _sliderPowered(String controlId) =>
      _sliderBoolSetting(controlId, 'powered', (c) => c.sliderPowered);
  bool _sliderSprung(String controlId) =>
      _sliderBoolSetting(controlId, 'sprung', (c) => c.sliderSprung);

  int _sliderIntSetting(
      String controlId, String suffix, int Function(ControllerControl) dflt) {
    final wire = _wireInto(
        PinRef(kControllerNodeId, '$controlId.$suffix', isOutput: false));
    final control = layout.control(controlId);
    final fallback = control == null ? 0 : dflt(control);
    if (wire == null) return fallback;
    return _toInt(_evalOutput(wire.from, {}), fallback);
  }

  bool _sliderBoolSetting(String controlId, String suffix,
      bool Function(ControllerControl) dflt) {
    final wire = _wireInto(
        PinRef(kControllerNodeId, '$controlId.$suffix', isOutput: false));
    final control = layout.control(controlId);
    final fallback = control != null && dflt(control);
    if (wire == null) return fallback;
    return _toBool(_evalOutput(wire.from, {}), fallback);
  }

  // ---- power propagation ---------------------------------------------------

  void _firePower(PinRef output, int depth) {
    if (depth > _maxPowerDepth) return;
    final wire = _wireFrom(output);
    if (wire == null) return;
    final node = graph.node(wire.toNode);
    if (node == null) return;
    _execute(node, wire.toPin, depth + 1);
  }

  void _execute(GraphNode node, String inputPin, int depth) {
    void fire(String outputPin) =>
        _firePower(PinRef(node.id, outputPin, isOutput: true), depth);

    // Power into a slider's "set" pin jumps it to its "set to" value —
    // unless the user is actively holding that slider.
    if (node.id == kControllerNodeId) {
      if (inputPin.endsWith('.setPos')) {
        final controlId =
            inputPin.substring(0, inputPin.length - '.setPos'.length);
        if (!_touchingSliders.contains(controlId)) {
          final target = _sliderIntSetting(controlId, 'setValue',
              (c) => c.sliderHome);
          _controlValues[controlId] = target.clamp(0, 100);
          _firePower(
              PinRef(kControllerNodeId, '$controlId.changed', isOutput: true),
              depth);
        }
      }
      return;
    }

    switch (node.defId) {
      case 'motor.run':
        final port = node.config['port'] as String? ?? 'A';
        final speed = _toInt(_evalInput(node, 'speed', {}), 100).clamp(0, 100);
        final forward = _toBool(_evalInput(node, 'forward', {}), true);
        _sendMotor(port, 'run:$speed:$forward',
            () => brick.runMotor(port, speed: speed, forward: forward));
        if (_inTick) _motorsRunThisTick.add(port);
        fire('then');
      case 'motor.stop':
        final port = node.config['port'] as String? ?? 'A';
        _sendMotor(port, 'stop', () => brick.stopMotor(port));
        fire('then');
      case 'motor.toAngle':
        final port = node.config['port'] as String? ?? 'A';
        final angle = _toInt(_evalInput(node, 'angle', {}), 0);
        final speed = _toInt(_evalInput(node, 'speed', {}), 50).clamp(1, 100);
        _sendMotor(port, 'angle:$angle:$speed',
            () => brick.runToAngle(port, targetAngle: angle, speed: speed));
        fire('then');
      case 'motor.reset':
        final port = node.config['port'] as String? ?? 'A';
        brick.resetAngle(port);
        _lastMotorCommand.remove(port); // let the next command re-issue
        fire('then');
      case 'var.set':
        final varId = node.config['var'] as String? ?? '';
        final value = _evalInput(node, 'value', {});
        if (value != null) _varStore[varId] = value;
        fire('then');
      case 'flow.branch':
        fire(_toBool(_evalInput(node, 'condition', {}), false)
            ? 'ifTrue'
            : 'ifFalse');
      case 'flow.sequence':
        // However many outputs it has grown, in order.
        for (final out in node.def.outputs) {
          fire(out.id);
        }
      case 'flow.gate':
        switch (inputPin) {
          case 'open':
            _gateOpen[node.id] = true;
          case 'close':
            _gateOpen[node.id] = false;
          case 'toggle':
            _gateOpen[node.id] = !(_gateOpen[node.id] ?? false);
          case 'enter':
            if (_gateOpen[node.id] ?? false) fire('exit');
        }
      case 'flow.doOnce':
        if (inputPin == 'reset') {
          _doOnceFired[node.id] = false;
        } else if (!(_doOnceFired[node.id] ?? false)) {
          _doOnceFired[node.id] = true;
          fire('completed');
        }
      case 'flow.doN':
        if (inputPin == 'reset') {
          _doNCount[node.id] = 0;
        } else {
          final limit = node.config['value'] as int? ?? 0;
          final count = _doNCount[node.id] ?? 0;
          if (count < limit) {
            _doNCount[node.id] = count + 1;
            fire('exit');
          }
        }
      case 'text.fromPower':
        // A pulse from a non-held source shows as a short blink of "1".
        _nodeState[node.id] = '1';
        _pulseTimers[node.id]?.cancel();
        _pulseTimers[node.id] =
            Timer(const Duration(milliseconds: 250), () {
          _nodeState[node.id] = '0';
          notifyListeners();
        });
      default:
        // Pure nodes have no power inputs; nothing to do.
        break;
    }
  }

  /// Sends a motor command only when it differs from the last one for that
  /// port — keeps tick-driven Run/Stop from flooding the wire.
  void _sendMotor(String port, String command, VoidCallback send) {
    if (_lastMotorCommand[port] == command) return;
    _lastMotorCommand[port] = command;
    send();
  }

  // ---- data evaluation -----------------------------------------------------

  Object? _evalInput(GraphNode node, String pinId, Set<String> visiting) {
    final wire = _wireInto(PinRef(node.id, pinId, isOutput: false));
    if (wire == null) return null;
    return _evalOutput(wire.from, visiting);
  }

  Object? _evalOutput(PinRef output, Set<String> visiting) {
    final key = '${output.nodeId}.${output.pinId}';
    if (!visiting.add(key)) return null; // data cycle — bail out safely
    try {
      if (output.nodeId == kControllerNodeId) {
        return _evalControllerPin(output.pinId);
      }
      final node = graph.node(output.nodeId);
      if (node == null) return null;

      int input(String pin, int fallback) =>
          _toInt(_evalInput(node, pin, visiting), fallback);
      bool flag(String pin, bool fallback) =>
          _toBool(_evalInput(node, pin, visiting), fallback);
      String str(String pin) {
        final value = _evalInput(node, pin, visiting);
        return value is String ? value : '';
      }

      return switch (node.defId) {
        'value.int' => node.config['value'] as int? ?? 0,
        'value.bool' => node.config['value'] == true,
        'text.string' => node.config['value'] as String? ?? '',
        'text.pick' => flag('condition', false) ? str('a') : str('b'),
        'text.fromInt' => '${input('number', 0)}',
        'text.append' => str('a') + str('b'),
        'text.fromBool' => flag('value', false) ? 'true' : 'false',
        'text.fromPower' => _powerLevelString(node),
        'math.add' => input('a', 0) + input('b', 0),
        'math.subtract' => input('a', 0) - input('b', 0),
        'math.multiply' => input('a', 0) * input('b', 0),
        'math.greater' => input('a', 0) > input('b', 0),
        'math.less' => input('a', 0) < input('b', 0),
        'math.equals' => input('a', 0) == input('b', 0),
        'math.near' =>
          (input('a', 0) - input('b', 0)).abs() <= input('within', 5),
        'logic.and' => flag('a', false) && flag('b', false),
        'logic.or' => flag('a', false) || flag('b', false),
        'logic.not' => !flag('value', false),
        'logic.xor' => flag('a', false) != flag('b', false),
        'logic.same' => flag('a', false) == flag('b', false),
        'logic.nand' => !(flag('a', false) && flag('b', false)),
        'logic.nor' => !(flag('a', false) || flag('b', false)),
        'logic.imply' => !flag('a', false) || flag('b', false),
        'logic.nimply' => flag('a', false) && !flag('b', false),
        'flow.doN' => _doNCount[node.id] ?? 0,
        'var.get' => _varStore[node.config['var'] as String? ?? ''],
        'motor.run' => brick.motorAngle(node.config['port'] as String? ?? 'A'),
        _ when node.defId.startsWith('sensor.') =>
          _readSensorPin(node, output.pinId),
        _ => null,
      };
    } finally {
      visiting.remove(key);
    }
  }

  /// "1" if power is flowing into the node, "0" if not. Wired to a `held`
  /// pin (button or d-pad direction) it reads the live held state; the
  /// one-shot pins (touched, released, changed…) are pulses, so it shows a
  /// short blink of "1" set in [_execute].
  String _powerLevelString(GraphNode node) {
    final wire = _wireInto(PinRef(node.id, 'power', isOutput: false));
    if (wire == null) return '0';
    if (wire.fromNode == kControllerNodeId) {
      final capability = wire.fromPin.split('.').last;
      if (capability == 'isDown') {
        final controlId = wire.fromPin.split('.').first;
        return _held.contains(controlId) ? '1' : '0';
      }
      if (capability.endsWith('IsDown')) {
        // `<id>.<dir>IsDown` → held entry is `<id>.<dir>`.
        final held =
            wire.fromPin.substring(0, wire.fromPin.length - 'IsDown'.length);
        return _held.contains(held) ? '1' : '0';
      }
    }
    return _nodeState[node.id] as String? ?? '0';
  }

  /// Maps a sensor node's output pin to a brick reading. Returns a bool for
  /// the touch pin, an int otherwise.
  Object? _readSensorPin(GraphNode node, String pinId) {
    final port = _portNumber(node.config['port']);
    final reading = switch ('${node.defId}.$pinId') {
      'sensor.touch.pressed' => SensorReading.touch,
      'sensor.colour.colour' => SensorReading.colourId,
      'sensor.colour.reflected' => SensorReading.reflectedLight,
      'sensor.colour.ambient' => SensorReading.ambientLight,
      'sensor.distance.distance' => SensorReading.distanceCm,
      'sensor.gyro.angle' => SensorReading.gyroAngle,
      'sensor.gyro.rate' => SensorReading.gyroRate,
      'sensor.infrared.distance' => SensorReading.irProximity,
      'sensor.infrared.heading' => SensorReading.beaconHeading,
      'sensor.infrared.beacon' => SensorReading.beaconDistance,
      'sensor.sound.level' => SensorReading.soundLevel,
      'sensor.light.reflected' => SensorReading.nxtLightReflected,
      'sensor.light.ambient' => SensorReading.nxtLightAmbient,
      _ => null,
    };
    if (reading == null) return null;
    final value = brick.readSensor(port, reading);
    return reading == SensorReading.touch ? value > 0.5 : value.round();
  }

  Object? _evalControllerPin(String pinId) {
    final dot = pinId.indexOf('.');
    if (dot < 0) return null;
    final controlId = pinId.substring(0, dot);
    return switch (pinId.substring(dot + 1)) {
      'value' => sliderValue(controlId),
      'state' => toggleValue(controlId),
      _ => null,
    };
  }

  // ---- helpers -------------------------------------------------------------

  Wire? _wireInto(PinRef input) =>
      graph.wires.where((w) => w.to == input).firstOrNull;

  Wire? _wireFrom(PinRef output) =>
      graph.wires.where((w) => w.from == output).firstOrNull;

  static int _portNumber(Object? port) =>
      int.tryParse(port as String? ?? '1') ?? 1;

  static int _toInt(Object? value, int fallback) =>
      value is int ? value : fallback;

  static bool _toBool(Object? value, bool fallback) =>
      value is bool ? value : fallback;
}
