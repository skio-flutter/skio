// Regenerates lib/src/android/bindings.g.dart.
//
// Run from packages/uvc_camera after building the example once
// (`cd example && flutter build apk --debug`) so Gradle has resolved the
// Android dependencies:
//
//   dart run tool/jnigen.dart
import 'dart:io';

import 'package:jnigen/jnigen.dart';

/// Members to bind per class. Classes not listed get every public member.
/// Keeping this short keeps the generated file small and reviewable.
const _allow = <String, Set<String>>{
  'android.content.Context': {},
  'android.hardware.usb.UsbDevice': {
    'getDeviceName',
    'getVendorId',
    'getProductId',
    'getProductName',
    'getInterfaceCount',
    'getInterface',
  },
  'android.hardware.usb.UsbInterface': {'getInterfaceClass'},
  'com.serenegiant.usb.USBMonitor': {
    '<init>',
    'register',
    'unregister',
    'destroy',
    'getDeviceList',
    'hasPermission',
    'requestPermission',
  },
  r'com.serenegiant.usb.USBMonitor$UsbControlBlock': {'getDeviceName', 'close'},
  'com.serenegiant.usb.UVCCamera': {
    '<init>',
    'open',
    'close',
    'destroy',
    'stopPreview',
    'getSupportedSizeList',
    'setPreviewSize',
    'setButtonCallback',
    'UVC_VS_FRAME_MJPEG',
    'UVC_VS_FRAME_UNCOMPRESSED',
    'UVC_ERROR_BUSY',
  },
  'com.serenegiant.usb.UVCParam': {'<init>'},
  'com.serenegiant.usb.Size': {'type', 'width', 'height', 'fps'},
  'com.serenegiant.usb.IButtonCallback': {'onButton'},
  'dev.skio.uvc_camera.UvcCameraPlugin': {
    'context',
    'hasCameraPermission',
    'requestCameraPermission',
    'openAppSettings',
  },
  'dev.skio.uvc_camera.UvcPreviewTexture': {'<init>', 'id', 'start', 'release'},
  'dev.skio.uvc_camera.JpegCapture': {'capture'},
};

/// Nested classes to bind in full. Other nested classes of bound classes are
/// dropped.
const _nested = {
  r'com.serenegiant.usb.USBMonitor$OnDeviceConnectListener',
  r'com.serenegiant.usb.USBMonitor$UsbControlBlock',
  r'dev.skio.uvc_camera.UvcCameraPlugin$PermissionCallback',
  r'dev.skio.uvc_camera.UvcPreviewTexture$Listener',
  r'dev.skio.uvc_camera.JpegCapture$Callback',
};

final class _AllowList extends Visitor {
  _AllowList() : super.base();

  Set<String>? _current;

  @override
  void visitClass(ClassDecl c) {
    final name = c.binaryName;
    if (name.contains(r'$') && !_nested.contains(name)) {
      c.isIncluded = false;
    }
    _current = _allow[name];
  }

  @override
  void visitMethod(Method method) {
    final allowed = _current;
    if (allowed == null) return;
    final name = method.isConstructor ? '<init>' : method.originalName;
    method.isIncluded = allowed.contains(name);
  }

  @override
  void visitField(Field field) {
    final allowed = _current;
    if (allowed == null) return;
    field.isIncluded = allowed.contains(field.originalName);
  }
}

Future<void> main() async {
  final root = Platform.script.resolve('../');
  await JniGenerator(
    input: Input(
      classes: [
        for (final name in _allow.keys)
          if (!name.contains(r'$')) name,
      ],
      androidSdk: AndroidSdk(
        addGradleDeps: true,
        androidExample: root.resolve('example/'),
      ),
    ),
    output: Output(
      dart: DartOutput(
        path: root.resolve('lib/src/android/bindings.g.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
    visitors: [_AllowList()],
  ).generate();
  // Match the repo's formatter so CI's format check passes.
  await Process.run('dart', [
    'format',
    root.resolve('lib/src/android/bindings.g.dart').toFilePath(),
  ]);
}
