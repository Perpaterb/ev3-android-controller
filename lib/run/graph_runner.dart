import 'dart:async';

import 'package:flutter/foundation.dart';

import '../blueprint/model/controller_layout.dart';
import '../blueprint/model/graph.dart';
import '../blueprint/model/pins.dart';
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
    // ignore: prefer_initializing_formals — the field is private.
  }) : _brick = brick {
    _attachBrick();
    for (final tab in layout.tabs) {
      for (final control in tab.controls) {
        switch (control.kind) {
          case ControlKind.slider:
            _controlValues[control.id] =
                (control.config['min'] as num?)?.toInt() ?? 0;
          case ControlKind.toggle:
            _controlValues[control.id] = false;
          default:
            break;
        }
      }
    }
  }

  final BlueprintGraph graph;
  final ControllerLayout layout;

  Ev3Brick _brick;
  Ev3Brick get brick => _brick;

  /// Swappable mid-run: connecting/disconnecting the real brick replaces
  /// this without rebuilding the runner (control state survives).
  set brick(Ev3Brick value) {
    if (identical(value, _brick)) return;
    _detachBrick();
    _brick = value;
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

  /// Per-node runtime state for stateful nodes (Power → String).
  final Map<String, Object> _nodeState = {};

  /// Which momentary controls are currently held: button ids, plus
  /// `<dpadId>.<direction>` entries.
  final Set<String> _held = {};

  /// Decay timers for Power → String pulses from non-held sources.
  final Map<String, Timer> _pulseTimers = {};

  /// Power chains longer than this are cut — a kid can't build an infinite
  /// loop that hangs the app.
  static const int _maxPowerDepth = 64;

  // ---- control state -----------------------------------------------------

  int sliderValue(String controlId) => _controlValues[controlId] as int? ?? 0;

  bool toggleValue(String controlId) => _controlValues[controlId] == true;

  /// Whether a light control should be lit: evaluates whatever is wired
  /// into its `on?` input right now.
  bool lightOn(String controlId) {
    final wire =
        _wireInto(PinRef(kControllerNodeId, '$controlId.on', isOutput: false));
    if (wire == null) return false;
    return _toBool(_evalOutput(wire.from, {}), false);
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

  void toggleChanged(String controlId, bool value) {
    _controlValues[controlId] = value;
    _fireControl('$controlId.switched');
  }

  void _fireControl(String pinId) {
    _firePower(PinRef(kControllerNodeId, pinId, isOutput: true), 0);
    notifyListeners(); // lights and the command log may have changed
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

    switch (node.defId) {
      case 'motor.run':
        brick.runMotor(
          node.config['port'] as String? ?? 'A',
          speed: _toInt(_evalInput(node, 'speed', {}), 100).clamp(0, 100),
          forward: _toBool(_evalInput(node, 'forward', {}), true),
        );
        fire('then');
      case 'motor.stop':
        brick.stopMotor(node.config['port'] as String? ?? 'A');
        fire('then');
      case 'flow.branch':
        fire(_toBool(_evalInput(node, 'condition', {}), false)
            ? 'ifTrue'
            : 'ifFalse');
      case 'flow.sequence':
        fire('then1');
        fire('then2');
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
        'logic.and' => flag('a', false) && flag('b', false),
        'logic.or' => flag('a', false) || flag('b', false),
        'logic.not' => !flag('value', false),
        'motor.run' => brick.motorAngle(node.config['port'] as String? ?? 'A'),
        'sensor.touch' =>
          brick.touchPressed(_portNumber(node.config['port'])),
        'sensor.distance' =>
          brick.distance(_portNumber(node.config['port'])),
        _ => null,
      };
    } finally {
      visiting.remove(key);
    }
  }

  /// "1" if power is flowing into the node, "0" if not. Wired to a held
  /// control (button, d-pad direction) this reads the live held state;
  /// `released` pins read the inverse; pulse-only sources fall back to the
  /// blink state set in [_execute].
  String _powerLevelString(GraphNode node) {
    final wire = _wireInto(PinRef(node.id, 'power', isOutput: false));
    if (wire == null) return '0';
    if (wire.fromNode == kControllerNodeId) {
      final pinId = wire.fromPin;
      final dot = pinId.indexOf('.');
      if (dot > 0) {
        final controlId = pinId.substring(0, dot);
        final capability = pinId.substring(dot + 1);
        switch (capability) {
          case 'pressed':
            return _held.contains(controlId) ? '1' : '0';
          case 'up' || 'down' || 'left' || 'right':
            return _held.contains('$controlId.$capability') ? '1' : '0';
          case 'released': // a button's released pin: inverse of held
            return _held.contains(controlId) ? '0' : '1';
          case _ when capability.endsWith('Released'):
            // A d-pad direction's released pin: inverse of that direction.
            final direction =
                capability.substring(0, capability.length - 'Released'.length);
            return _held.contains('$controlId.$direction') ? '0' : '1';
        }
      }
    }
    return _nodeState[node.id] as String? ?? '0';
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
