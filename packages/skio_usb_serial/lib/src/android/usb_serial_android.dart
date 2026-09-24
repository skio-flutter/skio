import '../platform/default_platform.dart' as fallback;
import '../platform/usb_serial_platform.dart';

/// Picks the Android implementation on Android, and the unsupported fallback
/// on other native platforms.
UsbSerialPlatform createDefaultPlatform() => fallback.createDefaultPlatform();
