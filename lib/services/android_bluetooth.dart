import 'dart:async';

import 'package:flutter/services.dart';

import 'ev3_transport.dart';

const MethodChannel _channel = MethodChannel('bricklogic/bt');
const EventChannel _inputChannel = EventChannel('bricklogic/bt/input');

/// Bluetooth Classic SPP to the EV3 via the Kotlin side of the app
/// (see MainActivity.kt). One connection at a time.
class AndroidBluetoothTransport implements Ev3Transport {
  AndroidBluetoothTransport(this.address);

  final String address;

  @override
  Future<void> connect() async {
    final granted = await _channel.invokeMethod<bool>('ensurePermission');
    if (granted != true) {
      throw Exception('Bluetooth permission not granted');
    }
    await _channel.invokeMethod('connect', {'address': address});
  }

  @override
  void write(Uint8List bytes) {
    _channel.invokeMethod('write', bytes);
  }

  @override
  Stream<Uint8List> get input => _inputChannel
      .receiveBroadcastStream()
      .map((event) => event as Uint8List);

  @override
  Future<void> close() async {
    await _channel.invokeMethod('disconnect');
  }
}

class AndroidBluetoothScanner implements Ev3Scanner {
  @override
  Future<List<Ev3Device>> pairedDevices() async {
    final granted = await _channel.invokeMethod<bool>('ensurePermission');
    if (granted != true) return const [];
    final devices =
        await _channel.invokeListMethod<Map>('bondedDevices') ?? const [];
    return [
      for (final device in devices)
        Ev3Device(
          name: device['name'] as String? ?? 'Unknown',
          address: device['address'] as String,
        ),
    ];
  }
}
