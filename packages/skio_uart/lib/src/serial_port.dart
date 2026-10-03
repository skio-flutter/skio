import 'dart:async';
import 'dart:typed_data';

import 'package:skio_core/skio_core.dart';

import 'backend.dart';

const _source = 'skio_uart';

/// An open serial port: a UART wired to the processor (`/dev/ttyS3` on an
/// Android panel, `/dev/ttyTHS1` on a Jetson), a USB serial adapter
/// (`/dev/ttyUSB0`, `/dev/cu.usbserial-0001`), or a COM port on Windows.
///
/// ```dart
/// final port = await SerialPort.open(
///   '/dev/ttyS3',
///   config: const SerialConfig(baudRate: 9600),
/// );
/// port.input.listen((bytes) => print(bytes));
/// await port.write(utf8.encode('hello\n'));
/// await port.close();
/// ```
final class SerialPort {
  SerialPort._(this.path, this.device, this.config, this._connection) {
    _subscription = _connection.input.listen(
      _onData,
      onError: _onConnectionError,
      onDone: () => unawaited(_shutDown()),
    );
  }

  static SerialBackend get _backend => SerialBackend.instance;

  /// Serial ports present now, optionally narrowed by [filters]. Each
  /// [DeviceHandle.id] is the path to pass to [open].
  ///
  /// USB ports carry their vendor and product IDs. On Android the system
  /// often hides the port list from apps; then this returns what it can
  /// (possibly nothing), and [open] still works with the panel's documented
  /// path such as `/dev/ttyS3`.
  static Future<List<DeviceHandle>> list({
    List<DeviceFilter> filters = const [],
  }) async {
    final all = await _backend.list();
    return [
      for (final d in all)
        if (DeviceFilter.matchesAny(filters, d)) d,
    ];
  }

  /// Ports appearing and disappearing, checked about once a second while
  /// listened to.
  static Stream<DeviceEvent> get events => _backend.events;

  /// Opens the serial port at [path]: `/dev/ttyS3`, `/dev/ttyUSB0`,
  /// `/dev/cu.usbserial-0001` or `COM3`.
  ///
  /// [openDelay] waits after opening before returning, for boards that reset
  /// when the port opens. [writeTimeout] is the default for [write].
  ///
  /// Throws [AccessDenied] when the system doesn't let this app use the
  /// port (the message says how to fix it), [DeviceBusy] if another app has
  /// it open, [DeviceNotFound] if there is no such port, and [Unsupported]
  /// for settings the platform can't apply.
  static Future<SerialPort> open(
    String path, {
    required SerialConfig config,
    Duration openDelay = Duration.zero,
    Duration writeTimeout = const Duration(seconds: 2),
  }) async {
    config.validate();
    final device = DeviceHandle(id: path, name: path.split('/').last);
    final SerialConnection connection;
    try {
      connection = await _backend.open(path, config);
    } on Object catch (e) {
      SkioLog.log(
        LogLevel.warning,
        _source,
        () => 'Open failed',
        device: device,
        error: e,
      );
      rethrow;
    }
    SkioLog.log(
      LogLevel.info,
      _source,
      () => 'Opened with $config',
      device: device,
    );
    final port = SerialPort._(path, device, config, connection)
      .._writeTimeout = writeTimeout;
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    return port;
  }

  /// The path the port was opened with.
  final String path;

  /// The port as a [DeviceHandle], as attached to errors and log records.
  final DeviceHandle device;

  /// The settings the port was opened with.
  final SerialConfig config;

  final SerialConnection _connection;
  late final StreamSubscription<Uint8List> _subscription;
  late Duration _writeTimeout;

  // Single-subscription so bytes that arrive before the app listens (a boot
  // banner, for example) are buffered instead of dropped.
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();
  Future<void> _writeQueue = Future.value();
  bool _open = true;

  /// Incoming bytes, in arrival order.
  ///
  /// Chunks follow what the driver had ready, not message boundaries; use
  /// [LineReader] or your own framing. Can be listened to once; use
  /// `asBroadcastStream()` for several listeners. Emits [Disconnected] and
  /// closes if the port goes away.
  Stream<Uint8List> get input => _input.stream;

