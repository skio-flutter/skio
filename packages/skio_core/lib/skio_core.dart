/// Shared types for the skio hardware plugins.
///
/// The skio plugins (`skio_usb_serial`, `skio_uvc_camera`) re-export this library,
/// so apps handle permissions, errors and device matching the same way for
/// every device.
library;

export 'src/access.dart';
export 'src/device.dart';
export 'src/exceptions.dart';
export 'src/log.dart';
