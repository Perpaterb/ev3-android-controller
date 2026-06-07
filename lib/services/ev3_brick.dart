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
class MockEv3Brick extends ChangeNotifier implements Ev3Brick {
  /// Human-readable command log, oldest first.
  final List<String> log = [];

  final Map<String, int> motorAngles = {};
  final Map<int, bool> touchValues = {};
  final Map<int, int> distanceValues = {};

  void _log(String entry) {
    log.add(entry);
    notifyListeners();
  }

  @override
  void runMotor(String port, {required int speed, required bool forward}) =>
      _log('Motor $port: run at $speed% ${forward ? 'forward' : 'backward'}');

  @override
  void stopMotor(String port) => _log('Motor $port: stop');

  @override
  void stopAll() => _log('All motors: stop');

  @override
  int motorAngle(String port) => motorAngles[port] ?? 0;

  @override
  bool touchPressed(int port) => touchValues[port] ?? false;

  @override
  int distance(int port) => distanceValues[port] ?? 255;
}
