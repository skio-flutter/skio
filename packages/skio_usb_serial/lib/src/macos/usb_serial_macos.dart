import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/device_poller.dart';
import '../platform/usb_serial_platform.dart';
import '../serial_config.dart';
import 'iokit.dart';
import 'posix.dart';

/// [UsbSerialPlatform] for macOS: lists ports through IOKit and talks to
/// `/dev/cu.*` with POSIX termios, all through `dart:ffi`.
///
/// Sandboxed apps need the `com.apple.security.device.serial` entitlement.
final class MacosUsbSerialPlatform extends UsbSerialPlatform {
  /// Creates the macOS platform.
  MacosUsbSerialPlatform();

  /// Registers this implementation. Called by Flutter's plugin registrant.
  static void registerWith() {
    UsbSerialPlatform.instance = MacosUsbSerialPlatform();
  }

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  @override
  bool get requiresUserSelection => false;

  // ---------------------------------------------------------------- access

  // macOS has no per-device USB permission. Sandboxed apps get access from
  // an entitlement at build time, which can't be checked or requested here.
  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<bool> openSettings() async => false;

  // ----------------------------------------------------------- discovery

  /// USB serial ports. Built-in ports such as `Bluetooth-Incoming-Port` are
  /// left out.
  @override
  Future<List<DeviceHandle>> list() async => [
    for (final port in listSerialPorts())
      if (port.vendorId != null)
        DeviceHandle(
          id: port.calloutPath,
          name: port.productName ?? port.calloutPath.split('/').last,
          vendorId: port.vendorId,
          productId: port.productId,
          serialNumber: port.serialNumber,
        ),
  ];

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(
        'macOS has no port chooser. Use UsbSerialPort.list().',
      );

  @override
  Stream<DeviceEvent> get events => pollDeviceEvents(list, pollInterval);

  // ---------------------------------------------------------------- open

  /// Opens the device node named by `device.id`, which must be under `/dev/`.
  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    if (config.parity case Parity.mark || Parity.space) {
      throw Unsupported(
        'macOS does not support ${config.parity.name} parity.',
        device: device,
      );
    }
    if (config.stopBits == StopBits.onePointFive) {
      throw Unsupported(
        'macOS does not support 1.5 stop bits.',
        device: device,
      );
    }
    if (!device.id.startsWith('/dev/')) {
      throw DeviceNotFound('Not a serial device path.', device: device);
    }
    // TIOCEXCL below keeps other processes out; this covers this app, which
    // some drivers would otherwise let open the port twice.
    if (!_openPaths.add(device.id)) {
      throw DeviceBusy('The port is already open in this app.', device: device);
    }
    try {
      return await _open(device, config);
    } catch (_) {
      _openPaths.remove(device.id);
      rethrow;
    }
  }

  /// Ports open in this isolate.
  static final _openPaths = <String>{};

  Future<SerialConnection> _open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    final fd = using(
      (arena) => LibC.open(
        device.id.toNativeUtf8(allocator: arena),
        // Non-blocking so open doesn't wait for carrier detect and the read
        // isolate can be woken to stop.
        O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC,
        0,
      ),
    );
    if (fd < 0) throw _openError(PosixError('open'), device);

    try {
      // Other processes get EBUSY while this one has the port.
      LibC.ioctl(fd, TIOCEXCL, nullptr);
      _configure(fd, config, device);
      if (config.dtr != null || config.rts != null) {
        _setSignals(fd, device, dtr: config.dtr, rts: config.rts);
      }
      LibC.tcflush(fd, TCIOFLUSH);
    } catch (_) {
      LibC.close(fd);
      rethrow;
    }
    final connection = _MacosSerialConnection(
      fd,
      device,
      onClosed: () => _openPaths.remove(device.id),
    );
    await connection.start();
    return connection;
  }

  static HardwareException _openError(PosixError error, DeviceHandle device) =>
      switch (error.code) {
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
        EACCES || EPERM => AccessDenied(
          'macOS refused access to the port. Sandboxed apps need the '
          'com.apple.security.device.serial entitlement.',
          device: device,
          cause: error,
        ),
        _ => DeviceBusy(
          'The port could not be opened.',
          device: device,
          cause: error,
        ),
      };

  static void _configure(int fd, SerialConfig config, DeviceHandle device) {
    using((arena) {
      final t = arena<Termios>();
      if (LibC.tcgetattr(fd, t) != 0) {
        throw ProtocolError(
          'Could not read the port settings.',
          device: device,
          cause: PosixError('tcgetattr'),
        );
      }
      LibC.cfmakeraw(t);
      final termios = t.ref;

      var cflag =
          termios.c_cflag &
          ~(CSIZE |
              CSTOPB |
              PARENB |
              PARODD |
              CCTS_OFLOW |
              CRTS_IFLOW |
              CDTR_IFLOW |
              CDSR_OFLOW);
      cflag |= CREAD | CLOCAL;
      cflag |= switch (config.dataBits) {
        5 => CS5,
        6 => CS6,
        7 => CS7,
        _ => CS8,
      };
      if (config.stopBits == StopBits.two) cflag |= CSTOPB;
      cflag |= switch (config.parity) {
        Parity.odd => PARENB | PARODD,
        Parity.even => PARENB,
        _ => 0,
      };
      cflag |= switch (config.flowControl) {
        FlowControl.rtsCts => CCTS_OFLOW | CRTS_IFLOW,
        FlowControl.dtrDsr => CDTR_IFLOW | CDSR_OFLOW,
        _ => 0,
      };
      termios.c_cflag = cflag;

      var iflag = termios.c_iflag & ~(IXON | IXOFF | IXANY);
      if (config.flowControl == FlowControl.xonXoff) iflag |= IXON | IXOFF;
      termios.c_iflag = iflag;

      termios.c_cc[VMIN] = 0;
      termios.c_cc[VTIME] = 0;

      // termios only takes the standard rates; others are set afterwards
      // with IOSSIOSPEED, which tcsetattr would reset.
      final standard = standardBaudRates.contains(config.baudRate);
      LibC.cfsetspeed(t, standard ? config.baudRate : 9600);
      if (LibC.tcsetattr(fd, TCSANOW, t) != 0) {
        throw Unsupported(
          'This adapter does not support $config.',
          device: device,
          cause: PosixError('tcsetattr'),
        );
      }
      if (!standard) {
        final speed = arena<UnsignedLong>()..value = config.baudRate;
        if (LibC.ioctl(fd, IOSSIOSPEED, speed.cast()) != 0) {
          throw Unsupported(
            'This adapter does not support ${config.baudRate} baud.',
            device: device,
            cause: PosixError('ioctl(IOSSIOSPEED)'),
          );
        }
      }
    });
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
          'Could not set signals',
          device: device,
          cause: PosixError('ioctl'),
        );
      }
    }
  });
}

final class _MacosSerialConnection implements SerialConnection {
  _MacosSerialConnection(this._fd, this._device, {required this.onClosed});

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
        LibC.close(_fd);
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
            if (error.code != EAGAIN && error.code != EINTR) {
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
    _setSignals(_fd, _device, dtr: dtr, rts: rts);
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
