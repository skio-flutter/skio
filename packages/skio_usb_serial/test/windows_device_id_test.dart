// Parses the IDs and names Windows reports for COM ports. Plain Dart, so it
// runs on every OS.
import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/src/windows/dcb.dart';
import 'package:skio_usb_serial/src/windows/device_id.dart';

void main() {
  group('parseUsbInstanceId', () {
    test('CH340 without a serial number', () {
      final ids = parseUsbInstanceId(r'USB\VID_1A86&PID_7523\5&2B5B5E1&0&2');
      expect(ids, (vendorId: 0x1a86, productId: 0x7523, serialNumber: null));
    });

    test('a device with a serial number', () {
      final ids = parseUsbInstanceId(r'USB\VID_10C4&PID_EA60\0001');
      expect(ids, (vendorId: 0x10c4, productId: 0xea60, serialNumber: '0001'));
    });

    test("FTDI's own driver", () {
      final ids = parseUsbInstanceId(
        r'FTDIBUS\VID_0403+PID_6001+A50285BIA\0000',
      );
      expect(ids, (
        vendorId: 0x0403,
        productId: 0x6001,
        serialNumber: 'A50285BIA',
      ));
    });

    test('an interface of a composite device has no serial of its own', () {
      const id = r'USB\VID_303A&PID_1001&MI_00\6&1D3A2B&0&0000';
      expect(isInterfaceId(id), isTrue);
      expect(parseUsbInstanceId(id), (
        vendorId: 0x303a,
        productId: 0x1001,
        serialNumber: null,
      ));
      // The parent carries it.
      expect(
        parseUsbInstanceId(r'USB\VID_303A&PID_1001\DC:54:75:C1:2A:30')
            ?.serialNumber,
        'DC:54:75:C1:2A:30',
      );
    });

    test('lower-case IDs', () {
      expect(parseUsbInstanceId(r'usb\vid_2e8a&pid_000a\e6614c311b1f9a2c'), (
        vendorId: 0x2e8a,
        productId: 0x000a,
        serialNumber: 'e6614c311b1f9a2c',
      ));
    });

    test('ports that are not on USB', () {
      expect(parseUsbInstanceId(r'ACPI\PNP0501\1'), isNull);
      expect(
        parseUsbInstanceId(
          r'BTHENUM\{00001101-0000-1000-8000-00805F9B34FB}_LOCALMFG&0002\7&1C',
        ),
        isNull,
      );
    });

    test('a plain device is not an interface', () {
      expect(isInterfaceId(r'USB\VID_1A86&PID_7523\5&2B5B5E1&0&2'), isFalse);
    });
  });

  group('trimPortSuffix', () {
    test('drops the port Windows adds', () {
      expect(
        trimPortSuffix('USB-SERIAL CH340 (COM3)', 'COM3'),
        'USB-SERIAL CH340',
      );
      expect(
        trimPortSuffix(
          'Silicon Labs CP210x USB to UART Bridge (COM12)',
          'COM12',
        ),
        'Silicon Labs CP210x USB to UART Bridge',
      );
    });

    test('keeps names without it', () {
      expect(trimPortSuffix('USB Serial Device', 'COM4'), 'USB Serial Device');
      expect(trimPortSuffix('Device (COM5)', 'COM4'), 'Device (COM5)');
    });
  });

  group('normalizeComPort', () {
    test('accepts COM names in any form', () {
      expect(normalizeComPort('COM3'), 'COM3');
      expect(normalizeComPort('com3'), 'COM3');
      expect(normalizeComPort(r'\\.\COM12'), 'COM12');
    });

    test('rejects paths that are not device names', () {
      expect(normalizeComPort('/dev/ttyUSB0'), isNull);
      expect(normalizeComPort(r'C:\file.txt'), isNull);
      expect(normalizeComPort(''), isNull);
    });
  });
}
