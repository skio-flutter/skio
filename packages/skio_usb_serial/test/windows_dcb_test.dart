import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';
import 'package:skio_usb_serial/src/windows/dcb.dart';

void main() {
  group('encodeDcb', () {
    test('8N1 without flow control keeps DTR and RTS as they were', () {
      final on = encodeDcb(const SerialConfig(baudRate: 9600), 0x1011);
      expect(on.flags, 0x1 | 0x10 | 0x1000); // fBinary, DTR on, RTS on
      expect((on.byteSize, on.parity, on.stopBits), (8, 0, 0));

      final off = encodeDcb(const SerialConfig(baudRate: 9600), 0x0001);
      expect(off.flags, 0x1);
    });

    test('explicit DTR and RTS win over the current state', () {
      final f = encodeDcb(
        const SerialConfig(baudRate: 9600, dtr: false, rts: true),
        0x1011,
      );
      expect(f.flags, 0x1 | 0x1000);
    });

    test('a handshake left by another app becomes on', () {
      // DTR handshake (2 << 4), RTS toggle (3 << 12).
      final f = encodeDcb(const SerialConfig(baudRate: 9600), 0x3021);
      expect(f.flags, 0x1 | 0x10 | 0x1000);
    });

    test('RTS/CTS flow control', () {
      final f = encodeDcb(
        const SerialConfig(baudRate: 9600, flowControl: FlowControl.rtsCts),
        0,
      );
      // fBinary, fOutxCtsFlow, RTS handshake.
      expect(f.flags, 0x1 | 0x4 | 0x2000);
    });

    test('DTR/DSR flow control', () {
      final f = encodeDcb(
        const SerialConfig(baudRate: 9600, flowControl: FlowControl.dtrDsr),
        0,
      );
      // fBinary, fOutxDsrFlow, DTR handshake.
      expect(f.flags, 0x1 | 0x8 | 0x20);
    });

    test('XON/XOFF flow control', () {
      final f = encodeDcb(
        const SerialConfig(baudRate: 9600, flowControl: FlowControl.xonXoff),
        0,
      );
      expect(f.flags, 0x1 | 0x100 | 0x200);
    });

    test('parity, data bits and stop bits', () {
      for (final (parity, value) in [
        (Parity.odd, 1),
        (Parity.even, 2),
        (Parity.mark, 3),
        (Parity.space, 4),
      ]) {
        final f = encodeDcb(
          SerialConfig(baudRate: 9600, dataBits: 7, parity: parity),
          0,
        );
        expect(f.parity, value);
        expect(f.byteSize, 7);
        expect(f.flags & 0x2, 0x2, reason: 'fParity');
      }
      expect(
        encodeDcb(
          const SerialConfig(baudRate: 9600, stopBits: StopBits.two),
          0,
        ).stopBits,
        2,
      );
      expect(
        encodeDcb(
          const SerialConfig(
            baudRate: 9600,
            dataBits: 5,
            stopBits: StopBits.onePointFive,
          ),
          0,
        ).stopBits,
        1,
      );
    });
  });

  test('normalizeComPort', () {
    expect(normalizeComPort('COM3'), 'COM3');
    expect(normalizeComPort('com12'), 'COM12');
    expect(normalizeComPort(r'\\.\COM3'), 'COM3');
    expect(normalizeComPort(' COM4 '), 'COM4');
    expect(normalizeComPort('CNCA0'), 'CNCA0');
    expect(normalizeComPort('/dev/ttyS0'), isNull);
    expect(normalizeComPort(r'C:\COM3'), isNull);
    expect(normalizeComPort(''), isNull);
  });
}
