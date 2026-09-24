/// The platform layer of `skio_usb_serial`, for tests and custom backends.
///
/// Replace [UsbSerialPlatform.instance] with a fake in tests to exercise app
/// code without hardware.
library;

import 'src/platform/usb_serial_platform.dart';

export 'src/platform/default_platform.dart' show UnsupportedUsbSerialPlatform;
export 'src/platform/usb_serial_platform.dart';
