import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

void main() {
  test('defaults to 8N1 without flow control', () {
    const c = SerialConfig(baudRate: 9600);
    expect(c.dataBits, 8);
    expect(c.parity, Parity.none);
    expect(c.stopBits, StopBits.one);
    expect(c.flowControl, FlowControl.none);
    expect(c.toString(), 'SerialConfig(9600 8N1, flow: none)');
  });

  test('validate rejects out-of-range values', () {
    expect(
      () => const SerialConfig(baudRate: -1).validate(),
      throwsArgumentError,
    );
    expect(
      () => const SerialConfig(baudRate: 9600, dataBits: 9).validate(),
      throwsArgumentError,
    );
    const SerialConfig(baudRate: 9600, dataBits: 7).validate();
  });

  test('copyWith and equality', () {
    const a = SerialConfig(baudRate: 9600);
    final b = a.copyWith(baudRate: 115200, parity: Parity.even);
    expect(b, const SerialConfig(baudRate: 115200, parity: Parity.even));
    expect(
      b.hashCode,
      const SerialConfig(baudRate: 115200, parity: Parity.even).hashCode,
    );
    expect(a == b, isFalse);
  });
}
