import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:skio_core/skio_core.dart';

import 'button_debouncer.dart';
import 'platform/uvc_camera_platform.dart';
import 'uvc_size.dart';

const _source = 'skio_uvc_camera';

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
/// // Or straight into your own folder, or as bytes with no file at all:
/// await cam.capture(directory: photosDir, fileName: 'scan_001.jpg');
/// final Uint8List bytes = await cam.captureBytes();
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
  _Capture? _pendingCapture;

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

  /// Captures the current frame as a JPEG file.
  ///
  /// [quality] is 1 to 100.
  ///
  /// On Android the photo is written to [directory] as [fileName], so it
  /// lands where your app keeps photos without a move or copy. [directory]
  /// must be an absolute path the app can write to (for example from
  /// `path_provider`'s `getApplicationDocumentsDirectory()`); it is created
  /// if missing. [fileName] must be a plain name such as `scan_001.jpg` (no
  /// `/`), and an existing file with that name is replaced. Without
  /// [directory] the photo goes to the app's cache folder; without
  /// [fileName] it is named `uvc_<milliseconds>.jpg`.
  ///
  /// On the web the result is an in-memory file named [fileName];
  /// [directory] is ignored.
  ///
  /// To upload, display or hand the photo to another API without writing a
  /// file, use [captureBytes].
  ///
  /// Calls made while the same capture is running get the same result, so a
  /// double-tap produces one image. Captures to a different file, and
  /// [captureBytes], wait for the running one and then take their own frame.
  Future<XFile> capture({
    int quality = 90,
    String? directory,
    String? fileName,
  }) {
    _checkQuality(quality);
    if (directory != null && directory.isEmpty) {
      throw ArgumentError.value(directory, 'directory', 'must not be empty');
    }
    if (fileName != null) _checkFileName(fileName);
    return _guard(('file', directory, fileName), () async {
      final file = await _session.capture(
        quality: quality,
        directory: directory,
        fileName: fileName,
      );
      SkioLog.log(
        LogLevel.info,
        _source,
        () => 'Captured ${file.path}',
        device: device,
      );
      return file;
    });
  }

  /// Captures the current frame as JPEG bytes, without writing a file.
  ///
  /// Use it to upload the photo, show it with `Image.memory`, or save it
  /// with your own storage code (for example to the gallery). [quality] is
  /// 1 to 100. Shares the in-flight guard with [capture]: calls made while a
  /// bytes capture is running get the same bytes.
  Future<Uint8List> captureBytes({int quality = 90}) {
    _checkQuality(quality);
    return _guard(('bytes',), () async {
      final bytes = await _session.captureBytes(quality: quality);
      SkioLog.log(
        LogLevel.info,
        _source,
        () => 'Captured ${bytes.length} bytes',
        device: device,
      );
      return bytes;
    });
  }

  void _checkQuality(int quality) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be 1 to 100');
    }
    if (!isOpen) {
      throw Disconnected('Camera is closed', device: device);
    }
  }

  static void _checkFileName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\u0000')) {
      throw ArgumentError.value(
        name,
        'fileName',
        'must be a plain file name without path separators',
      );
    }
  }

  /// Runs [run] unless a capture for the same [key] is already running, in
  /// which case its result is shared. A capture for another key waits for
  /// the running one: the camera delivers frames to one capture at a time.
  Future<T> _guard<T extends Object>(Object key, Future<T> Function() run) {
    final pending = _pendingCapture;
    if (pending != null && pending.key == key) {
      return pending.result as Future<T>;
    }
    final Future<T> result = pending == null
        ? run()
        : pending.result.then((_) => run(), onError: (Object _) => run());
    final capture = _Capture(key, result);
    _pendingCapture = capture;
    return result.whenComplete(() {
      if (identical(_pendingCapture, capture)) _pendingCapture = null;
    });
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

/// A running capture and what it was asked for.
final class _Capture {
  _Capture(this.key, this.result);

  final Object key;
  final Future<Object> result;
}
