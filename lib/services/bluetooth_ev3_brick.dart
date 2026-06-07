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

  // Sensor caches and which ports run mode actually asked about.
  final Map<int, bool> _touchCache = {};
  final Map<int, int> _distanceCache = {};
  final Map<String, int> _angleCache = {};
  final Set<int> _watchedTouch = {};
  final Set<int> _watchedDistance = {};
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
  bool touchPressed(int port) {
    _watchedTouch.add(port);
    return _touchCache[port] ?? false;
  }

  @override
  int distance(int port) {
    _watchedDistance.add(port);
    return _distanceCache[port] ?? 255;
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
    // `changed` compares against the same defaults the getters return, so
    // the first reply only notifies when it differs from what callers saw.
    for (final port in _watchedTouch) {
      _request(Ev3Commands.readSensorSi(_nextCounter(), port, mode: 0),
          (reply) {
        final pressed = reply.float32 > 0.5;
        _updateCache(() => _touchCache[port] = pressed,
            changed: (_touchCache[port] ?? false) != pressed);
      });
    }
    for (final port in _watchedDistance) {
      _request(Ev3Commands.readSensorSi(_nextCounter(), port, mode: 0),
          (reply) {
        final cm = reply.float32.round();
        _updateCache(() => _distanceCache[port] = cm,
            changed: (_distanceCache[port] ?? 255) != cm);
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
