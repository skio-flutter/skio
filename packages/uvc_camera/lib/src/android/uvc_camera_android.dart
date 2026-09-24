import 'dart:async';
import 'dart:io' show Platform;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:jni/jni.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/default_platform.dart' as fallback;
import '../platform/uvc_camera_platform.dart';
import '../uvc_size.dart';
import 'bindings.g.dart' as a;

/// Picks the Android implementation on Android, and the unsupported fallback
/// on other native platforms.
UvcCameraPlatform createDefaultPlatform() => Platform.isAndroid
    ? AndroidUvcCameraPlatform()
    : fallback.createDefaultPlatform();

/// USB interface class for video devices.
const _videoClass = 0x0e;

const _source = 'uvc_camera';

/// [UvcCameraPlatform] for Android USB host (OTG), using UVCAndroid through
/// JNI. Only the texture, permission result and JPEG encoding live in Java.
final class AndroidUvcCameraPlatform extends UvcCameraPlatform {
  /// Creates the Android platform.
  AndroidUvcCameraPlatform();

  final _events = StreamController<DeviceEvent>.broadcast();

  /// Control blocks the library opened after a USB grant, by device name.
  final _controlBlocks = <String, a.USBMonitor$UsbControlBlock>{};

  /// Pending USB permission requests, by device name.
  final _grants = <String, Completer<bool>>{};

  /// Open sessions, by device name, to report unplugging.
  final _sessions = <String, _AndroidUvcSession>{};

  late final a.USBMonitor _monitor = _createMonitor();

  a.USBMonitor _createMonitor() {
    final context = a.UvcCameraPlugin.context();
    if (context == null) {
      throw const Unsupported('The uvc_camera plugin is not attached.');
    }
    // All callbacks are async so the library's handler thread never waits
    // for Dart.
    final listener = a.USBMonitor$OnDeviceConnectListener.implement(
      a.$USBMonitor$OnDeviceConnectListener(
        onAttach: (device) => _withDevice(device, (d, name) {
          _events.add(DeviceAttached(d));
        }),
        onAttach$async: true,
        onDetach: (device) => _withDevice(device, (d, name) {
          _events.add(DeviceDetached(d));
          _controlBlocks.remove(name)?.release();
          _sessions[name]?.onUnplugged();
        }),
        onDetach$async: true,
        onDeviceOpen: (device, block, createNew) {
          final name = _name(device);
          device?.release();
          if (name == null || block == null) return;
          _controlBlocks.remove(name)?.release();
          _controlBlocks[name] = block;
          _grants.remove(name)?.complete(true);
        },
        onDeviceOpen$async: true,
        onDeviceClose: (device, block) {
          final name = _name(device);
          device?.release();
          block?.release();
          if (name != null) _controlBlocks.remove(name)?.release();
        },
        onDeviceClose$async: true,
        onCancel: (device) {
          final name = _name(device);
          device?.release();
          if (name != null) _grants.remove(name)?.complete(false);
        },
        onCancel$async: true,
        onError: (device, error) {
          final name = _name(device);
          final message = error?.toString();
          device?.release();
          error?.release();
          SkioLog.log(LogLevel.warning, _source, () => 'USB error: $message');
          if (name != null) _grants.remove(name)?.complete(false);
        },
        onError$async: true,
      ),
    );
    return a.USBMonitor.new$1(context, listener)..register();
  }

  static String? _name(a.UsbDevice? device) =>
      device?.deviceName?.toDartString(releaseOriginal: true);

  void _withDevice(
    a.UsbDevice? device,
    void Function(DeviceHandle handle, String name) action,
  ) {
    if (device == null) return;
    try {
      if (!_isVideo(device)) return;
      final handle = _handle(device);
      action(handle, handle.id);
    } finally {
      device.release();
    }
  }

  static bool _isVideo(a.UsbDevice device) {
    for (var i = 0; i < device.interfaceCount; i++) {
      final iface = device.getInterface(i);
      if (iface == null) continue;
      final isVideo = iface.interfaceClass == _videoClass;
      iface.release();
      if (isVideo) return true;
    }
    return false;
  }

