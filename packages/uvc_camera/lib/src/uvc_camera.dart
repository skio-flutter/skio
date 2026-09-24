import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:skio_core/skio_core.dart';

import 'button_debouncer.dart';
import 'platform/uvc_camera_platform.dart';
import 'uvc_size.dart';

const _source = 'uvc_camera';

/// An open USB Video Class camera.
///
/// ```dart
/// final cameras = await UvcCamera.devices();
/// await UvcCamera.access.requestAccess(cameras.first);
/// final cam = await UvcCamera.open(
///   cameras.first,
///   preferred: const [UvcSize(1920, 1080), UvcSize(1280, 720)],
/// );
/// // In build(): UvcPreview(camera: cam)
/// final jpeg = await cam.capture(quality: 95);
/// await cam.close();
/// ```
final class UvcCamera {
  UvcCamera._(this.device, this._session, ButtonDebouncer debouncer) {
    _statusSub = _session.status.listen(_onStatus);
    _buttonSub = debouncer.bind(_session.buttonStates).listen((_) {
      SkioLog.log(LogLevel.debug, _source, () => 'Button', device: device);
      _buttons.add(null);
    });
  }

  static UvcCameraPlatform get _platform => UvcCameraPlatform.instance;

  /// Permission handling for UVC cameras.
  ///
  /// On Android, `requestAccess(device)` asks for the CAMERA permission (which
  /// Android 9+ requires for USB video devices) and then the USB grant for
  /// that device, in one call. On the web it shows the browser's camera
  /// prompt; call it from a user gesture.
  static HardwareAccess get access => _platform;

  /// UVC cameras that can be opened, optionally narrowed by [filters].
  static Future<List<DeviceHandle>> devices({
    List<DeviceFilter> filters = const [],
  }) async => [
    for (final d in await _platform.devices())
      if (DeviceFilter.matchesAny(filters, d)) d,
  ];

  /// Attach and detach events for UVC cameras.
  static Stream<DeviceEvent> get events => _platform.events;

  /// Opens [device] and starts the preview.
  ///
  /// The preview size is the first of [preferred] that the camera supports
  /// (see [selectPreviewSize]); cheap cameras often support only 1280x720 and
  /// 640x480, so list fallbacks. [buttonDebounce] is the minimum time between
  /// two reported [buttonPresses].
  ///
  /// Throws [AccessDenied] without permission, [DeviceBusy] if another app
  /// uses the camera and [DeviceNotFound] if it was unplugged.
  static Future<UvcCamera> open(
    DeviceHandle device, {
    List<UvcSize> preferred = const [],
    Duration buttonDebounce = const Duration(milliseconds: 700),
  }) async {
    final UvcCameraSession session;
    try {
      session = await _platform.open(device, preferred);
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
      () => 'Opened at ${session.previewSize}',
      device: device,
    );
    return UvcCamera._(
      device,
      session,
      ButtonDebouncer(window: buttonDebounce),
    );
  }

  /// The camera's device handle.
  final DeviceHandle device;

  final UvcCameraSession _session;
  late final StreamSubscription<UvcCameraStatus> _statusSub;
  late final StreamSubscription<void> _buttonSub;
  final _buttons = StreamController<void>.broadcast();
  final _statuses = StreamController<UvcCameraStatus>.broadcast();
  UvcCameraStatus _status = UvcCameraStatus.previewing;
  Future<XFile>? _pendingCapture;

  /// Every size and format the camera supports.
  List<UvcSize> get supportedSizes => _session.supportedSizes;

  /// The size the preview is running at.
  UvcSize get previewSize => _session.previewSize;

  /// The current status.
  UvcCameraStatus get currentStatus => _status;

  /// Status changes after opening.
  Stream<UvcCameraStatus> get status => _statuses.stream;

  /// Whether the camera is still open.
  bool get isOpen =>
      _status == UvcCameraStatus.previewing ||
      _status == UvcCameraStatus.paused;

  /// One event per press of the camera's own button (press only, debounced).
  Stream<void> get buttonPresses => _buttons.stream;

  /// The platform session, for [UvcPreview].
  UvcCameraSession get session => _session;

  /// Captures the current frame as a JPEG.
  ///
  /// [quality] is 1 to 100. On Android the result is a file in the app's
  /// cache directory; move or delete it when done. On the web it is an
  /// in-memory file. Calls made while a capture is running get the same
  /// result, so a double-tap produces one image.
  Future<XFile> capture({int quality = 90}) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be 1 to 100');
    }
    if (!isOpen) {
      throw Disconnected('Camera is closed', device: device);
    }
    return _pendingCapture ??= _capture(quality).whenComplete(() {
      _pendingCapture = null;
    });
  }

  Future<XFile> _capture(int quality) async {
    final file = await _session.capture(quality: quality);
    SkioLog.log(
      LogLevel.info,
      _source,
      () => 'Captured ${file.path}',
      device: device,
    );
    return file;
  }

  /// Stops the preview and releases the camera. Safe to call more than once.
  Future<void> close() => _shutDown(UvcCameraStatus.closed);

  void _onStatus(UvcCameraStatus status) {
    if (!isOpen) return;
    if (status == UvcCameraStatus.disconnected ||
        status == UvcCameraStatus.closed) {
      SkioLog.log(
        LogLevel.warning,
        _source,
        () => 'Camera ${status.name}',
        device: device,
      );
      unawaited(_shutDown(status));
      return;
    }
    _setStatus(status);
  }

  void _setStatus(UvcCameraStatus status) {
    if (_status == status) return;
    _status = status;
    _statuses.add(status);
  }

  Future<void> _shutDown(UvcCameraStatus finalStatus) async {
    if (!isOpen) return;
    _setStatus(finalStatus);
    SkioLog.log(LogLevel.info, _source, () => 'Closed', device: device);
    await _statusSub.cancel();
    await _buttonSub.cancel();
    await _session.close();
    await _buttons.close();
    await _statuses.close();
  }

  @override
  String toString() => 'UvcCamera($device, $previewSize, ${_status.name})';
}
