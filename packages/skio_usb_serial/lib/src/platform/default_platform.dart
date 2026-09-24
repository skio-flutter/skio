import 'package:skio_core/skio_core.dart';

import '../serial_config.dart';
import 'usb_serial_platform.dart';

/// Fallback for platforms without an implementation.
UsbSerialPlatform createDefaultPlatform() => UnsupportedUsbSerialPlatform();

/// A platform where USB serial is not available. Every call reports
/// [AccessStatus.unsupported] or throws [Unsupported].
final class UnsupportedUsbSerialPlatform extends UsbSerialPlatform {
  static const _message = 'USB serial is not supported on this platform.';
  static const _report = AccessReport(AccessStatus.unsupported, hint: _message);

  @override
  bool get requiresUserSelection => false;

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async => _report;

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async => _report;

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<List<DeviceHandle>> list() async => const [];

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(_message);

  @override
  Stream<DeviceEvent> get events => const Stream.empty();

  @override
  Future<SerialConnection> open(DeviceHandle device, SerialConfig config) =>
      throw Unsupported(_message, device: device);
}
