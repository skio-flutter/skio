import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:skio_core/skio_core.dart';
import 'package:web/web.dart' as web;

import '../platform/uvc_camera_platform.dart';
import '../uvc_size.dart';

/// Web implementation entry point, registered by Flutter on the web.
final class UvcCameraWeb {
  UvcCameraWeb._();

  /// Called by the Flutter web plugin registrant.
  static void registerWith(Registrar registrar) {
    UvcCameraPlatform.instance = createDefaultPlatform();
  }
}

/// Picks the web implementation.
UvcCameraPlatform createDefaultPlatform() => WebUvcCameraPlatform();

/// Chrome appends `(vendor:product)` to USB camera labels.
final _usbIds = RegExp(r'\(([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\)\s*$');

/// Sizes offered on the web, filtered by what the camera's track allows.
const _commonSizes = [
  UvcSize(3840, 2160),
  UvcSize(2592, 1944),
  UvcSize(1920, 1080),
  UvcSize(1600, 1200),
  UvcSize(1280, 960),
  UvcSize(1280, 720),
  UvcSize(1024, 768),
  UvcSize(800, 600),
  UvcSize(640, 480),
  UvcSize(320, 240),
];

/// [UvcCameraPlatform] for browsers. A UVC camera is an ordinary webcam
/// there, so this uses `getUserMedia`. The hardware button is not exposed to
/// web pages.
final class WebUvcCameraPlatform extends UvcCameraPlatform {
  /// Creates the web platform.
  WebUvcCameraPlatform();

  static const _unsupported = AccessReport(
    AccessStatus.unsupported,
    hint: 'Camera access needs a browser with getUserMedia over https.',
  );

  web.MediaDevices? get _media {
    final navigator = web.window.navigator;
    return navigator.has('mediaDevices') ? navigator.mediaDevices : null;
  }

  // ---------------------------------------------------------------- access

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async {
    if (_media == null) return _unsupported;
    try {
      final status = await web.window.navigator.permissions
          .query({'name': 'camera'}.jsify()! as JSObject)
          .toDart;
      return switch (status.state) {
        'granted' => const AccessReport(AccessStatus.granted),
        'denied' => const AccessReport(
          AccessStatus.permanentlyDenied,
          hint: 'Camera access is blocked in the browser site settings.',
        ),
        _ => const AccessReport(
          AccessStatus.denied,
          hint: 'Call requestAccess() from a user gesture.',
        ),
      };
    } catch (_) {
      // Some browsers can't query the camera permission; asking reveals it.
      return const AccessReport(AccessStatus.denied);
    }
  }

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async {
    final media = _media;
    if (media == null) return _unsupported;
    try {
      final stream = await media
          .getUserMedia(_constraints(device?.id, null))
          .toDart;
      _stop(stream);
      return const AccessReport(AccessStatus.granted);
    } catch (e) {
      return switch (_errorName(e)) {
        'NotAllowedError' || 'SecurityError' => AccessReport(
          AccessStatus.denied,
          hint:
              'The camera was not allowed. If it stays blocked, the user can '
              'allow it in the browser site settings.',
        ),
        'NotFoundError' || 'OverconstrainedError' => const AccessReport(
          AccessStatus.denied,
          hint: 'The camera was not found.',
        ),
        _ => AccessReport(AccessStatus.denied, hint: '$e'),
      };
    }
  }

  @override
  Future<bool> openSettings() async => false;

  // ----------------------------------------------------------- discovery

  @override
  Future<List<DeviceHandle>> devices() async {
    final media = _media;
    if (media == null) return const [];
    final all = (await media.enumerateDevices().toDart).toDart;
    var index = 0;
    return [
      for (final d in all)
        if (d.kind == 'videoinput') _handle(d, index++),
    ];
  }

  static DeviceHandle _handle(web.MediaDeviceInfo info, int index) {
    // Labels and ids are empty until the page has camera permission.
    final label = info.label.isEmpty ? 'Camera ${index + 1}' : info.label;
    final ids = _usbIds.firstMatch(label);
    return DeviceHandle(
      id: info.deviceId.isEmpty ? 'camera-$index' : info.deviceId,
      name: ids == null ? label : label.substring(0, ids.start).trim(),
      vendorId: ids == null ? null : int.parse(ids.group(1)!, radix: 16),
      productId: ids == null ? null : int.parse(ids.group(2)!, radix: 16),
    );
  }

  @override
  Stream<DeviceEvent> get events {
    final media = _media;
    if (media == null) return const Stream.empty();
    late final StreamController<DeviceEvent> controller;
    var known = <String, DeviceHandle>{};
    Future<void> diff() async {
      final now = {for (final d in await devices()) d.id: d};
      for (final d in now.values) {
        if (!known.containsKey(d.id)) controller.add(DeviceAttached(d));
      }
      for (final d in known.values) {
        if (!now.containsKey(d.id)) controller.add(DeviceDetached(d));
      }
      known = now;
    }

    final onChange = ((web.Event _) => unawaited(diff())).toJS;
    controller = StreamController<DeviceEvent>.broadcast(
      onListen: () async {
        known = {for (final d in await devices()) d.id: d};
        media.addEventListener('devicechange', onChange);
      },
      onCancel: () => media.removeEventListener('devicechange', onChange),
    );
    return controller.stream;
  }

  // ---------------------------------------------------------------- open

