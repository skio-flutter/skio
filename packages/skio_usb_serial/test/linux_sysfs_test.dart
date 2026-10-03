// Lists ports from a fake sysfs tree, so it runs on every OS.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/platform_interface.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';
import 'package:skio_usb_serial/src/linux/usb_serial_linux.dart';

void main() {
  late Directory root;
  late LinuxUsbSerialPlatform platform;

  void file(String path, String content) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('$content\n');

  void dir(String path) =>
      Directory('${root.path}/$path').createSync(recursive: true);

  /// Adds /sys/class/tty/[name] whose `device` link points at [device].
  void tty(String name, String? device) {
    dir('sys/class/tty/$name');
    if (device != null) {
      dir(device);
      Link('${root.path}/sys/class/tty/$name/device')
          .createSync('${root.path}/$device');
    }
  }

  void usbDevice(String path, Map<String, String> files) =>
      files.forEach((name, value) => file('$path/$name', value));

  setUp(() {
    root = Directory.systemTemp.createTempSync('skio_sysfs');
    platform = LinuxUsbSerialPlatform(
      sysClassTty: '${root.path}/sys/class/tty',
    );

    // CH340 adapter with a usb-serial port below its interface.
    usbDevice('sys/devices/usb1/1-1', {
      'idVendor': '1a86',
      'idProduct': '7523',
      'product': 'USB Serial',
    });
    tty('ttyUSB0', 'sys/devices/usb1/1-1/1-1:1.0/ttyUSB0');

    // FT2232: one USB device, two ports.
    usbDevice('sys/devices/usb1/1-2', {
      'idVendor': '0403',
      'idProduct': '6010',
      'product': 'Dual RS232-HS',
      'manufacturer': 'FTDI',
      'serial': 'FT1234',
    });
    tty('ttyUSB1', 'sys/devices/usb1/1-2/1-2:1.0/ttyUSB1');
    tty('ttyUSB2', 'sys/devices/usb1/1-2/1-2:1.1/ttyUSB2');

    // CDC-ACM board without a product string; the tty's device is the
    // interface itself.
    usbDevice('sys/devices/usb1/1-3', {
      'idVendor': '2e8a',
      'idProduct': '000a',
    });
    tty('ttyACM0', 'sys/devices/usb1/1-3/1-3:1.0');

    // Not USB: a built-in UART and a virtual terminal.
    tty('ttyS0', 'sys/devices/platform/serial8250/tty/ttyS0');
    tty('tty0', null);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('lists USB serial ports only, with USB details', () async {
    final ports = await platform.list();
    expect(ports.map((p) => p.id), [
      '/dev/ttyACM0',
      '/dev/ttyUSB0',
      '/dev/ttyUSB1',
      '/dev/ttyUSB2',
    ]);

    final ch340 = ports[1];
    expect(ch340.vendorId, 0x1a86);
    expect(ch340.productId, 0x7523);
    expect(ch340.name, 'USB Serial');
    expect(ch340.serialNumber, isNull);

    expect(ports[2].serialNumber, 'FT1234');
  });

  test('names multi-port adapters by tty and nameless ports by tty', () async {
    final names = [for (final p in await platform.list()) p.name];
    expect(names, [
      'ttyACM0',
      'USB Serial',
      'Dual RS232-HS (ttyUSB1)',
      'Dual RS232-HS (ttyUSB2)',
    ]);
  });

  test('filters by vendor', () async {
    UsbSerialPlatform.instance = platform;
    final ports = await UsbSerialPort.list(
      filters: const [DeviceFilter(vendorId: 0x0403)],
    );
    expect(ports, hasLength(2));
  });

  test('a missing sysfs lists nothing', () async {
    final none = LinuxUsbSerialPlatform(sysClassTty: '${root.path}/nope');
    expect(await none.list(), isEmpty);
  });

  test('has no chooser and rejects settings Linux lacks', () async {
    expect(platform.requiresUserSelection, isFalse);
    await expectLater(platform.request(const []), throwsA(isA<Unsupported>()));
    const device = DeviceHandle(id: '/dev/ttyUSB0');
    for (final config in const [
      SerialConfig(baudRate: 9600, stopBits: StopBits.onePointFive),
      SerialConfig(baudRate: 9600, flowControl: FlowControl.dtrDsr),
    ]) {
      await expectLater(
        platform.open(device, config),
        throwsA(isA<Unsupported>()),
      );
    }
  });
}
