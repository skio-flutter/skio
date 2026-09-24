import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:skio_core/skio_core.dart';

import '../uvc_size.dart';
import 'default_platform.dart'
    if (dart.library.js_interop) '../web/uvc_camera_web.dart'
    if (dart.library.ffi) '../android/uvc_camera_android.dart';

/// State of an open camera, as reported by [UvcCameraSession.status].
enum UvcCameraStatus {
  /// Frames are arriving and the preview is live.
  previewing,

  /// The preview surface is gone for now (for example the app is in the
  /// background); it resumes on its own.
  paused,

  /// The camera was unplugged or stopped responding. The camera is closed.
  disconnected,

  /// The camera was closed by the app.
  closed,
}

/// The platform side of `skio_uvc_camera`.
///
/// Apps use `UvcCamera`; tests can replace [instance] with a fake.
abstract base class UvcCameraPlatform implements HardwareAccess {
  /// Constructor for subclasses.
  UvcCameraPlatform();

  static UvcCameraPlatform? _instance;

  /// The active platform implementation.
  static UvcCameraPlatform get instance =>
      _instance ??= createDefaultPlatform();

  /// Replaces the platform implementation, for tests and custom backends.
  static set instance(UvcCameraPlatform platform) => _instance = platform;

  /// UVC cameras currently attached (Android) or available (web).
  Future<List<DeviceHandle>> devices();

  /// Attach and detach events.
  Stream<DeviceEvent> get events;

  /// Opens [device] and starts the preview at the first size in [preferred]
  /// the camera supports (see `selectPreviewSize`).
  Future<UvcCameraSession> open(DeviceHandle device, List<UvcSize> preferred);
}

/// An open camera as seen by the platform layer.
abstract interface class UvcCameraSession {
  /// Every size and format the camera reports.
  List<UvcSize> get supportedSizes;

  /// The size the preview is running at.
  UvcSize get previewSize;

  /// Builds the live preview widget.
  Widget buildPreview(BuildContext context);

  /// Raw hardware-button states: 1 for press, 0 for release.
  Stream<int> get buttonStates;

  /// Status changes. Emits [UvcCameraStatus.disconnected] if the camera goes
  /// away.
  Stream<UvcCameraStatus> get status;

  /// Captures the next frame as JPEG with [quality] from 1 to 100.
  Future<XFile> capture({required int quality});

  /// Stops the preview and releases the camera. Safe to call more than once.
  Future<void> close();
}
