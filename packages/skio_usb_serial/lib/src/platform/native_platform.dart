import 'dart:io' show Platform;

import '../android/usb_serial_android.dart';
import '../macos/usb_serial_macos.dart';
import 'default_platform.dart' as fallback;
import 'usb_serial_platform.dart';

/// Picks the implementation for the native platform the app runs on, or the
/// unsupported fallback.
UsbSerialPlatform createDefaultPlatform() {
  if (Platform.isAndroid) return AndroidUsbSerialPlatform();
  if (Platform.isMacOS) return MacosUsbSerialPlatform();
  return fallback.createDefaultPlatform();
}
