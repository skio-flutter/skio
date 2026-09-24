import '../platform/default_platform.dart' as fallback;
import '../platform/uvc_camera_platform.dart';

/// Picks the Android implementation on Android, and the unsupported fallback
/// on other native platforms.
UvcCameraPlatform createDefaultPlatform() => fallback.createDefaultPlatform();
