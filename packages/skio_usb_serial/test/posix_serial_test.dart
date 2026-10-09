// Runs the macOS or Linux backend against a pseudo-terminal pair, which
// behaves like a serial port without any hardware attached.
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';
import 'package:skio_usb_serial/src/linux/usb_serial_linux.dart';
import 'package:skio_usb_serial/src/macos/usb_serial_macos.dart';
import 'package:skio_usb_serial/src/platform/usb_serial_platform.dart';
import 'package:skio_usb_serial/src/posix/libc.dart';

final _lib = DynamicLibrary.process();
final _posixOpenpt = _lib.lookupFunction<Int Function(Int), int Function(int)>(
  'posix_openpt',
);
final _grantpt = _lib.lookupFunction<Int Function(Int), int Function(int)>(
  'grantpt',
);
final _unlockpt = _lib.lookupFunction<Int Function(Int), int Function(int)>(
  'unlockpt',
);
final _ptsname = _lib
    .lookupFunction<Pointer<Utf8> Function(Int), Pointer<Utf8> Function(int)>(
      'ptsname',
    );

/// Opens a pty and returns the master fd and the slave's path. These calls
/// are in libc on both macOS and Linux, unlike openpty.
(int, String) _openPty() {
  final master = _posixOpenpt(Sys.O_RDWR | Sys.O_NOCTTY);
  expect(master, greaterThanOrEqualTo(0));
  expect(_grantpt(master), 0);
  expect(_unlockpt(master), 0);
  return (master, _ptsname(master).toDartString());
}

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
  late UsbSerialPlatform platform;
  late int master;
  late DeviceHandle device;

  setUp(() {
    platform = Platform.isMacOS
        ? MacosUsbSerialPlatform()
        : LinuxUsbSerialPlatform();
    final (fd, path) = _openPty();
    master = fd;
    device = DeviceHandle(id: path);
  });

  tearDown(() => LibC.close(master));

  test('list returns only USB ports', () async {
    for (final port in await platform.list()) {
      expect(port.id, startsWith(Platform.isMacOS ? '/dev/cu.' : '/dev/tty'));
      expect(port.vendorId, isNotNull);
    }
  });

  test('access needs no prompt', () async {
    expect((await platform.checkAccess()).status, AccessStatus.notRequired);
    expect(platform.requiresUserSelection, isFalse);
    // Linux checks the device node's permissions; the pty is ours.
    expect((await platform.checkAccess(device)).isUsable, isTrue);
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
    for (final config in [
      const SerialConfig(baudRate: 9600, dataBits: 7, parity: Parity.even),
      const SerialConfig(baudRate: 57600, stopBits: StopBits.two),
      const SerialConfig(baudRate: 19200, flowControl: FlowControl.xonXoff),
      const SerialConfig(baudRate: 115200, flowControl: FlowControl.rtsCts),
      // Linux supports these through CMSPAR and BOTHER.
      if (Platform.isLinux) ...[
        const SerialConfig(baudRate: 9600, parity: Parity.mark),
        const SerialConfig(baudRate: 9600, parity: Parity.space),
        const SerialConfig(baudRate: 250000),
      ],
    ]) {
      final connection = await platform.open(device, config);
      await connection.close();
    }
  });

  test('rejects settings the system lacks', () async {
    for (final config in [
      if (Platform.isMacOS)
        const SerialConfig(baudRate: 9600, parity: Parity.mark),
      if (Platform.isLinux)
        const SerialConfig(baudRate: 9600, flowControl: FlowControl.dtrDsr),
      const SerialConfig(baudRate: 9600, stopBits: StopBits.onePointFive),
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
