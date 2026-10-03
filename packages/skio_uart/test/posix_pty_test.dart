// Runs the Linux/Android/macOS backend against a pseudo-terminal pair, which
// behaves like a serial port without any hardware attached.
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:skio_uart/skio_uart.dart';
import 'package:skio_uart/src/backend.dart';
import 'package:skio_uart/src/posix/libc.dart';
import 'package:skio_uart/src/posix/posix_backend.dart';
import 'package:test/test.dart';

typedef _OpenPtyC = Int Function(
  Pointer<Int>,
  Pointer<Int>,
  Pointer<Utf8>,
  Pointer,
  Pointer,
);
typedef _OpenPtyDart = int Function(
  Pointer<Int>,
  Pointer<Int>,
  Pointer<Utf8>,
  Pointer,
  Pointer,
);

// glibc 2.34+ and macOS have openpty in libc; older glibc in libutil.
final _openpty = () {
  try {
    return DynamicLibrary.process().lookupFunction<_OpenPtyC, _OpenPtyDart>(
      'openpty',
    );
  } on ArgumentError {
    return DynamicLibrary.open('libutil.so.1')
        .lookupFunction<_OpenPtyC, _OpenPtyDart>('openpty');
  }
}();

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
  final buffer = malloc<Uint8>(4096);
  final pfd = malloc<PollFd>();
  try {
    while (out.length < count && DateTime.now().isBefore(deadline)) {
      pfd.ref
        ..fd = fd
        ..events = POLLIN
        ..revents = 0;
      if (LibC.poll(pfd, 1, 0) > 0) {
        final n = LibC.read(fd, buffer, 4096);
        if (n > 0) out.addAll(buffer.asTypedList(n));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
  } finally {
    malloc
      ..free(buffer)
      ..free(pfd);
  }
  return out;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late int master;
  late String path;

  setUp(() {
    SerialBackend.instance = PosixBackend();
    final (fd, slave) = _openPty();
    master = fd;
    path = slave;
  });

  tearDown(() {
    if (master >= 0) LibC.close(master);
  });

  test('list does not throw and returns device paths', () async {
    for (final port in await SerialPort.list()) {
      expect(port.id, startsWith('/dev/'));
    }
  });

  test('reads and writes', () async {
    final port = await SerialPort.open(
      path,
      config: const SerialConfig(baudRate: 115200),
    );
    final received = <int>[];
    final sub = port.input.listen(received.addAll);

    _writeMaster(master, utf8.encode('ping\n'));
    await _until(() => received.length >= 5);
    expect(utf8.decode(received), 'ping\n');

    await port.write(utf8.encode('pong\n'));
    expect(utf8.decode(await _readMaster(master, 5)), 'pong\n');

    await port.close();
    await sub.cancel();
  });

  test('a large write arrives in full', () async {
    final port = await SerialPort.open(
      path,
      config: const SerialConfig(baudRate: 115200),
    );
    final data = Uint8List.fromList(List.generate(100000, (i) => i % 251));
    final reading = _readMaster(master, data.length);
    await port.write(data, timeout: const Duration(seconds: 5));
    expect(await reading, data);
    await port.close();
  });

  test('applies line settings', () async {
    for (final config in [
      const SerialConfig(baudRate: 9600, dataBits: 7, parity: Parity.even),
      const SerialConfig(baudRate: 57600, stopBits: StopBits.two),
      const SerialConfig(baudRate: 19200, flowControl: FlowControl.xonXoff),
      const SerialConfig(baudRate: 38400, parity: Parity.odd, dataBits: 5),
      if (Platform.isLinux) ...const [
        // Non-standard rate through BOTHER, and mark/space parity.
        SerialConfig(baudRate: 250000),
        SerialConfig(baudRate: 9600, parity: Parity.mark),
        SerialConfig(baudRate: 9600, parity: Parity.space),
      ],
    ]) {
      final port = await SerialPort.open(path, config: config);
      await port.close();
    }
  });

  test('rejects settings the system lacks', () async {
    await expectLater(
      SerialPort.open(
        path,
        config: const SerialConfig(
          baudRate: 9600,
          stopBits: StopBits.onePointFive,
        ),
      ),
      throwsA(isA<Unsupported>()),
    );
    await expectLater(
      SerialPort.open(
        path,
        config: Platform.isLinux
            ? const SerialConfig(
                baudRate: 9600,
                flowControl: FlowControl.dtrDsr,
              )
            : const SerialConfig(baudRate: 9600, parity: Parity.mark),
      ),
      throwsA(isA<Unsupported>()),
    );
  });

  test('flush and drain work', () async {
    final port = await SerialPort.open(
      path,
      config: const SerialConfig(baudRate: 115200),
    );
    // A pty only empties its output queue as the other end reads it.
    final reading = _readMaster(master, 3);
    await port.write(utf8.encode('abc'));
    await port.drain(timeout: const Duration(seconds: 2));
    expect(utf8.decode(await reading), 'abc');
    await port.flush();
    await port.close();
  });

  test('a second open of the same port is busy', () async {
    const config = SerialConfig(baudRate: 9600);
    final port = await SerialPort.open(path, config: config);
    await expectLater(
      SerialPort.open(path, config: config),
      throwsA(isA<DeviceBusy>()),
    );
    await port.close();
    // Free again after close.
    await (await SerialPort.open(path, config: config)).close();
  });

  test('missing, relative and non-serial paths are reported', () async {
    const config = SerialConfig(baudRate: 9600);
    await expectLater(
      SerialPort.open('/dev/ttySKIO-missing', config: config),
      throwsA(isA<DeviceNotFound>()),
    );
    await expectLater(
      SerialPort.open('ttyS0', config: config),
      throwsA(isA<DeviceNotFound>()),
    );
    await expectLater(
      SerialPort.open('/dev/null', config: config),
      throwsA(isA<ProtocolError>()),
    );
  });

  test('reports Disconnected when the other end goes away', () async {
    final port = await SerialPort.open(
      path,
      config: const SerialConfig(baudRate: 9600),
    );
    final error = Completer<Object>();
    final done = Completer<void>();
    port.input.listen(null, onError: error.complete, onDone: done.complete);
    LibC.close(master);
    master = -1;
    expect(
      await error.future.timeout(const Duration(seconds: 5)),
      isA<Disconnected>(),
    );
    await done.future.timeout(const Duration(seconds: 5));
    expect(port.isOpen, isFalse);
    expect(() => port.write([1]), throwsA(isA<Disconnected>()));
  });

  test('close is idempotent and ends input', () async {
    final port = await SerialPort.open(
      path,
      config: const SerialConfig(baudRate: 9600),
    );
    final done = Completer<void>();
    port.input.listen(null, onDone: done.complete);
    await port.close();
    await port.close();
    await done.future.timeout(const Duration(seconds: 5));
  });
}
