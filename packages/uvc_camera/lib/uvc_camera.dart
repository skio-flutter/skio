/// USB Video Class cameras for Flutter on Android (USB OTG) and the web.
///
/// Find a camera with [UvcCamera.devices], request access, [UvcCamera.open]
/// it and show it with [UvcPreview].
library;

import 'src/uvc_camera.dart';
import 'src/uvc_preview.dart';

export 'package:cross_file/cross_file.dart' show XFile;
export 'package:skio_core/skio_core.dart';

export 'src/platform/uvc_camera_platform.dart' show UvcCameraStatus;
export 'src/uvc_camera.dart';
export 'src/uvc_preview.dart';
export 'src/uvc_size.dart';
