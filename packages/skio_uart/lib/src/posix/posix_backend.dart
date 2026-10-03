import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../backend.dart';
import 'darwin_ports.dart';
import 'libc.dart';
import 'linux_ports.dart';
import 'tty.dart';

/// [SerialBackend] for Linux, Android and macOS: opens device nodes such as
/// `/dev/ttyS3` and talks to them with termios, all through `dart:ffi`.
final class PosixBackend extends SerialBackend {
  /// Creates the POSIX backend.
  PosixBackend();

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  @override
  Future<List<DeviceHandle>> list() async =>
      isLinuxKernel ? listLinuxPorts() : listDarwinPorts();

  @override
  Stream<DeviceEvent> get events => pollDeviceEvents(list, pollInterval);

  /// Ports open in this isolate, by resolved path.
  static final _openPaths = <String>{};

  @override
  Future<SerialConnection> open(String path, SerialConfig config) async {
    final device = DeviceHandle(id: path, name: path.split('/').last);
    if (!path.startsWith('/')) {
      throw DeviceNotFound(
        'Serial port paths start with /dev/, for example /dev/ttyS3.',
        device: device,
      );
    }
    Tty.current.check(config, device);
    // TIOCEXCL below keeps other apps out; this covers this app, which root
    // could otherwise open twice. Symlinks such as /dev/serial/by-id/... are
    // resolved so they count as the same port.
    final key = _resolve(path);
    if (!_openPaths.add(key)) {
      throw DeviceBusy('$path is already open in this app.', device: device);
    }
    try {
      return await _open(
        path,
        config,
        device,
        onClosed: () {
          _openPaths.remove(key);
        },
      );
    } catch (_) {
      _openPaths.remove(key);
      rethrow;
    }
  }

  static String _resolve(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }

  Future<SerialConnection> _open(
    String path,
    SerialConfig config,
    DeviceHandle device, {
    required void Function() onClosed,
  }) async {
    final fd = using(
      (arena) => LibC.open(
        path.toNativeUtf8(allocator: arena),
        // Non-blocking so open doesn't wait for carrier detect and the read
        // isolate can be woken to stop.
        O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC,
        0,
      ),
    );
    if (fd < 0) throw _openError(PosixError('open'), path, device);

    try {
      // Other apps get EBUSY while this one has the port.
      LibC.ioctl(fd, TIOCEXCL, nullptr);
      Tty.current.configure(fd, config, device);
      if (config.dtr != null || config.rts != null) {
        _setSignals(fd, device, dtr: config.dtr, rts: config.rts);
      }
      Tty.current.flush(fd, input: true, output: true);
    } catch (_) {
      LibC.close(fd);
      rethrow;
    }
    final connection = _PosixConnection(fd, device, onClosed: onClosed);
    await connection.start();
    return connection;
  }

  static HardwareException _openError(
    PosixError error,
    String path,
    DeviceHandle device,
  ) => switch (error.code) {
    ENOENT || ENXIO || ENODEV => DeviceNotFound(
      'There is no serial port at $path.',
      device: device,
      cause: error,
    ),
    EBUSY => DeviceBusy(
      '$path is in use by another app.',
      device: device,
      cause: error,
    ),
    EACCES ||
    EPERM => AccessDenied(_accessHint(path), device: device, cause: error),
    _ => ProtocolError('Could not open $path.', device: device, cause: error),
  };

  static String _accessHint(String path) {
    if (Platform.isAndroid) {
      return 'Android refused access to $path. The device\'s system image '
          'must let apps open it: check with `adb shell ls -lZ $path`, and '
          'ask the panel maker for a build that allows it.';
    }
    if (Platform.isLinux) {
      return 'Permission denied for $path. Add your user to the dialout '
          'group (sudo usermod -aG dialout \$USER), then log out and in.';
    }
    return 'macOS refused access to $path. Sandboxed apps need the '
        'com.apple.security.device.serial entitlement.';
  }
}

