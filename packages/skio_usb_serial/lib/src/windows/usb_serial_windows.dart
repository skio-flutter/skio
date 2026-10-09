import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/device_poller.dart';
import '../platform/usb_serial_platform.dart';
import 'dcb.dart';
import 'device_id.dart';
import 'kernel32.dart';
import 'setupapi.dart';

/// [UsbSerialPlatform] for Windows: lists USB COM ports through the
/// SetupAPI and opens them with overlapped I/O through kernel32, all
/// through `dart:ffi`.
final class WindowsUsbSerialPlatform extends UsbSerialPlatform {
  /// Creates the Windows platform.
  WindowsUsbSerialPlatform();

  /// Registers this implementation. Called by Flutter's plugin registrant.
  static void registerWith() {
    UsbSerialPlatform.instance = WindowsUsbSerialPlatform();
  }

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  @override
  bool get requiresUserSelection => false;

  // ---------------------------------------------------------------- access

  // Windows has no per-device permission for COM ports; a port another app
  // holds fails to open with DeviceBusy instead.
  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<bool> openSettings() async => false;

  // ----------------------------------------------------------- discovery

  /// USB serial ports, sorted by COM number. Built-in and Bluetooth COM
  /// ports are left out.
  @override
  Future<List<DeviceHandle>> list() async {
    final handles = [
      for (final port in listComPorts())
        if (port.usb case final usb?)
          DeviceHandle(
            id: port.port,
            name: port.friendlyName == null
                ? port.port
                : trimPortSuffix(port.friendlyName!, port.port),
            vendorId: usb.vendorId,
            productId: usb.productId,
            serialNumber: usb.serialNumber,
          ),
    ];
    return handles
      ..sort((a, b) => _comNumber(a.id).compareTo(_comNumber(b.id)));
  }

  static int _comNumber(String id) =>
      int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 0;

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(
        'Windows has no port chooser. Use UsbSerialPort.list().',
      );

  @override
  Stream<DeviceEvent> get events => pollDeviceEvents(list, pollInterval);

  // ---------------------------------------------------------------- open

  /// Opens the COM port named by `device.id`, for example `COM3`.
  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    final name = normalizeComPort(device.id);
    if (name == null) {
      throw DeviceNotFound(
        'Windows serial ports are named like COM3.',
        device: device,
      );
    }
    final handle = using(
      (arena) => Win32.CreateFileW(
        '\\\\.\\$name'.toNativeUtf16(allocator: arena),
        GENERIC_READ | GENERIC_WRITE,
        0, // no sharing: other apps get access denied
        nullptr,
        OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED,
        0,
      ),
    );
    if (handle == INVALID_HANDLE_VALUE) {
      throw _openError(Win32Error('CreateFileW'), name, device);
    }
    try {
      _configure(handle, config, device);
      final connection = _WindowsConnection(handle, device);
      await connection.start();
      return connection;
    } catch (_) {
      Win32.CloseHandle(handle);
      rethrow;
    }
  }

  static HardwareException _openError(
    Win32Error error,
    String name,
    DeviceHandle device,
  ) => switch (error.code) {
    ERROR_FILE_NOT_FOUND || ERROR_PATH_NOT_FOUND => DeviceNotFound(
      'The device is no longer attached ($name).',
      device: device,
      cause: error,
    ),
    // Windows reports a port another app has open as access denied.
    ERROR_ACCESS_DENIED || ERROR_SHARING_VIOLATION => DeviceBusy(
      '$name is in use by another app. Close serial monitors and IDEs '
      'that may have it open.',
      device: device,
      cause: error,
    ),
    _ => ProtocolError('Could not open $name.', device: device, cause: error),
  };

  static void _configure(int handle, SerialConfig config, DeviceHandle device) {
    using((arena) {
      // Driver buffers; a hint the driver may round or ignore.
      Win32.SetupComm(handle, 64 * 1024, 64 * 1024);

      final dcb = arena<DCB>()..ref.DCBlength = sizeOf<DCB>();
      if (Win32.GetCommState(handle, dcb) == 0) {
        throw ProtocolError(
          'Could not read the port settings. Is this a serial port?',
          device: device,
          cause: Win32Error('GetCommState'),
        );
      }
      final fields = encodeDcb(config, dcb.ref.flags);
      dcb.ref
        ..BaudRate = config.baudRate
        ..flags = fields.flags
        ..ByteSize = fields.byteSize
        ..Parity = fields.parity
        ..StopBits = fields.stopBits
        ..XonChar = 0x11
        ..XoffChar = 0x13
        ..XonLim = 512
        ..XoffLim = 512;
      if (Win32.SetCommState(handle, dcb) == 0) {
        throw Unsupported(
          'This port does not support $config.',
          device: device,
          cause: Win32Error('SetCommState'),
        );
      }

      // A read returns as soon as any byte is there, or after a second with
      // nothing, so the reader can check whether it should stop. Writes
      // have no driver timeout; write() enforces its own.
      final timeouts = arena<COMMTIMEOUTS>();
      timeouts.ref
        ..ReadIntervalTimeout = MAXDWORD
        ..ReadTotalTimeoutMultiplier = MAXDWORD
        ..ReadTotalTimeoutConstant = 1000
        ..WriteTotalTimeoutMultiplier = 0
        ..WriteTotalTimeoutConstant = 0;
      if (Win32.SetCommTimeouts(handle, timeouts) == 0) {
        throw ProtocolError(
          'Could not set the port timeouts.',
          device: device,
          cause: Win32Error('SetCommTimeouts'),
        );
      }
      Win32.PurgeComm(handle, PURGE_RXCLEAR | PURGE_TXCLEAR);
    });
  }
}

