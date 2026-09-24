import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../platform/default_platform.dart' as fallback;
import '../platform/uvc_camera_platform.dart';

/// Web implementation entry point, registered by Flutter on the web.
final class UvcCameraWeb {
  UvcCameraWeb._();

  /// Called by the Flutter web plugin registrant.
  static void registerWith(Registrar registrar) {
    UvcCameraPlatform.instance = createDefaultPlatform();
  }
}

/// Picks the web implementation.
UvcCameraPlatform createDefaultPlatform() => fallback.createDefaultPlatform();