  static DeviceHandle _handle(a.UsbDevice device) {
    String? name;
    try {
      name = device.productName?.toDartString(releaseOriginal: true);
    } on JThrowable {
      // Some devices refuse string descriptors before permission is granted.
    }
    return DeviceHandle(
      id: device.deviceName!.toDartString(releaseOriginal: true),
      name: name,
      vendorId: device.vendorId,
      productId: device.productId,
      interfaceClasses: const [_videoClass],
    );
  }

  /// Finds the attached [device]. The caller releases the result.
  a.UsbDevice _find(DeviceHandle device) {
    final list = _monitor.deviceList;
    if (list != null) {
      final devices = list.asDart();
      for (var i = 0; i < devices.length; i++) {
        final d = devices[i];
        if (d == null) continue;
        if (_name(d) == device.id) {
          list.release();
          return d;
        }
        d.release();
      }
      list.release();
    }
    throw DeviceNotFound('The camera is no longer attached.', device: device);
  }

  // ---------------------------------------------------------------- access

  static const _cameraPermission = 'android.permission.CAMERA';

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async {
    if (!a.UvcCameraPlugin.hasCameraPermission()) {
      return const AccessReport(
        AccessStatus.denied,
        missing: [_cameraPermission],
      );
    }
    if (device == null) return const AccessReport(AccessStatus.granted);
    final usb = _find(device);
    try {
      return _monitor.hasPermission(usb)
          ? const AccessReport(AccessStatus.granted)
          : const AccessReport(
              AccessStatus.denied,
              hint: 'Call requestAccess(device) to show the USB dialog.',
            );
    } finally {
      usb.release();
    }
  }

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async {
    // Android 9+ needs CAMERA to open USB video devices.
    final camera = await _requestCameraPermission();
    if (camera.status != AccessStatus.granted || device == null) return camera;
    final granted = await _requestUsbGrant(device);
    SkioLog.log(
      LogLevel.info,
      _source,
      () => 'USB permission ${granted ? 'granted' : 'denied'}',
      device: device,
    );
    return granted
        ? const AccessReport(AccessStatus.granted)
        : const AccessReport(AccessStatus.denied);
  }

  Future<AccessReport> _requestCameraPermission() {
    final result = Completer<AccessReport>();
    final callback = a.UvcCameraPlugin$PermissionCallback.implement(
      a.$UvcCameraPlugin$PermissionCallback(
        onResult: (granted, permanentlyDenied) {
          if (result.isCompleted) return;
          result.complete(
            granted
                ? const AccessReport(AccessStatus.granted)
                : AccessReport(
                    permanentlyDenied
                        ? AccessStatus.permanentlyDenied
                        : AccessStatus.denied,
                    missing: const [_cameraPermission],
                    canOpenSettings: permanentlyDenied,
                  ),
          );
        },
        onResult$async: true,
      ),
    );
    a.UvcCameraPlugin.requestCameraPermission(callback);
    return result.future.whenComplete(callback.release);
  }

  /// Gets the USB grant. The library opens the device once granted and hands
  /// over a control block through onDeviceOpen, which [open] then uses.
  Future<bool> _requestUsbGrant(DeviceHandle device) async {
    if (_controlBlocks.containsKey(device.id)) return true;
    final pending = _grants[device.id];
    if (pending != null) return pending.future;
    final result = _grants[device.id] = Completer<bool>();
    final usb = _find(device);
    try {
      _monitor.requestPermission(usb);
    } finally {
      usb.release();
    }
    return result.future.timeout(
      const Duration(minutes: 1),
      onTimeout: () {
        _grants.remove(device.id);
        return false;
      },
    );
  }

  @override
  Future<bool> openSettings() async => a.UvcCameraPlugin.openAppSettings();

  // ----------------------------------------------------------- discovery

