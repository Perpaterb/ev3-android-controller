import 'package:flutter/foundation.dart';

/// Every kind of value a sensor can report, with the EV3 input *mode* it maps
/// to and a friendly resting value for the practice mock.
///
/// (The EV3 mode numbers follow the LEGO firmware; they may need tuning
/// against real hardware, which hasn't been wired up yet.)
enum SensorReading {
  touch(0, 0), // 0/1 pressed
  reflectedLight(0, 0), // colour sensor reflected, 0-100
  ambientLight(1, 0), // colour sensor ambient, 0-100
  colourId(2, 0), // colour sensor colour, 0-7
  distanceCm(0, 255), // ultrasonic distance
  gyroAngle(0, 0),
  gyroRate(1, 0),
  irProximity(0, 100), // IR proximity 0-100
  beaconHeading(1, 0), // IR beacon heading, -25..25
  beaconDistance(1, 100), // IR beacon distance, 0-100
  soundLevel(0, 0), // NXT sound, 0-100
  nxtLightReflected(0, 0), // NXT light reflected
  nxtLightAmbient(1, 0); // NXT light ambient

  const SensorReading(this.ev3Mode, this.resting);

  /// EV3 input mode index for this reading.
  final int ev3Mode;

  /// Default value when nothing has been read yet.
  final int resting;
}

/// What the app needs from an EV3 brick. Run mode drives this; the real
/// Bluetooth implementation (Epic 2) and the practice-mode mock both
/// implement it.
abstract class Ev3Brick {
  /// [port] is an output port 'A'-'D'; [speed] is 0-100.
  void runMotor(String port, {required int speed, required bool forward});

  void stopMotor(String port);

  /// Safety: kill every motor (leaving Run mode, app backgrounded, …).
  void stopAll();

  /// Drives the motor to an absolute [targetAngle] and brakes there.
  void runToAngle(String port, {required int targetAngle, required int speed});

  /// Zeroes the motor's angle counter, so future angles are measured from
  /// here (a known reference for steering, rotation counting, …).
  void resetAngle(String port);

  int motorAngle(String port);

  /// Reads one value from the sensor on input [port] (1-4).
  num readSensor(int port, SensorReading reading);
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

  /// Injected sensor readings, keyed by (port, reading). Tests and a future
  /// simulator write here; unset readings fall back to the reading's resting
  /// value.
  final Map<(int, SensorReading), num> sensors = {};

  /// Convenience for tests: set a sensor reading.
  void setSensor(int port, SensorReading reading, num value) {
    sensors[(port, reading)] = value;
    notifyListeners();
  }

  @override
  num readSensor(int port, SensorReading reading) =>
      sensors[(port, reading)] ?? reading.resting;

  /// Running motors → signed speed (negative = backward). Drives the sim.
  final Map<String, int> _runningMotors = {};

  /// Motors driving to a target angle → (target, signed speed).
  final Map<String, (int, int)> _motorTargets = {};

  /// Simulated degrees-per-tick at full speed; a real LEGO motor is roughly
  /// in this ballpark at 60 fps.
  static const double _degreesPerTickAtFullSpeed = 0.25;

  void _log(String entry) {
    log.add(entry);
    notifyListeners();
  }

  /// Advances every moving motor's angle one frame's worth.
  void advanceSimulation() {
    if (_runningMotors.isEmpty && _motorTargets.isEmpty) return;
    var changed = false;
    for (final entry in _runningMotors.entries) {
      final step = (entry.value * _degreesPerTickAtFullSpeed).round();
      if (step != 0) {
        motorAngles[entry.key] = (motorAngles[entry.key] ?? 0) + step;
        changed = true;
      }
    }
    for (final port in _motorTargets.keys.toList()) {
      final (target, speed) = _motorTargets[port]!;
      final current = motorAngles[port] ?? 0;
      final step = (speed.abs() * _degreesPerTickAtFullSpeed).round();
      if ((target - current).abs() <= step) {
        motorAngles[port] = target; // arrived; brake and hold
        _motorTargets.remove(port);
      } else {
        motorAngles[port] = current + (target > current ? step : -step);
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void runMotor(String port, {required int speed, required bool forward}) {
    _motorTargets.remove(port);
    _runningMotors[port] = forward ? speed : -speed;
    _log('Motor $port: run at $speed% ${forward ? 'forward' : 'backward'}');
  }

  @override
  void stopMotor(String port) {
    _runningMotors.remove(port);
    _motorTargets.remove(port);
    _log('Motor $port: stop');
  }

  @override
  void stopAll() {
    _runningMotors.clear();
    _motorTargets.clear();
    _log('All motors: stop');
  }

  @override
  void runToAngle(String port,
      {required int targetAngle, required int speed}) {
    _runningMotors.remove(port);
    _motorTargets[port] = (targetAngle, speed);
    _log('Motor $port: turn to $targetAngle° at $speed%');
  }

  @override
  void resetAngle(String port) {
    motorAngles[port] = 0;
    _motorTargets.remove(port);
    _log('Motor $port: reset angle');
  }

  @override
  int motorAngle(String port) => motorAngles[port] ?? 0;
}
