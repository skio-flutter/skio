import 'package:skio_core/skio_core.dart';

import '../uvc_size.dart';
import 'uvc_camera_platform.dart';

/// Fallback for platforms without an implementation.
UvcCameraPlatform createDefaultPlatform() => UnsupportedUvcCameraPlatform();

/// A platform where UVC cameras are not available. Every call reports
/// [AccessStatus.unsupported] or throws [Unsupported].
final class UnsupportedUvcCameraPlatform extends UvcCameraPlatform {
  static const _message = 'UVC cameras are not supported on this platform.';
  static const _report = AccessReport(AccessStatus.unsupported, hint: _message);

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async => _report;

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async => _report;

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<List<DeviceHandle>> devices() async => const [];

  @override
  Stream<DeviceEvent> get events => const Stream.empty();

  @override
  Future<UvcCameraSession> open(DeviceHandle device, List<UvcSize> preferred) =>
      throw Unsupported(_message, device: device);
}
