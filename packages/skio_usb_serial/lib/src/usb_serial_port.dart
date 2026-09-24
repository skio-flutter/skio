import 'dart:async';
import 'dart:typed_data';

import 'package:skio_core/skio_core.dart';

import 'platform/usb_serial_platform.dart';
import 'serial_config.dart';

/// An open USB serial port.
///
/// ```dart
/// final ports = await UsbSerialPort.list();
/// final port = await UsbSerialPort.open(
///   ports.first,
///   config: const SerialConfig(baudRate: 115200),
/// );
/// port.input.listen((bytes) => print(bytes));
/// await port.write(utf8.encode('hello\n'));
/// await port.close();
/// ```
///
/// On the web, call [request] from a user gesture first; the browser only
/// lists ports the user has picked.
final class UsbSerialPort {
  UsbSerialPort._(this.device, this.config, this._connection) {
    _subscription = _connection.input.listen(
      _input.add,
      onError: _onConnectionError,
      onDone: () => unawaited(_shutDown()),
    );
  }

  static UsbSerialPlatform get _platform => UsbSerialPlatform.instance;

  /// Permission handling for USB serial devices.
  ///
  /// On Android, `requestAccess(device)` shows the system USB permission
  /// dialog for that device. On the web, `requestAccess()` without a device
  /// opens the port chooser.
  static HardwareAccess get access => _platform;

  /// Whether ports must be picked in a system chooser with [request] before
  /// [list] returns them. True on the web, false on Android.
  static bool get requiresUserSelection => _platform.requiresUserSelection;

  /// Serial ports that can be opened now, optionally narrowed by [filters].
  ///
  /// On Android these are all attached USB serial adapters (permission may
  /// still be needed). On the web these are ports the user granted before.
  static Future<List<DeviceHandle>> list({
    List<DeviceFilter> filters = const [],
  }) async {
    final all = await _platform.list();
    return [
      for (final d in all)
        if (DeviceFilter.matchesAny(filters, d)) d,
    ];
  }

  /// Shows the browser's port chooser (web only) and returns the chosen port,
  /// or `null` if the user cancelled.
  ///
  /// Must be called from a user gesture such as a button tap. Throws
  /// [Unsupported] on platforms without a chooser; use [list] there.
  static Future<DeviceHandle?> request({
    List<DeviceFilter> filters = const [],
  }) => _platform.request(filters);

  /// Attach and detach events for USB serial devices.
  static Stream<DeviceEvent> get events => _platform.events;

  /// Opens [device].
  ///
  /// [openDelay] waits after opening before returning, for boards that reset
  /// when the port opens. [writeTimeout] is the default for [write].
  ///
  /// Throws [AccessDenied] without permission, [DeviceBusy] if another app or
  /// tab holds the port, and [DeviceNotFound] if it was unplugged.
  static Future<UsbSerialPort> open(
    DeviceHandle device, {
    required SerialConfig config,
    Duration openDelay = Duration.zero,
    Duration writeTimeout = const Duration(seconds: 2),
  }) async {
    config.validate();
    final connection = await _platform.open(device, config);
    final port = UsbSerialPort._(device, config, connection)
      .._writeTimeout = writeTimeout;
    if (openDelay > Duration.zero) await Future<void>.delayed(openDelay);
    return port;
  }

  /// The device this port belongs to.
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
  /// Chunks follow USB transfers, not message boundaries; use `LineReader` or
  /// your own framing. Can be listened to once; use `asBroadcastStream()` for
  /// several listeners. Emits [Disconnected] and closes if the device goes
  /// away.
  Stream<Uint8List> get input => _input.stream;

  /// Whether the port is still open.
  bool get isOpen => _open;

  /// Completes when the port closes, by [close] or because the device went
  /// away.
  Future<void> get done => _done.future;

  /// Writes [data]. Writes are sent in call order.
  ///
  /// Throws [OperationTimeout] if the device does not accept the data within
  /// [timeout] (default: the `writeTimeout` given to [open]), and
  /// [Disconnected] if the port is closed.
  Future<void> write(List<int> data, {Duration? timeout}) {
    _ensureOpen();
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final result = _writeQueue.then(
      (_) => _connection.write(bytes, timeout ?? _writeTimeout),
    );
    // Keep the queue going even if this write fails.
    _writeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Sets the DTR and RTS modem control lines. `null` leaves a line unchanged.
  Future<void> setSignals({bool? dtr, bool? rts}) {
    _ensureOpen();
    return _connection.setSignals(dtr: dtr, rts: rts);
  }

  /// Closes the port and releases the device. Safe to call more than once.
  Future<void> close() => _shutDown();

  void _ensureOpen() {
    if (!_open) throw Disconnected('Port is closed', device: device);
  }

  void _onConnectionError(Object error, StackTrace stackTrace) {
    final e = error is HardwareException
        ? error
        : Disconnected('Serial port failed', device: device, cause: error);
    _input.addError(e, stackTrace);
    unawaited(_shutDown());
  }

  Future<void> _shutDown() async {
    if (!_open) return _done.future;
    _open = false;
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
  String toString() =>
      'UsbSerialPort($device, $config${_open ? '' : ', closed'})';
}
