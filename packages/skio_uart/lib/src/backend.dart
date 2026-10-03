import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:skio_core/skio_core.dart';

import 'posix/posix_backend.dart';
import 'windows/windows_backend.dart';

/// The state of the modem status lines, read with `SerialPort.getSignals`.
final class ModemStatus {
  /// Creates a status snapshot.
  const ModemStatus({
    required this.cts,
    required this.dsr,
    required this.dcd,
    required this.ri,
  });

  /// Clear To Send: the other side is ready to receive.
  final bool cts;

  /// Data Set Ready: the other side is powered and connected.
  final bool dsr;

  /// Data Carrier Detect (also called RLSD on Windows).
  final bool dcd;

  /// Ring Indicator.
  final bool ri;

  @override
  bool operator ==(Object other) =>
      other is ModemStatus &&
      other.cts == cts &&
      other.dsr == dsr &&
      other.dcd == dcd &&
      other.ri == ri;

  @override
  int get hashCode => Object.hash(cts, dsr, dcd, ri);

  @override
  String toString() => 'ModemStatus(cts: $cts, dsr: $dsr, dcd: $dcd, ri: $ri)';
}

/// The operating-system side of `SerialPort`. One per platform.
abstract base class SerialBackend {
  /// Creates a backend.
  SerialBackend();

  static SerialBackend? _instance;

  /// The backend for the current platform. Replaceable for tests.
  static SerialBackend get instance => _instance ??= _defaultBackend();

  static set instance(SerialBackend backend) => _instance = backend;

  static SerialBackend _defaultBackend() {
    if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
      return PosixBackend();
    }
    if (Platform.isWindows) return WindowsBackend();
    return UnsupportedBackend();
  }

  /// Serial ports present now. Each id is the path to pass to [open].
  Future<List<DeviceHandle>> list();

  /// Attach and detach events.
  Stream<DeviceEvent> get events;

  /// Opens the port at [path] with [config], which has been validated.
  Future<SerialConnection> open(String path, SerialConfig config);
}

/// An open port as a backend sees it.
abstract interface class SerialConnection {
  /// Incoming bytes. Emits [Disconnected] and closes if the port goes away.
  Stream<Uint8List> get input;

  /// Writes all of [data], or throws [OperationTimeout] after [timeout].
  Future<void> write(Uint8List data, Duration timeout);

  /// Sets DTR and RTS. `null` leaves a line unchanged.
  Future<void> setSignals({bool? dtr, bool? rts});

  /// Reads CTS, DSR, DCD and RI.
  Future<ModemStatus> getSignals();

  /// Discards bytes received but not read, sent but not transmitted, or both.
  Future<void> flush({required bool input, required bool output});

  /// Waits until every written byte has left the port, or throws
  /// [OperationTimeout] after [timeout].
  Future<void> drain(Duration timeout);

  /// Holds the TX line low for [duration].
  Future<void> sendBreak(Duration duration);

  /// Closes the port. Safe to call more than once.
  Future<void> close();
}

/// The backend on platforms without serial ports (iOS, web).
final class UnsupportedBackend extends SerialBackend {
  /// Creates the unsupported backend.
  UnsupportedBackend();

  @override
  Future<List<DeviceHandle>> list() async => const [];

  @override
  Stream<DeviceEvent> get events => const Stream.empty();

  @override
  Future<SerialConnection> open(String path, SerialConfig config) async =>
      throw Unsupported(
        'skio_uart supports Android, Linux, macOS and Windows. '
        'This platform has no serial ports apps can open.',
        device: DeviceHandle(id: path),
      );
}

/// Turns a device listing into attach and detach events by calling [list]
/// every [interval] while the stream has listeners.
Stream<DeviceEvent> pollDeviceEvents(
  Future<List<DeviceHandle>> Function() list,
  Duration interval,
) {
  Timer? timer;
  var known = <String, DeviceHandle>{};
  late final StreamController<DeviceEvent> controller;
  Future<void> poll() async {
    final now = {for (final d in await list()) d.id: d};
    for (final d in now.values) {
      if (!known.containsKey(d.id)) controller.add(DeviceAttached(d));
    }
    for (final d in known.values) {
      if (!now.containsKey(d.id)) controller.add(DeviceDetached(d));
    }
    known = now;
  }

  controller = StreamController<DeviceEvent>.broadcast(
    onListen: () async {
      known = {for (final d in await list()) d.id: d};
      // The listener may have cancelled while the first list() ran.
      if (!controller.hasListener) return;
      timer = Timer.periodic(interval, (_) => unawaited(poll()));
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  return controller.stream;
}