  /// Whether the port is still open.
  bool get isOpen => _open;

  /// Completes when the port closes, by [close] or because it went away.
  Future<void> get done => _done.future;

  /// Writes [data]. Writes are sent in call order.
  ///
  /// Completes once the system has taken the data, which may be before the
  /// last byte is on the wire; use [drain] to wait for that. Throws
  /// [OperationTimeout] if the port does not accept the data within
  /// [timeout] (default: the `writeTimeout` given to [open]), and
  /// [Disconnected] if the port is closed.
  Future<void> write(List<int> data, {Duration? timeout}) {
    _ensureOpen();
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    SkioLog.log(
      LogLevel.trace,
      _source,
      () => 'TX ${bytes.length}: ${SkioLog.hex(bytes)}',
      device: device,
    );
    final result = _writeQueue.then(
      (_) => _connection.write(bytes, timeout ?? _writeTimeout),
    );
    // Keep the queue going even if this write fails.
    _writeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Waits until everything written so far has been sent out of the port.
  ///
  /// Useful before closing, changing settings, or switching an RS-485
  /// transceiver back to receive. Throws [OperationTimeout] after
  /// [timeout].
  Future<void> drain({Duration timeout = const Duration(seconds: 5)}) async {
    _ensureOpen();
    await _writeQueue;
    await _connection.drain(timeout);
  }

  /// Discards received bytes not yet read ([input]) and written bytes not
  /// yet sent ([output]).
  Future<void> flush({bool input = true, bool output = true}) {
    _ensureOpen();
    return _connection.flush(input: input, output: output);
  }

  /// Sets the DTR and RTS lines. `null` leaves a line unchanged.
  Future<void> setSignals({bool? dtr, bool? rts}) {
    _ensureOpen();
    SkioLog.log(
      LogLevel.debug,
      _source,
      () => 'Signals dtr=$dtr rts=$rts',
      device: device,
    );
    return _connection.setSignals(dtr: dtr, rts: rts);
  }

  /// Reads the CTS, DSR, DCD and RI lines.
  ///
  /// Many ports, including most panel UARTs with only TX and RX wired, have
  /// no such lines; they read as off or throw [ProtocolError].
  Future<ModemStatus> getSignals() {
    _ensureOpen();
    return _connection.getSignals();
  }

  /// Holds the TX line low for [duration] (a "break"), which some devices
  /// use as a reset or start-of-frame signal.
  Future<void> sendBreak([
    Duration duration = const Duration(milliseconds: 250),
  ]) {
    _ensureOpen();
    return _connection.sendBreak(duration);
  }

  /// Closes the port. Safe to call more than once.
  Future<void> close() => _shutDown();

  void _ensureOpen() {
    if (!_open) throw Disconnected('Port is closed', device: device);
  }

  void _onData(Uint8List bytes) {
    SkioLog.log(
      LogLevel.trace,
      _source,
      () => 'RX ${bytes.length}: ${SkioLog.hex(bytes)}',
      device: device,
    );
    _input.add(bytes);
  }

  void _onConnectionError(Object error, StackTrace stackTrace) {
    final e = error is HardwareException
        ? error
        : Disconnected('Serial port failed', device: device, cause: error);
    SkioLog.log(
      LogLevel.warning,
      _source,
      () => e.message,
      device: device,
      error: e.cause,
    );
    _input.addError(e, stackTrace);
    unawaited(_shutDown());
  }

  Future<void> _shutDown() async {
    if (!_open) return _done.future;
    _open = false;
    SkioLog.log(LogLevel.info, _source, () => 'Closed', device: device);
    try {
      await _subscription.cancel();
      await _connection.close();
    } finally {
      // Not awaited: this only completes once a listener drains the buffer,
      // and the app may never listen.
      unawaited(_input.close());
      _done.complete();
    }
  }

  @override
  String toString() => 'SerialPort($path, $config${_open ? '' : ', closed'})';
}