  @override
  Future<UvcCameraSession> open(
    DeviceHandle device,
    List<UvcSize> preferred,
  ) async {
    final media = _media;
    if (media == null) throw Unsupported(_unsupported.hint!, device: device);
    final want = preferred.isEmpty ? null : preferred.first;
    final web.MediaStream stream;
    try {
      stream = await media.getUserMedia(_constraints(device.id, want)).toDart;
    } catch (e) {
      throw switch (_errorName(e)) {
        'NotAllowedError' || 'SecurityError' => AccessDenied(
          'Camera access was not allowed.',
          device: device,
          cause: e,
        ),
        'NotReadableError' || 'AbortError' => DeviceBusy(
          'The camera is in use by another app or tab.',
          device: device,
          cause: e,
        ),
        'NotFoundError' || 'OverconstrainedError' => DeviceNotFound(
          'The camera was not found.',
          device: device,
          cause: e,
        ),
        _ => ProtocolError(
          'Could not open the camera',
          device: device,
          cause: e,
        ),
      };
    }
    return _WebUvcSession.start(stream, device);
  }

  static web.MediaStreamConstraints _constraints(
    String? deviceId,
    UvcSize? size,
  ) {
    final video = <String, Object>{
      // Ids like 'camera-0' are placeholders from before permission.
      if (deviceId != null && !deviceId.startsWith('camera-'))
        'deviceId': {'exact': deviceId},
      if (size != null) 'width': {'ideal': size.width},
      if (size != null) 'height': {'ideal': size.height},
      if (size?.fps != null) 'frameRate': {'ideal': size!.fps},
    };
    return {'audio': false, 'video': video.isEmpty ? true : video}.jsify()!
        as web.MediaStreamConstraints;
  }
}

void _stop(web.MediaStream stream) {
  for (final track in stream.getTracks().toDart) {
    track.stop();
  }
}

/// The DOMException name of a rejected media promise, read from its text so
/// it works the same under dart2js and dart2wasm.
String? _errorName(Object error) {
  const names = [
    'NotAllowedError',
    'SecurityError',
    'NotFoundError',
    'NotReadableError',
    'OverconstrainedError',
    'AbortError',
  ];
  final text = error.toString();
  for (final name in names) {
    if (text.contains(name)) return name;
  }
  return null;
}

var _viewCounter = 0;

final class _WebUvcSession implements UvcCameraSession {
  _WebUvcSession._(
    this._stream,
    this._track,
    this._video,
    this._viewType,
    this._device,
    this.previewSize,
    this.supportedSizes,
  );

  static _WebUvcSession start(web.MediaStream stream, DeviceHandle device) {
    final track = stream.getVideoTracks().toDart.first;
    final settings = track.getSettings();
    final size = UvcSize(
      settings.width,
      settings.height,
      fps: settings.has('frameRate') ? settings.frameRate.round() : null,
    );

    // Sizes the track can do, limited by its capabilities where known.
    var maxW = size.width;
    var maxH = size.height;
    try {
      final caps = track.getCapabilities();
      if (caps.has('width')) maxW = caps.width.max.round();
      if (caps.has('height')) maxH = caps.height.max.round();
    } catch (_) {
      // getCapabilities is missing in some browsers.
    }
    final supported = [
      for (final s in _commonSizes)
        if (s.width <= maxW && s.height <= maxH) s,
      if (!_commonSizes.contains(UvcSize(size.width, size.height)))
        UvcSize(size.width, size.height),
    ];

    final video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..srcObject = stream;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..backgroundColor = 'black';
    final viewType = 'uvc-camera-${_viewCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => video);

    final session = _WebUvcSession._(
      stream,
      track,
      video,
      viewType,
      device,
      size,
      List.unmodifiable(supported),
    );
    track.addEventListener('ended', session._onEnded);
    return session;
  }

  final web.MediaStream _stream;
  final web.MediaStreamTrack _track;
  final web.HTMLVideoElement _video;
  final String _viewType;
  final DeviceHandle _device;
  final _status = StreamController<UvcCameraStatus>.broadcast();
  bool _closed = false;

  late final JSFunction _onEnded = ((web.Event _) {
    if (_closed) return;
    _status.add(UvcCameraStatus.disconnected);
    unawaited(close());
  }).toJS;

  @override
  final UvcSize previewSize;

  @override
  final List<UvcSize> supportedSizes;

  @override
  Widget buildPreview(BuildContext context) =>
      HtmlElementView(viewType: _viewType);

  /// Browsers don't expose the camera's hardware button.
  @override
  Stream<int> get buttonStates => const Stream.empty();

  @override
  Stream<UvcCameraStatus> get status => _status.stream;

  @override
  Future<XFile> capture({required int quality}) async {
    if (_closed) throw Disconnected('Camera is closed', device: _device);
    final width = _video.videoWidth;
    final height = _video.videoHeight;
    if (width == 0 || height == 0) {
      throw ProtocolError('No frame to capture yet', device: _device);
    }
    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    (canvas.getContext('2d')! as web.CanvasRenderingContext2D).drawImage(
      _video,
      0,
      0,
    );
    final blob = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? b) => blob.complete(b)).toJS,
      'image/jpeg',
      (quality / 100).toJS,
    );
    final result = await blob.future;
    if (result == null) {
      throw ProtocolError('JPEG encoding failed', device: _device);
    }
    final bytes = (await result.arrayBuffer().toDart).toDart.asUint8List();
    final name = 'uvc_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: 'image/jpeg',
      name: name,
      length: bytes.length,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _track.removeEventListener('ended', _onEnded);
    _stop(_stream);
    _video.srcObject = null;
    await _status.close();
  }
}
