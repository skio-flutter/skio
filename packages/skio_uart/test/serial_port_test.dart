import 'dart:async';
import 'dart:convert';

import 'package:skio_uart/skio_uart.dart';
import 'package:skio_uart/src/backend.dart';
import 'package:test/test.dart';

import 'fake_backend.dart';

void main() {
  const ttyS3 = DeviceHandle(id: '/dev/ttyS3', name: 'ttyS3');
  const cp2102 = DeviceHandle(
    id: '/dev/ttyUSB0',
    vendorId: 0x10c4,
    productId: 0xea60,
  );
  const config = SerialConfig(baudRate: 9600);

  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend(ports: [ttyS3, cp2102]);
    SerialBackend.instance = backend;
  });

  group('list', () {
    test('returns all ports without filters', () async {
      expect(await SerialPort.list(), [ttyS3, cp2102]);
    });

    test('applies filters', () async {
      expect(
        await SerialPort.list(filters: const [DeviceFilter(vendorId: 0x10c4)]),
        [cp2102],
      );
    });
  });

  group('open', () {
    test('passes path and config', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      expect(port.path, '/dev/ttyS3');
      expect(port.device.id, '/dev/ttyS3');
      expect(port.device.name, 'ttyS3');
      expect(backend.opened.single.path, '/dev/ttyS3');
      expect(backend.opened.single.config, config);
      expect(port.isOpen, isTrue);
    });

    test('rejects invalid config before touching the backend', () async {
      await expectLater(
        SerialPort.open('/dev/ttyS3', config: const SerialConfig(baudRate: 0)),
        throwsArgumentError,
      );
      expect(backend.opened, isEmpty);
    });

    test('propagates backend errors', () async {
      backend.openError = const AccessDenied('no');
      await expectLater(
        SerialPort.open('/dev/ttyS3', config: config),
        throwsA(isA<AccessDenied>()),
      );
    });
  });

  group('input', () {
    test('buffers bytes that arrive before listening', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      backend.opened.single
        ..receive([1, 2])
        ..receive([3]);
      await pumpEventQueue();
      expect(await port.input.take(2).toList(), [
        [1, 2],
        [3],
      ]);
    });

    test('removal emits Disconnected and closes the port', () async {
      final port = await SerialPort.open('/dev/ttyUSB0', config: config);
      final events = <Object>[];
      final done = Completer<void>();
      port.input.listen(events.add, onError: events.add, onDone: done.complete);
      backend.opened.single
        ..receive([0x41])
        ..unplug();
      await done.future;
      await port.done;
      expect(events.first, [0x41]);
      expect(events.last, isA<Disconnected>());
      expect(port.isOpen, isFalse);
    });

    test('works end to end with LineReader', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      final lines = port.input.transform(const LineReader()).toList();
      backend.opened.single
        ..receive(utf8.encode('P=10'))
        ..receive(utf8.encode('1.3kPa\r\nok\n'));
      await pumpEventQueue();
      await port.close();
      expect(await lines, ['P=101.3kPa', 'ok']);
    });
  });

  group('write', () {
    test('writes are sent in call order', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      final c = backend.opened.single..writeGate = Completer<void>();
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
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      final c = backend.opened.single;
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

    test('drain waits for queued writes first', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      final c = backend.opened.single..writeGate = Completer<void>();
      unawaited(port.write([1]));
      final draining = port.drain();
      await pumpEventQueue();
      expect(c.drains, 0);
      c.writeGate!.complete();
      await draining;
      expect(c.drains, 1);
    });

    test('everything throws Disconnected after close', () async {
      final port = await SerialPort.open('/dev/ttyS3', config: config);
      await port.close();
      expect(() => port.write([1]), throwsA(isA<Disconnected>()));
      expect(() => port.setSignals(dtr: true), throwsA(isA<Disconnected>()));
      expect(port.getSignals, throwsA(isA<Disconnected>()));
      expect(port.flush, throwsA(isA<Disconnected>()));
      expect(port.drain, throwsA(isA<Disconnected>()));
      expect(port.sendBreak, throwsA(isA<Disconnected>()));
    });
  });

  test('forwards signals, flush and break', () async {
    final port = await SerialPort.open('/dev/ttyS3', config: config);
    final c = backend.opened.single;
    await port.setSignals(dtr: false, rts: true);
    expect(c.signals.single, (dtr: false, rts: true));
    expect((await port.getSignals()).cts, isTrue);
    await port.flush(output: false);
    expect(c.flushes.single, (input: true, output: false));
    await port.sendBreak();
    expect(c.breaks.single, const Duration(milliseconds: 250));
  });

  test('close is idempotent and releases the connection once', () async {
    final port = await SerialPort.open('/dev/ttyS3', config: config);
    backend.opened.single.receive([1]);
    await Future.wait([port.close(), port.close()]);
    await port.close();
    await port.done.timeout(const Duration(seconds: 1));
    expect(backend.opened.single.closeCount, 1);
    expect(port.isOpen, isFalse);
  });

  test('unsupported platforms list nothing and refuse to open', () async {
    SerialBackend.instance = UnsupportedBackend();
    expect(await SerialPort.list(), isEmpty);
    await expectLater(
      SerialPort.open('/dev/ttyS0', config: config),
      throwsA(isA<Unsupported>()),
    );
  });

  test('logs open, TX, RX and close', () async {
    final records = <LogRecord>[];
    final sub = SkioLog.records.listen(records.add);
    SkioLog.level = LogLevel.trace;
    addTearDown(() async {
      SkioLog.level = LogLevel.off;
      await sub.cancel();
    });
    final port = await SerialPort.open('/dev/ttyS3', config: config);
    port.input.listen((_) {});
    await port.write([0x41, 0x0a]);
    backend.opened.single.receive([0x4f, 0x4b]);
    await pumpEventQueue();
    await port.close();
    await pumpEventQueue();
    expect(records.map((r) => r.message), [
      'Opened with SerialConfig(9600 8N1, flow: none)',
      'TX 2: 41 0a',
      'RX 2: 4f 4b',
      'Closed',
    ]);
    expect(records.every((r) => r.source == 'skio_uart'), isTrue);
  });
}