void _setSignals(int fd, DeviceHandle device, {bool? dtr, bool? rts}) {
  using((arena) {
    final bits = arena<Int>();
    for (final (on, bit) in [(dtr, TIOCM_DTR), (rts, TIOCM_RTS)]) {
      if (on == null) continue;
      bits.value = bit;
      if (LibC.ioctl(fd, on ? TIOCMBIS : TIOCMBIC, bits.cast()) != 0) {
        throw ProtocolError(
          'This port has no DTR/RTS lines.',
          device: device,
          cause: PosixError('ioctl(TIOCMBIS)'),
        );
      }
    }
  });
}

final class _PosixConnection implements SerialConnection {
  _PosixConnection(this._fd, this._device, {required this.onClosed});

  final int _fd;
  final DeviceHandle _device;

  /// Called once the descriptor is closed.
  final void Function() onClosed;
  final _input = StreamController<Uint8List>();
  final _fromReader = ReceivePort('skio_uart reader');
  final _readerDone = Completer<void>();
  Isolate? _reader;
  late final int _wakeRead;
  late final int _wakeWrite;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _input.stream;

  Future<void> start() async {
    using((arena) {
      final fds = arena<Int>(2);
      if (LibC.pipe(fds) != 0) {
        LibC.close(_fd);
        onClosed();
        throw ProtocolError(
          'Could not start reading',
          device: _device,
          cause: PosixError('pipe'),
        );
      }
      _wakeRead = fds[0];
      _wakeWrite = fds[1];
    });
    _fromReader.listen(_onReaderMessage);
    try {
      _reader = await Isolate.spawn(_readLoop, (
        _fromReader.sendPort,
        _fd,
        _wakeRead,
      ), debugName: 'skio_uart reader');
    } catch (e) {
      _fromReader.close();
      for (final fd in [_fd, _wakeRead, _wakeWrite]) {
        LibC.close(fd);
      }
      onClosed();
      throw ProtocolError('Could not start reading', device: _device, cause: e);
    }
  }

  void _onReaderMessage(Object? message) {
    switch (message) {
      case final TransferableTypedData data:
        if (!_closed) _input.add(data.materialize().asUint8List());
      case final String error:
        if (_closed) return;
        _input.addError(
          Disconnected(
            'The port was removed or stopped responding.',
            device: _device,
            cause: error,
          ),
        );
        unawaited(close());
      case null:
        if (!_readerDone.isCompleted) _readerDone.complete();
    }
  }

  void _ensureOpen() {
    if (_closed) throw Disconnected('Port is closed', device: _device);
  }