final class _WindowsConnection implements SerialConnection {
  _WindowsConnection(this._handle, this._device);

  final int _handle;
  final DeviceHandle _device;
  final _input = StreamController<Uint8List>();
  final _fromReader = ReceivePort('skio_usb_serial reader');
  final _readerDone = Completer<void>();
  Isolate? _reader;
  late final int _stopEvent;
  late final int _writeEvent;
  Future<void> _writing = Future.value();
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _input.stream;

  Future<void> start() async {
    _stopEvent = Win32.CreateEventW(nullptr, 1, 0, nullptr);
    _writeEvent = Win32.CreateEventW(nullptr, 1, 0, nullptr);
    if (_stopEvent == 0 || _writeEvent == 0) {
      throw ProtocolError(
        'Could not start reading',
        device: _device,
        cause: Win32Error('CreateEventW'),
      );
    }
    _fromReader.listen(_onReaderMessage);
    try {
      _reader = await Isolate.spawn(_readLoop, (
        _fromReader.sendPort,
        _handle,
        _stopEvent,
      ), debugName: 'skio_usb_serial reader');
    } catch (e) {
      _fromReader.close();
      Win32.CloseHandle(_stopEvent);
      Win32.CloseHandle(_writeEvent);
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

  void _ensureOpen() {
    if (_closed) throw Disconnected('Port is closed', device: _device);
  }

  @override
  Future<void> write(Uint8List data, Duration timeout) {
    _ensureOpen();
    final result = _write(data, timeout);
    // close() waits for this so it never frees a buffer Windows still uses.
    _writing = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// One overlapped write, polled from this isolate so it never blocks.
  Future<void> _write(Uint8List data, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final buffer = malloc<Uint8>(data.length);
    final overlapped = calloc<OVERLAPPED>();
    final written = calloc<Uint32>();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      var offset = 0;
      while (offset < data.length) {
        Win32.ResetEvent(_writeEvent);
        overlapped.ref
          ..Internal = 0
          ..InternalHigh = 0
          ..Offset = 0
          ..OffsetHigh = 0
          ..hEvent = _writeEvent;
        final started = Win32.WriteFile(
          _handle,
          buffer + offset,
          data.length - offset,
          nullptr,
          overlapped,
        );
        if (started == 0) {
          final error = Win32Error('WriteFile');
          if (error.code != ERROR_IO_PENDING) {
            throw Disconnected('Write failed', device: _device, cause: error);
          }
        }
        while (Win32.WaitForSingleObject(_writeEvent, 0) == WAIT_TIMEOUT) {
          final expired = DateTime.now().isAfter(deadline);
          if (_closed || expired) {
            Win32.CancelIoEx(_handle, overlapped);
            Win32.GetOverlappedResult(_handle, overlapped, written, 1);
            if (_closed) {
              throw Disconnected('Port is closed', device: _device);
            }
            throw OperationTimeout(
              'The device did not accept data in time. Check the flow '
              'control setting and the CTS line.',
              timeout: timeout,
              device: _device,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        if (Win32.GetOverlappedResult(_handle, overlapped, written, 0) == 0) {
          throw Disconnected(
            'Write failed',
            device: _device,
            cause: Win32Error('GetOverlappedResult'),
          );
        }
        offset += written.value;
      }
    } finally {
      malloc.free(buffer);
      calloc
        ..free(overlapped)
        ..free(written);
    }
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    _ensureOpen();
    for (final (on, set, clear) in [
      (dtr, SETDTR, CLRDTR),
      (rts, SETRTS, CLRRTS),
    ]) {
      if (on == null) continue;
      if (Win32.EscapeCommFunction(_handle, on ? set : clear) == 0) {
        throw ProtocolError(
          'Could not set DTR/RTS. With hardware flow control the driver '
          'owns that line.',
          device: _device,
          cause: Win32Error('EscapeCommFunction'),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Win32.SetEvent(_stopEvent);
    await _readerDone.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => _reader?.kill(priority: Isolate.immediate),
    );
    await _writing;
    _fromReader.close();
    Win32.CloseHandle(_handle);
    Win32.CloseHandle(_stopEvent);
    Win32.CloseHandle(_writeEvent);
    unawaited(_input.close());
  }
}

const _readSize = 16 * 1024;

/// Runs in its own isolate: reads from [handle] with overlapped I/O and
/// sends the data to the connection until `stopEvent` is set or the port
/// goes away.
///
/// Sends [TransferableTypedData] for data, a [String] for a fatal error, and
/// `null` when it stops.
void _readLoop((SendPort, int, int) args) {
  final (port, handle, stopEvent) = args;
  final readEvent = Win32.CreateEventW(nullptr, 1, 0, nullptr);
  final overlapped = calloc<OVERLAPPED>();
  final events = calloc<IntPtr>(2);
  final read = calloc<Uint32>();
  final buffer = calloc<Uint8>(_readSize);
  try {
    if (readEvent == 0) {
      port.send('${Win32Error('CreateEventW')}');
      return;
    }
    events[0] = readEvent;
    events[1] = stopEvent;
    while (true) {
      Win32.ResetEvent(readEvent);
      overlapped.ref
        ..Internal = 0
        ..InternalHigh = 0
        ..Offset = 0
        ..OffsetHigh = 0
        ..hEvent = readEvent;
      if (Win32.ReadFile(handle, buffer, _readSize, nullptr, overlapped) == 0) {
        final error = Win32Error('ReadFile');
        if (error.code != ERROR_IO_PENDING) {
          port.send('$error');
          return;
        }
        final woke = Win32.WaitForMultipleObjects(2, events, 0, INFINITE);
        if (woke == WAIT_OBJECT_0 + 1) {
          Win32.CancelIoEx(handle, overlapped);
          // Wait for the cancel, so the buffer is free before it's released.
          Win32.GetOverlappedResult(handle, overlapped, read, 1);
          return;
        }
      }
      if (Win32.GetOverlappedResult(handle, overlapped, read, 0) == 0) {
        final error = Win32Error('GetOverlappedResult');
        if (error.code == ERROR_OPERATION_ABORTED &&
            Win32.WaitForSingleObject(stopEvent, 0) == WAIT_OBJECT_0) {
          return;
        }
        port.send('$error');
        return;
      }
      final n = read.value;
      if (n > 0) {
        port.send(TransferableTypedData.fromList([buffer.asTypedList(n)]));
      } else if (Win32.WaitForSingleObject(stopEvent, 0) == WAIT_OBJECT_0) {
        return;
      }
    }
  } finally {
    if (readEvent != 0) Win32.CloseHandle(readEvent);
    calloc
      ..free(overlapped)
      ..free(events)
      ..free(read)
      ..free(buffer);
    port.send(null);
  }
}
