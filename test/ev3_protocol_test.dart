import 'package:ev3_controller/services/ev3_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runMotor builds a speed+start direct command', () {
    final frame =
        Ev3Commands.runMotor(1, 'B', speed: 50, forward: true);
    expect(frame, [
      0x0D, 0x00, // length 13
      0x01, 0x00, // counter 1
      0x80, // direct command, no reply
      0x00, 0x00, // no variables
      0xA5, 0x00, 0x02, 0x81, 50, // opOUTPUT_SPEED layer 0, port B, LC1(50)
      0xA6, 0x00, 0x02, // opOUTPUT_START layer 0, port B
    ]);
  });

  test('runMotor backward encodes a negative power byte', () {
    final frame =
        Ev3Commands.runMotor(2, 'A', speed: 50, forward: false);
    expect(frame[10], 0x81);
    expect(frame[11], 0xCE); // -50 as a signed byte
  });

  test('stopMotors brakes the given port mask', () {
    final frame = Ev3Commands.stopMotors(3, Ev3Commands.allOutputsMask);
    expect(frame, [
      0x09, 0x00,
      0x03, 0x00,
      0x80,
      0x00, 0x00,
      0xA3, 0x00, 0x0F, 0x01, // opOUTPUT_STOP layer 0, all ports, brake
    ]);
  });

  test('readSensorSi asks for one SI value into global 0', () {
    final frame = Ev3Commands.readSensorSi(4, 2, mode: 0);
    expect(frame, [
      0x0D, 0x00,
      0x04, 0x00,
      0x00, // reply requested
      0x04, 0x00, // 4 global bytes
      0x99, 0x1D, // opINPUT_DEVICE READY_SI
      0x00, 0x01, // layer 0, port index 1 (port "2" on the brick)
      0x00, 0x00, // type: don't change, mode 0
      0x01, 0x60, // one value into GV0(0)
    ]);
  });

  test('readTachoCount reads the motor counter', () {
    final frame = Ev3Commands.readTachoCount(5, 'C');
    expect(frame.sublist(7), [0xB3, 0x00, 0x02, 0x60]);
    expect(frame[4], 0x00); // reply requested
  });

  test('port helpers', () {
    expect(Ev3Commands.outputMask('A'), 1);
    expect(Ev3Commands.outputMask('D'), 8);
    expect(Ev3Commands.outputIndex('C'), 2);
  });

  group('reply parser', () {
    test('parses a float reply split across chunks', () {
      final parser = Ev3ReplyParser();
      // counter 7, ok, float32 1.0
      final frame = [0x07, 0x00, 0x07, 0x00, 0x02, 0x00, 0x00, 0x80, 0x3F];
      expect(parser.addChunk(frame.sublist(0, 4)), isEmpty);
      final replies = parser.addChunk(frame.sublist(4));
      expect(replies, hasLength(1));
      expect(replies.single.counter, 7);
      expect(replies.single.ok, isTrue);
      expect(replies.single.float32, 1.0);
    });

    test('parses two frames arriving in one chunk', () {
      final parser = Ev3ReplyParser();
      final one = [0x07, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00];
      final two = [0x07, 0x00, 0x02, 0x00, 0x02, 0x2A, 0x00, 0x00, 0x00];
      final replies = parser.addChunk([...one, ...two]);
      expect(replies.map((r) => r.counter), [1, 2]);
      expect(replies[1].int32, 42);
    });

    test('flags error replies as not ok', () {
      final parser = Ev3ReplyParser();
      final replies =
          parser.addChunk([0x03, 0x00, 0x09, 0x00, 0x04]); // 0x04 = error
      expect(replies.single.ok, isFalse);
    });
  });
}