  @override
  Future<List<DeviceHandle>> devices() async {
    final list = _monitor.deviceList;
    if (list == null) return const [];
    final result = <DeviceHandle>[];
    final devices = list.asDart();
    for (var i = 0; i < devices.length; i++) {
      final d = devices[i];
      if (d == null) continue;
      if (_isVideo(d)) result.add(_handle(d));
      d.release();
    }
    list.release();
    return result;
  }

  @override
  Stream<DeviceEvent> get events {
    _monitor; // start the monitor so attach/detach are reported
    return _events.stream;
  }

  // ---------------------------------------------------------------- open

  @override
  Future<UvcCameraSession> open(
    DeviceHandle device,
    List<UvcSize> preferred,
  ) async {
    if (_sessions.containsKey(device.id)) {
      throw DeviceBusy('The camera is already open.', device: device);
    }
    if (!a.UvcCameraPlugin.hasCameraPermission()) {
      throw AccessDenied(
        'CAMERA permission is required. Call requestAccess(device) first.',
        device: device,
      );
    }
    var block = _controlBlocks[device.id];
    if (block == null) {
      final usb = _find(device);
      final hasGrant = _monitor.hasPermission(usb);
      usb.release();
      if (!hasGrant) {
        throw AccessDenied(
          'No USB permission for this camera. Call requestAccess(device).',
          device: device,
        );
      }
      // Already granted: the library opens the device right away.
      await _requestUsbGrant(device);
      block = _controlBlocks[device.id];
      if (block == null) {
        throw DeviceBusy('Could not open the USB device.', device: device);
      }
    }

    final camera = a.UVCCamera(a.UVCParam());
    final rc = camera.open(block);
    if (rc != 0) {
      camera
        ..destroy()
        ..release();
      throw rc == a.UVCCamera.UVC_ERROR_BUSY
          ? DeviceBusy('The camera is in use.', device: device)
          : ProtocolError(
              'Could not open the camera (error $rc).',
              device: device,
            );
    }

    try {
      final session = _AndroidUvcSession.start(
        camera,
        device,
        preferred,
        onClosed: () => _sessions.remove(device.id),
      );
      _sessions[device.id] = session;
      return session;
    } on Object {
      camera
        ..destroy()
        ..release();
      rethrow;
    }
  }
}

final class _AndroidUvcSession implements UvcCameraSession {
  _AndroidUvcSession._(
    this._camera,
    this._device,
    this.supportedSizes,
    this.previewSize,
    this._onClosed,
  );

  static _AndroidUvcSession start(
    a.UVCCamera camera,
    DeviceHandle device,
    List<UvcSize> preferred, {
    required void Function() onClosed,
  }) {
    // Read what the camera reports. The frame type is the UVC frame
    // descriptor subtype (MJPEG = 7, uncompressed = 5).
    final sizes = <UvcSize>[];
    final native = <a.Size>[];
    final list = camera.supportedSizeList;
    if (list != null) {
      final items = list.asDart();
      for (var i = 0; i < items.length; i++) {
        final s = items[i];
        if (s == null) continue;
        final format = switch (s.type$1) {
          a.UVCCamera.UVC_VS_FRAME_MJPEG => UvcFrameFormat.mjpeg,
          a.UVCCamera.UVC_VS_FRAME_UNCOMPRESSED => UvcFrameFormat.yuyv,
          _ => null,
        };
        if (format == null) {
          s.release();
          continue;
        }
        sizes.add(UvcSize(s.width, s.height, fps: s.fps, format: format));
        native.add(s);
      }
      list.release();
    }

    final chosen = selectPreviewSize(sizes, preferred);
    if (chosen == null) {
      for (final s in native) {
        s.release();
      }
      throw Unsupported(
        'The camera reports no MJPEG or YUYV sizes.',
        device: device,
      );
    }
    try {
      camera.previewSize = native[sizes.indexOf(chosen)];
    } on JThrowable catch (e) {
      throw Unsupported(
        'The camera rejected $chosen.',
        device: device,
        cause: e.message,
      );
    } finally {
      for (final s in native) {
        s.release();
      }
    }

    final session = _AndroidUvcSession._(
      camera,
      device,
      List.unmodifiable(sizes),
      chosen,
      onClosed,
    );
    session._startPreview();
    return session;
  }

