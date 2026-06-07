import 'dart:async';
import 'dart:typed_data';

import 'package:ev3_controller/services/brick_connection.dart';
import 'package:ev3_controller/services/ev3_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class ScriptedTransport implements Ev3Transport {
  ScriptedTransport({this.failOnConnect = false});

  final bool failOnConnect;
  final List<Uint8List> written = [];
  final StreamController<Uint8List> inputController =
      StreamController<Uint8List>.broadcast();

  @override
  Future<void> connect() async {
    if (failOnConnect) throw Exception('out of range');
  }

  @override
  void write(Uint8List bytes) => written.add(bytes);

  @override
  Stream<Uint8List> get input => inputController.stream;

  @override
  Future<void> close() async {
    if (!inputController.isClosed) await inputController.close();
  }
}

class FakeScanner implements Ev3Scanner {
  @override
  Future<List<Ev3Device>> pairedDevices() async =>
      const [Ev3Device(name: 'EV3', address: '00:16:53:00:00:01')];
}

void main() {
  const device = Ev3Device(name: 'EV3', address: '00:16:53:00:00:01');

  test('starts disconnected; unsupported platforms stay that way', () async {
    final connection = BrickConnection();
    expect(connection.supported, isFalse);
    expect(connection.state, BrickConnectionState.disconnected);
    await connection.connect(device); // no factory — politely does nothing
    expect(connection.state, BrickConnectionState.disconnected);
  });

  test('successful connect exposes a live brick', () async {
    late ScriptedTransport transport;
    final connection = BrickConnection(
      transportFactory: (address) => transport = ScriptedTransport(),
      scanner: FakeScanner(),
    );

    await connection.connect(device);
    expect(connection.state, BrickConnectionState.connected);
    expect(connection.deviceName, 'EV3');
    expect(connection.brick, isNotNull);

    connection.brick!.runMotor('A', speed: 50, forward: true);
    expect(transport.written, hasLength(1));
  });

  test('failed connect reverts to disconnected and rethrows', () async {
    final connection = BrickConnection(
      transportFactory: (_) => ScriptedTransport(failOnConnect: true),
      scanner: FakeScanner(),
    );

    await expectLater(connection.connect(device), throwsException);
    expect(connection.state, BrickConnectionState.disconnected);
    expect(connection.brick, isNull);
  });

  test('disconnect stops motors first and clears state', () async {
    late ScriptedTransport transport;
    final connection = BrickConnection(
      transportFactory: (_) => transport = ScriptedTransport(),
      scanner: FakeScanner(),
    );
    await connection.connect(device);

    await connection.disconnect();
    expect(connection.state, BrickConnectionState.disconnected);
    expect(connection.brick, isNull);
    // The last write before closing was the stop-all failsafe.
    expect(transport.written.last[7], 0xA3); // opOUTPUT_STOP
    expect(transport.written.last[9], 0x0F); // all ports
  });

  test('a dropped transport flags connectionWasLost', () async {
    late ScriptedTransport transport;
    final connection = BrickConnection(
      transportFactory: (_) => transport = ScriptedTransport(),
      scanner: FakeScanner(),
    );
    await connection.connect(device);

    await transport.inputController.close(); // brick went away
    await Future<void>.delayed(Duration.zero);

    expect(connection.state, BrickConnectionState.disconnected);
    expect(connection.brick, isNull);
    expect(connection.connectionWasLost, isTrue);

    // Reconnecting clears the lost flag.
    await connection.connect(device);
    expect(connection.connectionWasLost, isFalse);
    expect(connection.state, BrickConnectionState.connected);
  });
}
