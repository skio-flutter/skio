/// Shared types for the skio hardware plugins.
///
/// The skio packages (`skio_usb_serial`, `skio_uart`, `skio_uvc_camera`)
/// re-export this library, so apps handle permissions, errors, device
/// matching and serial settings the same way for every device.
library;

export 'src/access.dart';
export 'src/device.dart';
export 'src/exceptions.dart';
export 'src/log.dart';
export 'src/serial/line_reader.dart';
export 'src/serial/serial_config.dart';
