import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/usb_serial_platform.dart';
import 'libc.dart';

/// Ports open in this isolate.
final _openPaths = <String>{};

/// Opens the serial device node named by `device.id` (under `/dev/`), shared
/// by macOS and Linux.
///
/// [configure] applies [SerialConfig]'s line settings to the open descriptor
/// and throws a [HardwareException] if it can't. [accessDenied] is the
/// message for permission errors, which have a different fix on each system.
Future<SerialConnection> openPosixPort(
  DeviceHandle device,
  SerialConfig config, {
  required void Function(int fd) configure,
  required String accessDenied,
}) async {
  if (!device.id.startsWith('/dev/')) {
    throw DeviceNotFound('Not a serial device path.', device: device);
  }
  // TIOCEXCL below keeps other processes out; this covers this app, which
  // some drivers would otherwise let open the port twice.
  if (!_openPaths.add(device.id)) {
    throw DeviceBusy('The port is already open in this app.', device: device);
  }
  try {
    final fd = using(
      (arena) => LibC.open(
        device.id.toNativeUtf8(allocator: arena),
        // Non-blocking so open doesn't wait for carrier detect and the read
        // isolate can be woken to stop.
        Sys.O_RDWR | Sys.O_NOCTTY | Sys.O_NONBLOCK | Sys.O_CLOEXEC,
        0,
      ),
    );
    if (fd < 0) throw _openError(PosixError('open'), device, accessDenied);

    try {
      // Other processes get EBUSY while this one has the port.
      LibC.ioctl(fd, Sys.TIOCEXCL, nullptr);
      configure(fd);
      if (config.dtr != null || config.rts != null) {
        setPosixSignals(fd, device, dtr: config.dtr, rts: config.rts);
      }
      LibC.tcflush(fd, Sys.TCIOFLUSH);
    } catch (_) {
      _closePort(fd);
      rethrow;
    }
    final connection = _PosixSerialConnection(
      fd,
      device,
      onClosed: () => _openPaths.remove(device.id),
    );
    await connection.start();
    return connection;
  } catch (_) {
    _openPaths.remove(device.id);
    rethrow;
  }
}

HardwareException _openError(
  PosixError error,
  DeviceHandle device,
  String accessDenied,
) => switch (error.code) {
  ENOENT || ENXIO || ENODEV => DeviceNotFound(
    'The device is no longer attached.',
    device: device,
    cause: error,
  ),
  EBUSY => DeviceBusy(
    'The port is in use by another app.',
    device: device,
    cause: error,
  ),
  EACCES || EPERM => AccessDenied(accessDenied, device: device, cause: error),
  _ => DeviceBusy(
    'The port could not be opened.',
    device: device,
    cause: error,
  ),
};

/// Clears exclusive mode and closes [fd]. Linux keeps the exclusive flag on
/// a tty that something else still holds open, which would block the next
/// open.
void _closePort(int fd) {
  LibC.ioctl(fd, Sys.TIOCNXCL, nullptr);
  LibC.close(fd);
}

/// Whether this process may read and write the device node at [path].
bool canAccessPath(String path) => using(
  (arena) => LibC.access(path.toNativeUtf8(allocator: arena), R_OK | W_OK) == 0,
);

/// Sets or clears DTR and RTS on [fd]. `null` leaves a line unchanged.
void setPosixSignals(int fd, DeviceHandle device, {bool? dtr, bool? rts}) {
  using((arena) {
    final bits = arena<Int>();
    for (final (on, bit) in [(dtr, TIOCM_DTR), (rts, TIOCM_RTS)]) {
      if (on == null) continue;
      bits.value = bit;
      if (LibC.ioctl(fd, on ? Sys.TIOCMBIS : Sys.TIOCMBIC, bits.cast()) != 0) {
        throw ProtocolError(
          'Could not set signals',
          device: device,
          cause: PosixError('ioctl'),
        );
      }
    }
  });
}

final class _PosixSerialConnection implements SerialConnection {
  _PosixSerialConnection(this._fd, this._device, {required this.onClosed});

  final int _fd;
  final DeviceHandle _device;

  /// Called once the descriptor is closed.
  final void Function() onClosed;
  final _input = StreamController<Uint8List>();
  final _fromReader = ReceivePort('skio_usb_serial reader');
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
        _closePort(_fd);
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
      ), debugName: 'skio_usb_serial reader');
    } catch (e) {
      _fromReader.close();
      _closePort(_fd);
      LibC.close(_wakeRead);
      LibC.close(_wakeWrite);
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
            'The device was disconnected or stopped responding.',
            device: _device,
            cause: error,
          ),
        );
        unawaited(close());
      case null:
        if (!_readerDone.isCompleted) _readerDone.complete();
    }
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
        if (_closed) throw Disconnected('Port is closed', device: _device);
        if (_writable()) {
          final n = LibC.write(_fd, buffer + offset, data.length - offset);
          if (n > 0) {
            offset += n;
            continue;
          }
          if (n < 0) {
            final error = PosixError('write');
            if (error.code != Sys.EAGAIN && error.code != EINTR) {
              throw Disconnected('Write failed', device: _device, cause: error);
            }
          }
        }
        if (DateTime.now().isAfter(deadline)) {
          throw OperationTimeout(
            'The device did not accept data in time',
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
    if (_closed) throw Disconnected('Port is closed', device: _device);
    setPosixSignals(_fd, _device, dtr: dtr, rts: rts);
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
    _closePort(_fd);
    LibC.close(_wakeRead);
    LibC.close(_wakeWrite);
    onClosed();
    unawaited(_input.close());
  }
}

const _readSize = 16 * 1024;

/// Runs in its own isolate: waits for data on [fd] and sends it to the
/// connection until a byte arrives on `wakeFd` or the device goes away.
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
      if ((error.code == Sys.EAGAIN || error.code == EINTR) &&
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