  /// Writes from this isolate with non-blocking `write` calls, waiting
  /// briefly whenever the driver's buffer is full.
  @override
  Future<void> write(Uint8List data, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final buffer = malloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      var offset = 0;
      while (offset < data.length) {
        _ensureOpen();
        if (_writable()) {
          final n = LibC.write(_fd, buffer + offset, data.length - offset);
          if (n > 0) {
            offset += n;
            continue;
          }
          if (n < 0) {
            final error = PosixError('write');
            if (error.code != EAGAIN && error.code != EINTR) {
              throw Disconnected('Write failed', device: _device, cause: error);
            }
          }
        }
        if (DateTime.now().isAfter(deadline)) {
          throw OperationTimeout(
            'The port did not accept data in time. Check the flow control '
            'setting and the CTS line.',
            timeout: timeout,
            device: _device,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    } finally {
      malloc.free(buffer);
    }
  }

  /// Whether a write would make progress now. Hang-ups and errors count as
  /// writable so the `write` call reports them.
  bool _writable() => using((arena) {
    final pfd = arena<PollFd>()
      ..ref.fd = _fd
      ..ref.events = POLLOUT;
    return LibC.poll(pfd, 1, 0) > 0;
  });

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    _ensureOpen();
    _setSignals(_fd, _device, dtr: dtr, rts: rts);
  }

  @override
  Future<ModemStatus> getSignals() async {
    _ensureOpen();
    return using((arena) {
      final bits = arena<Int>();
      if (LibC.ioctl(_fd, TIOCMGET, bits.cast()) != 0) {
        throw ProtocolError(
          'This port has no modem status lines.',
          device: _device,
          cause: PosixError('ioctl(TIOCMGET)'),
        );
      }
      final b = bits.value;
      return ModemStatus(
        cts: b & TIOCM_CTS != 0,
        dsr: b & TIOCM_DSR != 0,
        dcd: b & TIOCM_CAR != 0,
        ri: b & TIOCM_RNG != 0,
      );
    });
  }

  @override
  Future<void> flush({required bool input, required bool output}) async {
    _ensureOpen();
    if (!input && !output) return;
    if (Tty.current.flush(_fd, input: input, output: output) != 0) {
      throw ProtocolError(
        'Could not flush the port.',
        device: _device,
        cause: PosixError('flush'),
      );
    }
  }

  @override
  Future<void> drain(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    // Wait for the kernel's buffer without blocking this isolate...
    while (true) {
      _ensureOpen();
      final queued = using((arena) {
        final count = arena<Int>();
        return LibC.ioctl(_fd, TIOCOUTQ, count.cast()) == 0 ? count.value : 0;
      });
      if (queued == 0) break;
      if (DateTime.now().isAfter(deadline)) {
        throw OperationTimeout(
          'The port did not finish sending in time.',
          timeout: timeout,
          device: _device,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    // ...then for the last bytes in the UART's FIFO, which takes at most a
    // few milliseconds, on a helper isolate because the call blocks.
    await _drainHardware(_fd);
  }

  @override
  Future<void> sendBreak(Duration duration) async {
    _ensureOpen();
    if (LibC.ioctl(_fd, TIOCSBRK, nullptr) != 0) {
      throw ProtocolError(
        'This port cannot send a break.',
        device: _device,
        cause: PosixError('ioctl(TIOCSBRK)'),
      );
    }
    try {
      await Future<void>.delayed(duration);
    } finally {
      if (!_closed) LibC.ioctl(_fd, TIOCCBRK, nullptr);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Wake the reader and wait for it to stop polling before the descriptor
    // is closed, so it can't read from a reused descriptor number.
    using((arena) => LibC.write(_wakeWrite, arena<Uint8>(), 1));
    await _readerDone.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _reader?.kill(priority: Isolate.immediate),
    );
    _fromReader.close();
    LibC.close(_fd);
    LibC.close(_wakeRead);
    LibC.close(_wakeWrite);
    onClosed();
    unawaited(_input.close());
  }
}

/// Blocks a helper isolate until the hardware has sent everything. Top
/// level so the closure captures only [fd].
Future<int> _drainHardware(int fd) => Isolate.run(
  () => LibC.ioctl(fd, TCDRAIN_IOCTL, Pointer.fromAddress(1)),
  debugName: 'skio_uart drain',
);

const _readSize = 16 * 1024;

/// Runs in its own isolate: waits for data on [fd] and sends it to the
/// connection until a byte arrives on `wakeFd` or the port goes away.
///
/// Sends [TransferableTypedData] for data, a [String] for a fatal error, and
/// `null` when it stops.
void _readLoop((SendPort, int, int) args) {
  final (port, fd, wakeFd) = args;
  final fds = calloc<PollFd>(2);
  final buffer = calloc<Uint8>(_readSize);
  try {
    while (true) {
      fds[0]
        ..fd = fd
        ..events = POLLIN
        ..revents = 0;
      fds[1]
        ..fd = wakeFd
        ..events = POLLIN
        ..revents = 0;
      if (LibC.poll(fds, 2, -1) < 0) {
        final error = PosixError('poll');
        if (error.code == EINTR) continue;
        port.send(error.toString());
        return;
      }
      if (fds[1].revents != 0) return;

      final revents = fds[0].revents;
      if (revents & POLLNVAL != 0) {
        port.send('poll: invalid descriptor');
        return;
      }
      if (revents & (POLLIN | POLLHUP | POLLERR) == 0) continue;
      final n = LibC.read(fd, buffer, _readSize);
      if (n > 0) {
        port.send(
          // fromList copies, so the buffer can be reused.
          TransferableTypedData.fromList([buffer.asTypedList(n)]),
        );
        continue;
      }
      if (n == 0) {
        port.send('read: end of file');
        return;
      }
      final error = PosixError('read');
      // A hang-up with nothing to read would spin forever; treat it as gone.
      if ((error.code == EAGAIN || error.code == EINTR) &&
          revents & POLLHUP == 0) {
        continue;
      }
      port.send(error.toString());
      return;
    }
  } finally {
    calloc
      ..free(fds)
      ..free(buffer);
    port.send(null);
  }
}
