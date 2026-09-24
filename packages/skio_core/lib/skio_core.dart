/// Shared types for the skio hardware plugins.
///
/// Every skio plugin (`skio_usb_serial`, `skio_uvc_camera`,
/// `skio_ble_central`) re-exports this library, so apps handle permissions,
/// errors and device matching the same way for USB, camera and Bluetooth.
library;

export 'src/access.dart';
export 'src/device.dart';
export 'src/exceptions.dart';
