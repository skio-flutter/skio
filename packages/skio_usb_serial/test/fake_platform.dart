import 'dart:async';
import 'dart:typed_data';

import 'package:skio_usb_serial/platform_interface.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

/// In-memory platform for tests.
final class FakeUsbSerialPlatform extends UsbSerialPlatform {
  FakeUsbSerialPlatform({this.devices = const []});

  List<DeviceHandle> devices;
  final events_ = StreamController<DeviceEvent>.broadcast();
  final opened = <FakeConnection>[];
  Object? openError;

  @override
  bool get requiresUserSelection => false;

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.granted);

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.granted);

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<List<DeviceHandle>> list() async => devices;

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async => null;

  @override
  Stream<DeviceEvent> get events => events_.stream;

  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    if (openError case final e?) throw e;
    final c = FakeConnection(device, config);
    opened.add(c);
    return c;
  }
}

final class FakeConnection implements SerialConnection {
  FakeConnection(this.device, this.config);

  final DeviceHandle device;
  final SerialConfig config;
  final controller = StreamController<Uint8List>();
  final written = <List<int>>[];
  final signals = <({bool? dtr, bool? rts})>[];
  int closeCount = 0;

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
  Future<void> close() async {
    closeCount++;
    if (!controller.isClosed) await controller.close();
  }

  void receive(List<int> bytes) => controller.add(Uint8List.fromList(bytes));

  void unplug() {
    controller.addError(Disconnected('Unplugged', device: device));
    unawaited(controller.close());
  }
}
