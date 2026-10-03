import 'dart:async';
import 'dart:typed_data';

import 'package:skio_uart/skio_uart.dart';
import 'package:skio_uart/src/backend.dart';

/// In-memory backend for tests.
final class FakeBackend extends SerialBackend {
  FakeBackend({this.ports = const []});

  List<DeviceHandle> ports;
  final events_ = StreamController<DeviceEvent>.broadcast();
  final opened = <FakeConnection>[];
  Object? openError;

  @override
  Future<List<DeviceHandle>> list() async => ports;

  @override
  Stream<DeviceEvent> get events => events_.stream;

  @override
  Future<SerialConnection> open(String path, SerialConfig config) async {
    if (openError case final e?) throw e;
    final c = FakeConnection(path, config);
    opened.add(c);
    return c;
  }
}

final class FakeConnection implements SerialConnection {
  FakeConnection(this.path, this.config);

  final String path;
  final SerialConfig config;
  final controller = StreamController<Uint8List>();
  final written = <List<int>>[];
  final signals = <({bool? dtr, bool? rts})>[];
  final flushes = <({bool input, bool output})>[];
  final breaks = <Duration>[];
  int drains = 0;
  int closeCount = 0;
  ModemStatus status = const ModemStatus(
    cts: true,
    dsr: false,
    dcd: false,
    ri: false,
  );

  /// Completes a pending write when set; otherwise writes complete at once.
  Completer<void>? writeGate;

  @override
  Stream<Uint8List> get input => controller.stream;

  @override
  Future<void> write(Uint8List data, Duration timeout) async {
    final gate = writeGate;
    if (gate != null) await gate.future;
    written.add(data);
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async =>
      signals.add((dtr: dtr, rts: rts));

  @override
  Future<ModemStatus> getSignals() async => status;

  @override
  Future<void> flush({required bool input, required bool output}) async =>
      flushes.add((input: input, output: output));

  @override
  Future<void> drain(Duration timeout) async => drains++;

  @override
  Future<void> sendBreak(Duration duration) async => breaks.add(duration);

  @override
  Future<void> close() async {
    closeCount++;
    if (!controller.isClosed) await controller.close();
  }

  void receive(List<int> bytes) => controller.add(Uint8List.fromList(bytes));

  void unplug() {
    controller.addError(
      Disconnected('Unplugged', device: DeviceHandle(id: path)),
    );
    unawaited(controller.close());
  }
}
