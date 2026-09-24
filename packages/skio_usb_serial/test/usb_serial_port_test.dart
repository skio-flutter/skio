import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/platform_interface.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

import 'fake_platform.dart';

void main() {
  const cp2102 = DeviceHandle(id: 'usb-1', vendorId: 0x10c4, productId: 0xea60);
  const ch340 = DeviceHandle(id: 'usb-2', vendorId: 0x1a86, productId: 0x7523);
  const config = SerialConfig(baudRate: 115200);

  late FakeUsbSerialPlatform platform;

  setUp(() {
    platform = FakeUsbSerialPlatform(devices: [cp2102, ch340]);
    UsbSerialPlatform.instance = platform;
  });

  group('list', () {
    test('returns all devices without filters', () async {
      expect(await UsbSerialPort.list(), [cp2102, ch340]);
    });

    test('applies filters', () async {
      expect(
        await UsbSerialPort.list(
          filters: const [DeviceFilter(vendorId: 0x1a86)],
        ),
        [ch340],
      );
    });
  });

  group('open', () {
    test('passes config and exposes device', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      expect(port.device, cp2102);
      expect(platform.opened.single.config, config);
      expect(port.isOpen, isTrue);
    });

    test('rejects invalid config before touching the platform', () async {
      await expectLater(
        UsbSerialPort.open(cp2102, config: const SerialConfig(baudRate: 0)),
        throwsArgumentError,
      );
      expect(platform.opened, isEmpty);
    });

    test('propagates platform errors', () async {
      platform.openError = const DeviceBusy('Port is open elsewhere');
      await expectLater(
        UsbSerialPort.open(cp2102, config: config),
        throwsA(isA<DeviceBusy>()),
      );
    });
  });

  group('input', () {
    test('buffers bytes that arrive before listening', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      platform.opened.single.receive([1, 2]);
      platform.opened.single.receive([3]);
      await pumpEventQueue();
      expect(await port.input.take(2).toList(), [
        [1, 2],
        [3],
      ]);
    });

    test('unplug emits Disconnected, closes the stream and the port', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      final events = <Object>[];
      final done = Completer<void>();
      port.input.listen(events.add, onError: events.add, onDone: done.complete);
      platform.opened.single.receive([0x41]);
      platform.opened.single.unplug();
      await done.future;
      await port.done;
      expect(events.first, [0x41]);
      expect(events.last, isA<Disconnected>());
      expect(port.isOpen, isFalse);
    });
  });

  group('write', () {
    test('writes are sent in call order', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      final c = platform.opened.single..writeGate = Completer<void>();
      final a = port.write([1]);
      final b = port.write([2]);
      c.writeGate!.complete();
      await Future.wait([a, b]);
      expect(c.written, [
        [1],
        [2],
      ]);
    });

    test('a failed write does not block later writes', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      final c = platform.opened.single;
      c.writeGate = Completer<void>()
        ..completeError(
          const OperationTimeout('slow', timeout: Duration(seconds: 1)),
        );
      await expectLater(port.write([1]), throwsA(isA<OperationTimeout>()));
      c.writeGate = null;
      await port.write([2]);
      expect(c.written, [
        [2],
      ]);
    });

    test('after close throws Disconnected', () async {
      final port = await UsbSerialPort.open(cp2102, config: config);
      await port.close();
      expect(() => port.write([1]), throwsA(isA<Disconnected>()));
      expect(() => port.setSignals(dtr: true), throwsA(isA<Disconnected>()));
    });
  });

  test('setSignals forwards values', () async {
    final port = await UsbSerialPort.open(cp2102, config: config);
    await port.setSignals(dtr: false, rts: false);
    expect(platform.opened.single.signals.single, (dtr: false, rts: false));
  });

  test('close completes even if input was never listened to', () async {
    final port = await UsbSerialPort.open(cp2102, config: config);
    platform.opened.single.receive([1]);
    await port.close().timeout(const Duration(seconds: 1));
    await port.done.timeout(const Duration(seconds: 1));
  });

  test('close is idempotent and releases the connection once', () async {
    final port = await UsbSerialPort.open(cp2102, config: config);
    await Future.wait([port.close(), port.close()]);
    await port.close();
    expect(platform.opened.single.closeCount, 1);
    expect(port.isOpen, isFalse);
  });

  test('unsupported platform reports unsupported', () async {
    UsbSerialPlatform.instance = UnsupportedUsbSerialPlatform();
    expect(
      (await UsbSerialPort.access.checkAccess()).status,
      AccessStatus.unsupported,
    );
    expect(await UsbSerialPort.list(), isEmpty);
    await expectLater(UsbSerialPort.request(), throwsA(isA<Unsupported>()));
  });

  test('logs open, TX, RX and close at trace level', () async {
    final records = <LogRecord>[];
    final sub = SkioLog.records.listen(records.add);
    SkioLog.level = LogLevel.trace;
    addTearDown(() async {
      SkioLog.level = LogLevel.off;
      await sub.cancel();
    });
    final port = await UsbSerialPort.open(cp2102, config: config);
    port.input.listen((_) {});
    await port.write([0x41, 0x0a]);
    platform.opened.single.receive([0x4f, 0x4b]);
    await pumpEventQueue();
    await port.close();
    await pumpEventQueue();
    expect(records.map((r) => r.message), [
      'Opened with SerialConfig(115200 8N1, flow: none)',
      'TX 2: 41 0a',
      'RX 2: 4f 4b',
      'Closed',
    ]);
    expect(records.every((r) => r.device == cp2102), isTrue);
  });

  test('works end to end with LineReader', () async {
    final port = await UsbSerialPort.open(cp2102, config: config);
    final lines = port.input.transform(const LineReader()).toList();
    platform.opened.single
      ..receive(utf8.encode('temp=2'))
      ..receive(utf8.encode('1.5\r\nok\n'));
    await pumpEventQueue();
    await port.close();
    expect(await lines, ['temp=21.5', 'ok']);
  });
}
