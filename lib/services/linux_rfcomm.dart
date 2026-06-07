import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ev3_transport.dart';

// libc bindings — RFCOMM is just a socket family on Linux, no extra
// libraries needed.
typedef _SocketC = Int32 Function(Int32, Int32, Int32);
typedef _SocketDart = int Function(int, int, int);
typedef _ConnectC = Int32 Function(Int32, Pointer<Uint8>, Uint32);
typedef _ConnectDart = int Function(int, Pointer<Uint8>, int);
typedef _ReadC = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);
typedef _WriteC = IntPtr Function(Int32, Pointer<Uint8>, IntPtr);
typedef _WriteDart = int Function(int, Pointer<Uint8>, int);
typedef _CloseC = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

final DynamicLibrary _libc = DynamicLibrary.process();
final _SocketDart _socket =
    _libc.lookupFunction<_SocketC, _SocketDart>('socket');
final _ConnectDart _connect =
    _libc.lookupFunction<_ConnectC, _ConnectDart>('connect');
final _ReadDart _read = _libc.lookupFunction<_ReadC, _ReadDart>('read');
final _WriteDart _write = _libc.lookupFunction<_WriteC, _WriteDart>('write');
final _CloseDart _close = _libc.lookupFunction<_CloseC, _CloseDart>('close');

const int _afBluetooth = 31;
const int _sockStream = 1;
const int _btprotoRfcomm = 3;
const int _sockaddrRcSize = 10; // u16 family + 6-byte bdaddr + u8 channel (+pad)

/// RFCOMM connection to the EV3 from a Linux desktop. The blocking
/// connect runs in [Isolate.run]; a dedicated reader isolate streams
/// incoming bytes back (file descriptors are process-wide, so the main
/// isolate can keep writing on the same fd).
class LinuxRfcommTransport implements Ev3Transport {
  LinuxRfcommTransport(this.address, {this.channel = 1});

  /// Bluetooth MAC, e.g. `00:16:53:42:2B:99`.
  final String address;
  final int channel;

  int? _fd;
  Isolate? _reader;
  final _input = StreamController<Uint8List>.broadcast();

  @override
  Future<void> connect() async {
    final addr = address;
    final chan = channel;
    _fd = await Isolate.run(() => _connectBlocking(addr, chan));

    final port = ReceivePort();
    _reader = await Isolate.spawn(_readLoop, [_fd!, port.sendPort]);
    port.listen((message) {
      if (message is Uint8List) {
        _input.add(message);
      } else {
        _input.close(); // reader saw EOF/error → connection dropped
      }
    });
  }

  static int _connectBlocking(String address, int channel) {
    final parts =
        address.split(':').map((p) => int.parse(p, radix: 16)).toList();
    if (parts.length != 6) {
      throw FormatException('Bad Bluetooth address: $address');
    }
    final fd = _socket(_afBluetooth, _sockStream, _btprotoRfcomm);
    if (fd < 0) {
      throw const SocketException(
          'Could not create a Bluetooth socket (is Bluetooth on?)');
    }
    final addr = calloc<Uint8>(_sockaddrRcSize);
    try {
      addr[0] = _afBluetooth; // sa_family, little-endian u16
      addr[1] = 0;
      for (var i = 0; i < 6; i++) {
        addr[2 + i] = parts[5 - i]; // bdaddr_t is reversed byte order
      }
      addr[8] = channel;
      final result = _connect(fd, addr, _sockaddrRcSize);
      if (result != 0) {
        _close(fd);
        throw const SocketException(
            'Could not reach the EV3 — is it on and paired?');
      }
      return fd;
    } finally {
      calloc.free(addr);
    }
  }

  static void _readLoop(List<Object> args) {
    final fd = args[0] as int;
    final sendPort = args[1] as SendPort;
    final buffer = calloc<Uint8>(1024);
    try {
      while (true) {
        final n = _read(fd, buffer, 1024);
        if (n <= 0) {
          sendPort.send(null);
          break;
        }
        sendPort.send(Uint8List.fromList(buffer.asTypedList(n)));
      }
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void write(Uint8List bytes) {
    final fd = _fd;
    if (fd == null) return;
    final pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      _write(fd, pointer, bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> close() async {
    final fd = _fd;
    _fd = null;
    if (fd != null) _close(fd); // also unblocks the reader's read()
    _reader?.kill(priority: Isolate.immediate);
    _reader = null;
    if (!_input.isClosed) await _input.close();
  }
}

/// Lists paired devices by asking `bluetoothctl` — present on any Ubuntu
/// machine with BlueZ, and pairing in the system settings is friendlier
/// than reimplementing it.
class BluetoothctlScanner implements Ev3Scanner {
  static final _line =
      RegExp(r'^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$', multiLine: true);

  @override
  Future<List<Ev3Device>> pairedDevices() async {
    // Argument form changed across BlueZ versions; try both.
    for (final args in [
      ['devices', 'Paired'],
      ['paired-devices'],
    ]) {
      try {
        final result = await Process.run('bluetoothctl', args);
        if (result.exitCode != 0) continue;
        final devices = [
          for (final match in _line.allMatches(result.stdout as String))
            Ev3Device(name: match.group(2)!.trim(), address: match.group(1)!),
        ];
        if (devices.isNotEmpty) return devices;
      } on ProcessException {
        break; // bluetoothctl not installed
      }
    }
    return const [];
  }
}
