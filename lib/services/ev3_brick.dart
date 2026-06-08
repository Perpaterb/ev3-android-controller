import 'package:flutter/foundation.dart';

/// What the app needs from an EV3 brick. Run mode drives this; the real
/// Bluetooth implementation (Epic 2) and the practice-mode mock both
/// implement it.
abstract class Ev3Brick {
  /// [port] is an output port 'A'-'D'; [speed] is 0-100.
  void runMotor(String port, {required int speed, required bool forward});

  void stopMotor(String port);

  /// Safety: kill every motor (leaving Run mode, app backgrounded, …).
  void stopAll();

  int motorAngle(String port);

  /// [port] is an input port 1-4.
  bool touchPressed(int port);

  /// Distance reading in centimetres.
  int distance(int port);
}

/// Practice-mode brick: logs every command instead of sending it, and lets
/// tests (and later a simulator) inject sensor values.
///
/// It also simulates motor movement: a running motor's angle advances each
/// time [advanceSimulation] is called (driven by the runner's tick), so
/// live-angle logic — like a steering motor that stops at a limit — can be
/// built and tested with no hardware.
class MockEv3Brick extends ChangeNotifier implements Ev3Brick {
  /// Human-readable command log, oldest first.
  final List<String> log = [];

  final Map<String, int> motorAngles = {};
  final Map<int, bool> touchValues = {};
  final Map<int, int> distanceValues = {};

  /// Running motors → signed speed (negative = backward). Drives the sim.
  final Map<String, int> _runningMotors = {};

  /// Simulated degrees-per-tick at full speed; a real LEGO motor is roughly
  /// in this ballpark at 60 fps.
  static const double _degreesPerTickAtFullSpeed = 0.25;

  void _log(String entry) {
    log.add(entry);
    notifyListeners();
  }

  /// Advances every running motor's angle one frame's worth.
  void advanceSimulation() {
    if (_runningMotors.isEmpty) return;
    for (final entry in _runningMotors.entries) {
      final step = (entry.value * _degreesPerTickAtFullSpeed).round();
      if (step != 0) {
        motorAngles[entry.key] = (motorAngles[entry.key] ?? 0) + step;
      }
    }
    notifyListeners();
  }

  @override
  void runMotor(String port, {required int speed, required bool forward}) {
    _runningMotors[port] = forward ? speed : -speed;
    _log('Motor $port: run at $speed% ${forward ? 'forward' : 'backward'}');
  }

  @override
  void stopMotor(String port) {
    _runningMotors.remove(port);
    _log('Motor $port: stop');
  }

  @override
  void stopAll() {
    _runningMotors.clear();
    _log('All motors: stop');
  }

  @override
  int motorAngle(String port) => motorAngles[port] ?? 0;

  @override
  bool touchPressed(int port) => touchValues[port] ?? false;

  @override
  int distance(int port) => distanceValues[port] ?? 255;
}