  final a.UVCCamera _camera;
  final DeviceHandle _device;
  final void Function() _onClosed;

  @override
  final List<UvcSize> supportedSizes;

  @override
  final UvcSize previewSize;

  late final a.UvcPreviewTexture _texture;
  late final int _textureId;
  a.IButtonCallback? _buttonCallback;
  final _buttons = StreamController<int>.broadcast();
  final _status = StreamController<UvcCameraStatus>.broadcast();
  bool _closed = false;

  void _startPreview() {
    final listener = a.UvcPreviewTexture$Listener.implement(
      a.$UvcPreviewTexture$Listener(
        onPaused: () => _emit(UvcCameraStatus.paused),
        onPaused$async: true,
        onResumed: () => _emit(UvcCameraStatus.previewing),
        onResumed$async: true,
        onError: (message) {
          final text = message?.toDartString(releaseOriginal: true);
          SkioLog.log(
            LogLevel.warning,
            _source,
            () => 'Preview error: $text',
            device: _device,
          );
        },
        onError$async: true,
      ),
    );
    _texture = a.UvcPreviewTexture(
      _camera,
      previewSize.width,
      previewSize.height,
      listener,
    );
    _textureId = _texture.id();
    final callback = _buttonCallback = a.IButtonCallback.implement(
      a.$IButtonCallback(
        onButton: (button, state) {
          if (!_closed) _buttons.add(state);
        },
        onButton$async: true,
      ),
    );
    _camera.buttonCallback = callback;
    try {
      _texture.start();
    } on JThrowable catch (e) {
      _texture.release$1();
      throw ProtocolError(
        'Could not start the preview.',
        device: _device,
        cause: e.message,
      );
    }
  }

  void _emit(UvcCameraStatus status) {
    if (!_closed) _status.add(status);
  }

  void onUnplugged() {
    _emit(UvcCameraStatus.disconnected);
    unawaited(close());
  }

  @override
  Widget buildPreview(BuildContext context) => Texture(textureId: _textureId);

  @override
  Stream<int> get buttonStates => _buttons.stream;

  @override
  Stream<UvcCameraStatus> get status => _status.stream;

  @override
  Future<XFile> capture({required int quality}) {
    if (_closed) {
      throw Disconnected('Camera is closed', device: _device);
    }
    final result = Completer<XFile>();
    final callback = a.JpegCapture$Callback.implement(
      a.$JpegCapture$Callback(
        onCaptured: (path) {
          final p = path?.toDartString(releaseOriginal: true);
          if (result.isCompleted) return;
          if (p == null) {
            result.completeError(
              ProtocolError('Capture returned no file', device: _device),
            );
          } else {
            result.complete(XFile(p, mimeType: 'image/jpeg'));
          }
        },
        onCaptured$async: true,
        onError: (message) {
          final text = message?.toDartString(releaseOriginal: true);
          if (!result.isCompleted) {
            result.completeError(
              ProtocolError('Capture failed', device: _device, cause: text),
            );
          }
        },
        onError$async: true,
      ),
    );
    a.JpegCapture.capture(
      _camera,
      previewSize.width,
      previewSize.height,
      quality,
      callback,
    );
    const timeout = Duration(seconds: 5);
    return result.future
        .timeout(
          timeout,
          onTimeout: () => throw OperationTimeout(
            'No frame arrived to capture',
            timeout: timeout,
            device: _device,
          ),
        )
        .whenComplete(callback.release);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClosed();
    try {
      _camera.buttonCallback = null;
    } on JThrowable {
      // The camera may already be gone.
    }
    _texture.release$1();
    try {
      _camera
        ..close()
        ..destroy();
    } on JThrowable {
      // The camera may already be gone.
    }
    _camera.release();
    _buttonCallback?.release();
    await _buttons.close();
    await _status.close();
  }
}
