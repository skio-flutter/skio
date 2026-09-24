// Regenerates lib/src/android/bindings.g.dart.
//
// Run from packages/skio_usb_serial after building the example once
// (`cd example && flutter build apk --debug`) so Gradle has resolved the
// Android dependencies:
//
//   dart run tool/jnigen.dart
import 'dart:io';

import 'package:jnigen/jnigen.dart';

/// Members to bind per class. Classes not listed get every public member.
/// Keeping this short keeps the generated file small and reviewable.
const _allow = <String, Set<String>>{
  'android.content.Context': {
    'getSystemService',
    'getPackageName',
    'startActivity',
    'USB_SERVICE',
  },
  'android.content.Intent': {
    '<init>',
    'setPackage',
    'setData',
    'addFlags',
    'FLAG_ACTIVITY_NEW_TASK',
  },
  'android.net.Uri': {'fromParts'},
  'android.app.PendingIntent': {
    'getBroadcast',
    'cancel',
    'FLAG_MUTABLE',
    'FLAG_UPDATE_CURRENT',
  },
  r'android.os.Build$VERSION': {'SDK_INT'},
  'android.hardware.usb.UsbManager': {
    'hasPermission',
    'requestPermission',
    'openDevice',
  },
  'android.hardware.usb.UsbDevice': {
    'getDeviceName',
    'getVendorId',
    'getProductId',
    'getProductName',
    'getManufacturerName',
  },
  'android.hardware.usb.UsbDeviceConnection': {'close'},
  'com.hoho.android.usbserial.driver.UsbSerialProber': {
    'getDefaultProber',
    'findAllDrivers',
  },
  'com.hoho.android.usbserial.driver.UsbSerialDriver': {
    'getDevice',
    'getPorts',
  },
  'com.hoho.android.usbserial.driver.UsbSerialPort': {
    'open',
    'close',
    'isOpen',
    'setParameters',
    'setFlowControl',
    'write',
    'setDTR',
    'setRTS',
    'getPortNumber',
    'PARITY_NONE',
    'PARITY_ODD',
    'PARITY_EVEN',
    'PARITY_MARK',
    'PARITY_SPACE',
    'STOPBITS_1',
    'STOPBITS_1_5',
    'STOPBITS_2',
  },
  'com.hoho.android.usbserial.util.SerialInputOutputManager': {
    '<init>',
    'setReadTimeout',
    'setWriteTimeout',
    'setReadBufferSize',
    'writeAsync',
    'start',
    'stop',
  },
};

/// Nested classes to bind in full. Other nested classes of bound classes are
/// dropped.
const _nested = {
  r'android.os.Build$VERSION',
  r'com.hoho.android.usbserial.driver.UsbSerialPort$FlowControl',
  r'com.hoho.android.usbserial.util.SerialInputOutputManager$Listener',
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
    if (name == 'android.os.Build') c.isIncluded = false;
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
        'android.os.Build',
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
