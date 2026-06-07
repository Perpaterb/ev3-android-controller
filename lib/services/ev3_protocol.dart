import 'dart:typed_data';

/// EV3 direct-command protocol: builds command frames and parses reply
/// frames. Pure functions — no IO — so every byte is unit-testable.
///
/// Frame layout (little-endian):
///   [len lo][len hi] [counter lo][counter hi] [type] [vars lo][vars hi] [bytecodes…]
/// where len counts everything after the two length bytes.
///
/// Types: 0x80 = direct command, no reply · 0x00 = direct command, reply
/// requested · replies come back as 0x02 (ok) / 0x04 (error).
class Ev3Commands {
  // Opcodes
  static const int _opOutputSpeed = 0xA5;
  static const int _opOutputStart = 0xA6;
  static const int _opOutputStop = 0xA3;
  static const int _opOutputGetCount = 0xB3;
  static const int _opInputDevice = 0x99;
  static const int _cmdReadySi = 0x1D;

  /// Output-port bitmask for motor opcodes.
  static int outputMask(String port) => switch (port) {
        'A' => 0x01,
        'B' => 0x02,
        'C' => 0x04,
        'D' => 0x08,
        _ => 0x01,
      };

  static const int allOutputsMask = 0x0F;

  /// Output-port index (0-3) for tacho reads.
  static int outputIndex(String port) => switch (port) {
        'A' => 0,
        'B' => 1,
        'C' => 2,
        'D' => 3,
        _ => 0,
      };

  // Parameter encodings.
  static List<int> _lc0(int v) => [v & 0x3F]; // 6-bit immediate
  static List<int> _lc1(int v) => [0x81, v & 0xFF]; // 1-byte follows
  static List<int> _gv0(int index) => [0x60 | (index & 0x1F)]; // global var

  static Uint8List _frame(
    int counter, {
    required bool reply,
    int globalBytes = 0,
    required List<int> bytecodes,
  }) {
    final body = [
      counter & 0xFF,
      (counter >> 8) & 0xFF,
      reply ? 0x00 : 0x80,
      globalBytes & 0xFF,
      (globalBytes >> 8) & 0x03,
      ...bytecodes,
    ];
    return Uint8List.fromList(
        [body.length & 0xFF, (body.length >> 8) & 0xFF, ...body]);
  }

  /// Regulated speed + start, as one no-reply command.
  static Uint8List runMotor(int counter, String port,
      {required int speed, required bool forward}) {
    final mask = outputMask(port);
    final power = (forward ? speed : -speed).clamp(-100, 100);
    return _frame(counter, reply: false, bytecodes: [
      _opOutputSpeed,
      ..._lc0(0), // layer
      ..._lc0(mask),
      ..._lc1(power),
      _opOutputStart,
      ..._lc0(0),
      ..._lc0(mask),
    ]);
  }

  /// Stop with brake. Pass [allOutputsMask] for the stop-everything failsafe.
  static Uint8List stopMotors(int counter, int portMask) {
    return _frame(counter, reply: false, bytecodes: [
      _opOutputStop,
      ..._lc0(0),
      ..._lc0(portMask),
      ..._lc0(1), // brake
    ]);
  }

  /// Reads one sensor value in SI units (reply: float32 in global 0).
  /// [port] is 1-4 as printed on the brick.
  static Uint8List readSensorSi(int counter, int port, {required int mode}) {
    return _frame(counter, reply: true, globalBytes: 4, bytecodes: [
      _opInputDevice,
      _cmdReadySi,
      ..._lc0(0), // layer
      ..._lc0(port - 1),
      ..._lc0(0), // type: don't change
      ..._lc0(mode),
      ..._lc0(1), // one value
      ..._gv0(0),
    ]);
  }

  /// Reads a motor's tacho count (reply: int32 in global 0).
  static Uint8List readTachoCount(int counter, String port) {
    return _frame(counter, reply: true, globalBytes: 4, bytecodes: [
      _opOutputGetCount,
      ..._lc0(0),
      ..._lc0(outputIndex(port)),
      ..._gv0(0),
    ]);
  }
}

/// One parsed reply frame.
class Ev3Reply {
  const Ev3Reply(
      {required this.counter, required this.ok, required this.data});

  final int counter;
  final bool ok;
  final Uint8List data;

  double get float32 =>
      ByteData.sublistView(data).getFloat32(0, Endian.little);

  int get int32 => ByteData.sublistView(data).getInt32(0, Endian.little);
}

/// Reassembles length-prefixed reply frames from an arbitrary byte stream —
/// Bluetooth chunks don't respect frame boundaries.
class Ev3ReplyParser {
  final List<int> _buffer = [];

  List<Ev3Reply> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final replies = <Ev3Reply>[];
    while (_buffer.length >= 2) {
      final length = _buffer[0] | (_buffer[1] << 8);
      if (_buffer.length < length + 2) break;
      final frame = _buffer.sublist(2, 2 + length);
      _buffer.removeRange(0, 2 + length);
      if (frame.length < 3) continue; // malformed; skip
      replies.add(Ev3Reply(
        counter: frame[0] | (frame[1] << 8),
        ok: frame[2] == 0x02,
        data: Uint8List.fromList(frame.sublist(3)),
      ));
    }
    return replies;
  }
}
