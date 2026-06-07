import 'dart:io';

import 'package:flutter/foundation.dart';

import 'android_bluetooth.dart';
import 'bluetooth_ev3_brick.dart';
import 'ev3_transport.dart';
import 'linux_rfcomm.dart';

enum BrickConnectionState { disconnected, connecting, connected }

typedef TransportFactory = Ev3Transport Function(String address);

/// Owns the (single) live connection to an EV3. The whole app shares one of
/// these; Run mode reads [brick] and falls back to practice mode when it's
/// null.
class BrickConnection extends ChangeNotifier {
  BrickConnection({this.transportFactory, this.scanner});

  /// Platform pieces; both null on platforms without Bluetooth support,
  /// which keeps the app in practice mode.
  final TransportFactory? transportFactory;
  final Ev3Scanner? scanner;

  bool get supported => transportFactory != null && scanner != null;

  BrickConnectionState get state => _state;
  BrickConnectionState _state = BrickConnectionState.disconnected;

  String? get deviceName => _deviceName;
  String? _deviceName;

  BluetoothEv3Brick? get brick => _brick;
  BluetoothEv3Brick? _brick;
  Ev3Transport? _transport;

  /// True once after an unexpected drop, until the next connect attempt —
  /// lets the UI tell "lost the robot" apart from "never connected".
  bool get connectionWasLost => _connectionWasLost;
  bool _connectionWasLost = false;

  Future<void> connect(Ev3Device device) async {
    final factory = transportFactory;
    if (factory == null) return;
    await disconnect();
    _connectionWasLost = false;
    _state = BrickConnectionState.connecting;
    _deviceName = device.name;
    notifyListeners();
    try {
      final transport = factory(device.address);
      await transport.connect();
      _transport = transport;
      _brick = BluetoothEv3Brick(transport, onConnectionLost: _onLost);
      _state = BrickConnectionState.connected;
      notifyListeners();
    } catch (e) {
      _state = BrickConnectionState.disconnected;
      _deviceName = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (_brick == null && _transport == null) return;
    try {
      _brick?.stopAll(); // never leave motors running behind us
    } catch (_) {}
    await _teardown();
    _state = BrickConnectionState.disconnected;
    _deviceName = null;
    notifyListeners();
  }

  void _onLost() {
    _connectionWasLost = true;
    _teardown();
    _state = BrickConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> _teardown() async {
    final brick = _brick;
    final transport = _transport;
    _brick = null;
    _transport = null;
    brick?.dispose();
    try {
      await transport?.close();
    } catch (_) {}
  }
}

/// Builds the connection for whatever platform we're running on.
BrickConnection createPlatformBrickConnection() {
  if (kIsWeb) return BrickConnection();
  if (Platform.isAndroid) {
    return BrickConnection(
      transportFactory: AndroidBluetoothTransport.new,
      scanner: AndroidBluetoothScanner(),
    );
  }
  if (Platform.isLinux) {
    return BrickConnection(
      transportFactory: LinuxRfcommTransport.new,
      scanner: BluetoothctlScanner(),
    );
  }
  return BrickConnection();
}
