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
typedef _ErrnoC = Pointer<Int32> Function();
typedef _PollC = Int32 Function(Pointer<Uint8>, Uint64, Int32);
typedef _PollDart = int Function(Pointer<Uint8>, int, int);
typedef _GetsockoptC = Int32 Function(
    Int32, Int32, Int32, Pointer<Int32>, Pointer<Uint32>);
typedef _GetsockoptDart = int Function(
    int, int, int, Pointer<Int32>, Pointer<Uint32>);

final DynamicLibrary _libc = DynamicLibrary.process();
final _SocketDart _socket =
    _libc.lookupFunction<_SocketC, _SocketDart>('socket');
final _ConnectDart _connect =
    _libc.lookupFunction<_ConnectC, _ConnectDart>('connect');
final _ReadDart _read = _libc.lookupFunction<_ReadC, _ReadDart>('read');
final _WriteDart _write = _libc.lookupFunction<_WriteC, _WriteDart>('write');
final _CloseDart _close = _libc.lookupFunction<_CloseC, _CloseDart>('close');
final _ErrnoC _errnoLocation =
    _libc.lookupFunction<_ErrnoC, _ErrnoC>('__errno_location');
final _PollDart _poll = _libc.lookupFunction<_PollC, _PollDart>('poll');
final _GetsockoptDart _getsockopt =
    _libc.lookupFunction<_GetsockoptC, _GetsockoptDart>('getsockopt');

int get _errno => _errnoLocation().value;

/// Friendly explanation for the errno values RFCOMM connect tends to return.
String _explainErrno(int errno) => switch (errno) {
      111 => 'the EV3 refused the connection (ECONNREFUSED)',
      112 => 'the EV3 is down or asleep (EHOSTDOWN)',
      113 => "the EV3 couldn't be reached (EHOSTUNREACH)",
      110 => 'the connection timed out (ETIMEDOUT)',
      115 => 'the connection is still in progress (EINPROGRESS)',
      16 => 'the Bluetooth adapter is busy (EBUSY)',
      _ => 'errno $errno',
    };

const int _afBluetooth = 31;
const int _sockStream = 1;
const int _btprotoRfcomm = 3;
const int _sockaddrRcSize = 10; // u16 family + 6-byte bdaddr + u8 channel (+pad)
const int _econnrefused = 111;
const int _eintr = 4; // interrupted syscall
const int _einprogress = 115; // connect in progress; wait via poll
const int _etimedout = 110;
const int _pollout = 0x004;
const int _solSocket = 1;
const int _soError = 4;
const int _connectTimeoutMs = 10000;

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

  static int _connectBlocking(String address, int preferredChannel) {
    final parts =
        address.split(':').map((p) => int.parse(p, radix: 16)).toList();
    if (parts.length != 6) {
      throw FormatException('Bad Bluetooth address: $address');
    }

    // Try the preferred RFCOMM channel first, then scan the low channels:
    // the EV3's Serial Port service isn't always on channel 1. A refusal
    // (ECONNREFUSED) means "reachable, but nothing listening there" → try
    // the next channel; any other error means the brick itself is
    // unreachable, so stop and report it.
    final channels = <int>[
      preferredChannel,
      for (var c = 1; c <= 12; c++)
        if (c != preferredChannel) c,
    ];
    var lastErrno = 0;
    for (final channel in channels) {
      final fd = _socket(_afBluetooth, _sockStream, _btprotoRfcomm);
      if (fd < 0) {
        throw SocketException(
            'Could not create a Bluetooth socket (${_explainErrno(_errno)}) '
            '— is Bluetooth on?');
      }
      final addr = calloc<Uint8>(_sockaddrRcSize);
      try {
        addr[0] = _afBluetooth; // sa_family, little-endian u16
        addr[1] = 0;
        for (var i = 0; i < 6; i++) {
          addr[2 + i] = parts[5 - i]; // bdaddr_t is reversed byte order
        }
        addr[8] = channel;
        lastErrno = _connectFd(fd, addr);
        if (lastErrno == 0) return fd;
      } finally {
        calloc.free(addr);
      }
      _close(fd);
      if (lastErrno != _econnrefused) break; // unreachable → stop scanning
    }
    throw SocketException(
        'Could not reach the EV3 at $address — ${_explainErrno(lastErrno)}. '
        'Make sure it is on and in range, and turn it OFF in your computer\'s '
        'Bluetooth settings so it stops grabbing the connection.');
  }

  /// Connects [fd], returning 0 on success or the failing errno. A blocking
  /// connect interrupted by a VM signal (EINTR) keeps going in the
  /// background — calling connect() again corrupts the socket, so instead we
  /// wait for it to finish with poll() and read the real result from
  /// SO_ERROR. This is the canonical interruptible-connect pattern.
  static int _connectFd(int fd, Pointer<Uint8> addr) {
    final result = _connect(fd, addr, _sockaddrRcSize);
    if (result == 0) return 0;
    final err = _errno;
    if (err != _eintr && err != _einprogress) return err;

    // Wait for the in-progress connect to complete (socket becomes writable).
    final pollfd = calloc<Uint8>(8);
    final view = pollfd.asTypedList(8).buffer.asByteData();
    view.setInt32(0, fd, Endian.host); // pollfd.fd
    view.setInt16(4, _pollout, Endian.host); // pollfd.events
    try {
      // poll() is itself interruptible by VM signals (EINTR) — keep waiting.
      int ready;
      do {
        ready = _poll(pollfd, 1, _connectTimeoutMs);
      } while (ready < 0 && _errno == _eintr);
      if (ready == 0) return _etimedout;
      if (ready < 0) return _errno;
    } finally {
      calloc.free(pollfd);
    }

    // Connect finished — SO_ERROR holds 0 (success) or the real errno.
    final optval = calloc<Int32>();
    final optlen = calloc<Uint32>()..value = 4;
    try {
      if (_getsockopt(fd, _solSocket, _soError, optval, optlen) != 0) {
        return _errno;
      }
      return optval.value;
    } finally {
      calloc.free(optval);
      calloc.free(optlen);
    }
  }

  static void _readLoop(List<Object> args) {
    final fd = args[0] as int;
    final sendPort = args[1] as SendPort;
    final buffer = calloc<Uint8>(1024);
    try {
      while (true) {
        final n = _read(fd, buffer, 1024);
        if (n < 0 && _errno == _eintr) continue; // interrupted — read again
        if (n <= 0) {
          sendPort.send(null); // real EOF / error → connection dropped
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
      // Write the whole buffer, retrying on EINTR and short writes.
      var sent = 0;
      while (sent < bytes.length) {
        final n = _write(fd, pointer + sent, bytes.length - sent);
        if (n < 0) {
          if (_errno == _eintr) continue;
          break; // the connection is gone; the reader will report it
        }
        sent += n;
      }
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
