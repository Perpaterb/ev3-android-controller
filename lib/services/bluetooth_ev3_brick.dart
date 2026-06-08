import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ev3_brick.dart';
import 'ev3_protocol.dart';
import 'ev3_transport.dart';

/// A real EV3 brick over a byte transport.
///
/// Motor commands are fire-and-forget. Sensor reads are asynchronous on the
/// wire but the [Ev3Brick] interface is synchronous, so reads come from a
/// cache: the first query for a port marks it watched, a poll loop requests
/// watched values every [pollInterval], and replies update the cache (with a
/// [notifyListeners] so lights re-render).
class BluetoothEv3Brick extends ChangeNotifier implements Ev3Brick {
  BluetoothEv3Brick(
    this._transport, {
    Duration pollInterval = const Duration(milliseconds: 150),
    this.onConnectionLost,
  }) {
    _subscription = _transport.input.listen(
      _onData,
      onError: (_) => _fail(),
      onDone: _fail,
    );
    _pollTimer = Timer.periodic(pollInterval, (_) => pollSensors());
  }

  final Ev3Transport _transport;

  /// Fired once when the transport drops.
  final VoidCallback? onConnectionLost;

  final _parser = Ev3ReplyParser();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _pollTimer;
  int _counter = 0;
  bool _failed = false;

  /// Reply handlers keyed by message counter.
  final Map<int, void Function(Ev3Reply)> _pending = {};

  // Sensor caches and which (port, reading) pairs run mode actually asked
  // about, plus motor angle caches.
  final Map<(int, SensorReading), num> _sensorCache = {};
  final Set<(int, SensorReading)> _watchedSensors = {};
  final Map<String, int> _angleCache = {};
  final Set<String> _watchedAngles = {};

  // ---- Ev3Brick ------------------------------------------------------------

  @override
  void runMotor(String port, {required int speed, required bool forward}) =>
      _send(Ev3Commands.runMotor(_nextCounter(),
          port, speed: speed, forward: forward));

  @override
  void stopMotor(String port) => _send(Ev3Commands.stopMotors(
      _nextCounter(), Ev3Commands.outputMask(port)));

  @override
  void stopAll() => _send(
      Ev3Commands.stopMotors(_nextCounter(), Ev3Commands.allOutputsMask));

  @override
  void runToAngle(String port,
      {required int targetAngle, required int speed}) {
    // EV3 step commands run relative degrees, so aim from the last known
    // angle toward the target.
    final delta = targetAngle - motorAngle(port);
    if (delta == 0) return;
    _send(Ev3Commands.stepDegrees(_nextCounter(), port,
        degrees: delta, speed: speed));
  }

  @override
  void resetAngle(String port) {
    _angleCache[port] = 0;
    _send(Ev3Commands.clearCount(_nextCounter(), Ev3Commands.outputMask(port)));
  }

  @override
  num readSensor(int port, SensorReading reading) {
    _watchedSensors.add((port, reading));
    return _sensorCache[(port, reading)] ?? reading.resting;
  }

  @override
  int motorAngle(String port) {
    _watchedAngles.add(port);
    return _angleCache[port] ?? 0;
  }

  // ---- polling ---------------------------------------------------------------

  /// Requests fresh values for every watched sensor. Called by the poll
  /// timer; public so tests can drive it deterministically.
  void pollSensors() {
    if (_failed || _pending.length > 16) return; // brick stopped answering
    // `changed` compares against the resting default the getter returns, so
    // the first reply only notifies when it differs from what callers saw.
    for (final key in _watchedSensors) {
      final (port, reading) = key;
      _request(
          Ev3Commands.readSensorSi(_nextCounter(), port,
              mode: reading.ev3Mode), (reply) {
        final value = reply.float32.round();
        _updateCache(() => _sensorCache[key] = value,
            changed: (_sensorCache[key] ?? reading.resting) != value);
      });
    }
    for (final port in _watchedAngles) {
      _request(Ev3Commands.readTachoCount(_nextCounter(), port), (reply) {
        final angle = reply.int32;
        _updateCache(() => _angleCache[port] = angle,
            changed: (_angleCache[port] ?? 0) != angle);
      });
    }
  }

  void _updateCache(VoidCallback apply, {required bool changed}) {
    apply();
    if (changed) notifyListeners();
  }

  // ---- wire ------------------------------------------------------------------

  int _nextCounter() => _counter = (_counter + 1) & 0xFFFF;

  void _send(Uint8List frame) {
    if (_failed) return;
    try {
      _transport.write(frame);
    } catch (_) {
      _fail();
    }
  }

  void _request(Uint8List frame, void Function(Ev3Reply) onReply) {
    // Counter bytes live at offset 2-3 of the frame.
    final counter = frame[2] | (frame[3] << 8);
    _pending[counter] = onReply;
    _send(frame);
  }

  void _onData(Uint8List chunk) {
    for (final reply in _parser.addChunk(chunk)) {
      final handler = _pending.remove(reply.counter);
      if (handler != null && reply.ok && reply.data.length >= 4) {
        handler(reply);
      }
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    _pollTimer?.cancel();
    onConnectionLost?.call();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
