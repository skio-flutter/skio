// Runs the macOS backend against a pseudo-terminal pair, which behaves like a
// serial port without any hardware attached.
@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';
import 'package:skio_usb_serial/src/macos/posix.dart';
import 'package:skio_usb_serial/src/macos/usb_serial_macos.dart';

final _openpty = DynamicLibrary.process()
    .lookupFunction<
      Int Function(Pointer<Int>, Pointer<Int>, Pointer<Utf8>, Pointer, Pointer),
      int Function(Pointer<Int>, Pointer<Int>, Pointer<Utf8>, Pointer, Pointer)
    >('openpty');

/// Opens a pty and returns the master fd and the slave's path.
(int, String) _openPty() => using((arena) {
  final master = arena<Int>();
  final slave = arena<Int>();
  final name = arena<Uint8>(128).cast<Utf8>();
  expect(_openpty(master, slave, name, nullptr, nullptr), 0);
  // The backend opens the slave by path; this copy isn't needed.
  LibC.close(slave.value);
  return (master.value, name.toDartString());
});

void _writeMaster(int fd, List<int> bytes) => using((arena) {
  final buffer = arena<Uint8>(bytes.length)
    ..asTypedList(bytes.length).setAll(0, bytes);
  expect(LibC.write(fd, buffer, bytes.length), bytes.length);
});

Future<List<int>> _readMaster(int fd, int count) async {
  final out = <int>[];
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  final buffer = malloc<Uint8>(256);
  try {
    while (out.length < count && DateTime.now().isBefore(deadline)) {
      final pfd = malloc<PollFd>()
        ..ref.fd = fd
        ..ref.events = POLLIN;
      final ready = LibC.poll(pfd, 1, 0);
      malloc.free(pfd);
      if (ready > 0) {
        final n = LibC.read(fd, buffer, 256);
        if (n > 0) out.addAll(buffer.asTypedList(n));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
  } finally {
    malloc.free(buffer);
  }
  return out;
}

void main() {
  late MacosUsbSerialPlatform platform;
  late int master;
  late DeviceHandle device;

  setUp(() {
    platform = MacosUsbSerialPlatform();
    final (fd, path) = _openPty();
    master = fd;
    device = DeviceHandle(id: path);
  });

  tearDown(() => LibC.close(master));

  test('list returns only USB ports', () async {
    for (final port in await platform.list()) {
      expect(port.id, startsWith('/dev/cu.'));
      expect(port.vendorId, isNotNull);
    }
  });

  test('access is not required', () async {
    expect((await platform.checkAccess()).status, AccessStatus.notRequired);
    expect(platform.requiresUserSelection, isFalse);
  });

  test('reads and writes', () async {
    final connection = await platform.open(
      device,
      const SerialConfig(baudRate: 115200),
    );
    final received = <int>[];
    final sub = connection.input.listen(received.addAll);

    _writeMaster(master, utf8.encode('ping\n'));
    await _until(() => received.length >= 5);
    expect(utf8.decode(received), 'ping\n');

    await connection.write(
      Uint8List.fromList(utf8.encode('pong\n')),
      const Duration(seconds: 1),
    );
    expect(utf8.decode(await _readMaster(master, 5)), 'pong\n');

    await connection.close();
    await sub.cancel();
  });

  test('a large write arrives in full', () async {
    final connection = await platform.open(
      device,
      const SerialConfig(baudRate: 115200),
    );
    final data = Uint8List.fromList(List.generate(100000, (i) => i % 251));
    final reading = _readMaster(master, data.length);
    await connection.write(data, const Duration(seconds: 5));
    expect(await reading, data);
    await connection.close();
  });

  test('applies line settings', () async {
    for (final config in const [
      SerialConfig(baudRate: 9600, dataBits: 7, parity: Parity.even),
      SerialConfig(baudRate: 57600, stopBits: StopBits.two),
      SerialConfig(baudRate: 19200, flowControl: FlowControl.xonXoff),
    ]) {
      final connection = await platform.open(device, config);
      await connection.close();
    }
  });

  test('rejects settings macOS lacks', () async {
    for (final config in const [
      SerialConfig(baudRate: 9600, parity: Parity.mark),
      SerialConfig(baudRate: 9600, stopBits: StopBits.onePointFive),
    ]) {
      await expectLater(
        platform.open(device, config),
        throwsA(isA<Unsupported>()),
      );
    }
  });

  test('a second open of the same port is busy', () async {
    final connection = await platform.open(
      device,
      const SerialConfig(baudRate: 9600),
    );
    await expectLater(
      platform.open(device, const SerialConfig(baudRate: 9600)),
      throwsA(isA<DeviceBusy>()),
    );
    await connection.close();
    // Free again after close.
    await (await platform.open(
      device,
      const SerialConfig(baudRate: 9600),
    )).close();
  });

  test('a missing port is not found', () async {
    await expectLater(
      platform.open(
        const DeviceHandle(id: '/dev/cu.skio-missing'),
        const SerialConfig(baudRate: 9600),
      ),
      throwsA(isA<DeviceNotFound>()),
    );
    await expectLater(
      platform.open(
        const DeviceHandle(id: 'usb-1'),
        const SerialConfig(baudRate: 9600),
      ),
      throwsA(isA<DeviceNotFound>()),
    );
  });

  test('reports Disconnected when the other end goes away', () async {
    final connection = await platform.open(
      device,
      const SerialConfig(baudRate: 9600),
    );
    final error = Completer<Object>();
    final done = Completer<void>();
    connection.input.listen(
      null,
      onError: error.complete,
      onDone: done.complete,
    );
    LibC.close(master);
    master = -1;
    expect(
      await error.future.timeout(const Duration(seconds: 5)),
      isA<Disconnected>(),
    );
    await done.future.timeout(const Duration(seconds: 5));
    await expectLater(
      connection.write(Uint8List(1), const Duration(seconds: 1)),
      throwsA(isA<Disconnected>()),
    );
  });

  test('close is idempotent and ends input', () async {
    final connection = await platform.open(
      device,
      const SerialConfig(baudRate: 9600),
    );
    final done = Completer<void>();
    connection.input.listen(null, onDone: done.complete);
    await connection.close();
    await connection.close();
    await done.future.timeout(const Duration(seconds: 5));
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
