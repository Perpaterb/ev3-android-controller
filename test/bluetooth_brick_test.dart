import 'dart:async';
import 'dart:typed_data';

import 'package:ev3_controller/services/bluetooth_ev3_brick.dart';
import 'package:ev3_controller/services/ev3_brick.dart';
import 'package:ev3_controller/services/ev3_protocol.dart';
import 'package:ev3_controller/services/ev3_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport implements Ev3Transport {
  final List<Uint8List> written = [];
  final StreamController<Uint8List> _input =
      StreamController<Uint8List>.broadcast();
  bool failOnConnect = false;
  bool closed = false;

  @override
  Future<void> connect() async {
    if (failOnConnect) throw Exception('no route to brick');
  }

  @override
  void write(Uint8List bytes) => written.add(bytes);

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> close() async {
    closed = true;
    if (!_input.isClosed) await _input.close();
  }

  /// Replies to the most recent request frame with [payload] (already
  /// including the type byte's data, e.g. 4 float bytes).
  Future<void> reply(List<int> payload) async {
    final request = written.last;
    final counter = request[2] | (request[3] << 8);
    _input.add(Uint8List.fromList([
      payload.length + 3, 0x00,
      counter & 0xFF, (counter >> 8) & 0xFF,
      0x02,
      ...payload,
    ]));
    // Let the stream event get delivered.
    await Future<void>.delayed(Duration.zero);
  }
}

List<int> float32Bytes(double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  late FakeTransport transport;
  late BluetoothEv3Brick brick;
  var lost = false;

  setUp(() {
    transport = FakeTransport();
    lost = false;
    brick = BluetoothEv3Brick(transport, onConnectionLost: () => lost = true);
  });

  tearDown(() {
    brick.dispose();
  });

  test('runMotor writes the protocol frame', () {
    brick.runMotor('B', speed: 42, forward: true);
    expect(transport.written.single,
        Ev3Commands.runMotor(1, 'B', speed: 42, forward: true));
  });

  test('stopAll brakes every output port', () {
    brick.stopAll();
    expect(transport.written.single,
        Ev3Commands.stopMotors(1, Ev3Commands.allOutputsMask));
  });

  test('touch reads are cached and refreshed by polling', () async {
    // marks (port 1, touch) watched
    expect(brick.readSensor(1, SensorReading.touch), 0);

    brick.pollSensors();
    expect(transport.written, hasLength(1));
    expect(transport.written.single[7], 0x99); // opINPUT_DEVICE

    var notified = false;
    brick.addListener(() => notified = true);
    await transport.reply(float32Bytes(1.0)); // pressed
    expect(brick.readSensor(1, SensorReading.touch), 1);
    expect(notified, isTrue);
  });

  test('distance reads round the SI value to centimetres', () async {
    expect(brick.readSensor(2, SensorReading.distanceCm), 255); // default
    brick.pollSensors();
    await transport.reply(float32Bytes(57.4));
    expect(brick.readSensor(2, SensorReading.distanceCm), 57);
  });

  test('motor angle reads the tacho count', () async {
    expect(brick.motorAngle('C'), 0);
    brick.pollSensors();
    expect(transport.written.single.sublist(7),
        [0xB3, 0x00, 0x02, 0x60]);
    final data = ByteData(4)..setInt32(0, 360, Endian.little);
    await transport.reply(data.buffer.asUint8List());
    expect(brick.motorAngle('C'), 360);
  });

  test('unchanged sensor values do not notify', () async {
    brick.readSensor(1, SensorReading.touch);
    var notifications = 0;
    brick.addListener(() => notifications++);

    brick.pollSensors();
    await transport.reply(float32Bytes(0.0)); // still not pressed
    expect(notifications, 0);

    brick.pollSensors();
    await transport.reply(float32Bytes(1.0));
    expect(notifications, 1);
  });

  test('a dropped transport fires onConnectionLost once', () async {
    await transport.close();
    await Future<void>.delayed(Duration.zero);
    expect(lost, isTrue);
  });

  test('commands after a drop are swallowed, not crashes', () async {
    await transport.close();
    await Future<void>.delayed(Duration.zero);
    brick.runMotor('A', speed: 10, forward: true);
    expect(transport.written, isEmpty);
  });
}
