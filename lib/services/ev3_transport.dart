import 'dart:typed_data';

/// A byte pipe to an EV3 brick — Bluetooth SPP on Android, an RFCOMM socket
/// on Linux, a scripted fake in tests.
abstract class Ev3Transport {
  /// Opens the connection; throws on failure.
  Future<void> connect();

  void write(Uint8List bytes);

  /// Bytes from the brick. Done/error means the connection dropped.
  Stream<Uint8List> get input;

  Future<void> close();
}

/// A Bluetooth device the user could connect to.
class Ev3Device {
  const Ev3Device({required this.name, required this.address});

  final String name;
  final String address;
}

/// Lists already-paired Bluetooth devices (pairing itself happens in the
/// system settings — much friendlier than reimplementing it).
abstract class Ev3Scanner {
  Future<List<Ev3Device>> pairedDevices();
}
