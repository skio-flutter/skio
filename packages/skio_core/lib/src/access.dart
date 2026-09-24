import 'device.dart';

/// The result of checking or requesting access to a hardware capability.
enum AccessStatus {
  /// Everything needed is granted; the device can be used.
  granted,

  /// Access was refused, but asking again may show the system prompt.
  denied,

  /// Access was refused and the system will not prompt again. The user must
  /// enable it in the app's settings page (see [HardwareAccess.openSettings]).
  permanentlyDenied,

  /// Access is blocked by policy (for example parental controls or MDM).
  restricted,

  /// The platform needs no permission for this capability.
  notRequired,

  /// The capability does not exist on this platform.
  unsupported,
}

/// A detailed access result returned by [HardwareAccess].
final class AccessReport {
  /// Creates an access report.
  const AccessReport(
    this.status, {
    this.missing = const [],
    this.canOpenSettings = false,
    this.hint,
  });

  /// The overall access status.
  final AccessStatus status;

  /// Platform permission names that are still missing, for example
  /// `android.permission.CAMERA`. Empty when nothing is missing.
  final List<String> missing;

  /// Whether the user must enable access in the system settings page.
  final bool canOpenSettings;

  /// Optional developer-facing explanation, for example that a web prompt
  /// must be triggered from a user gesture.
  final String? hint;

  /// Whether the device can be used now.
  bool get isUsable =>
      status == AccessStatus.granted || status == AccessStatus.notRequired;

  @override
  String toString() =>
      'AccessReport($status, missing: $missing, '
      'canOpenSettings: $canOpenSettings${hint == null ? '' : ', hint: $hint'})';
}

/// The permission API every skio plugin implements.
///
/// Access is device-scoped because some platforms grant permission per
/// attached device (Android USB). Pass `null` to check the capability as a
/// whole, for example Bluetooth scanning.
abstract interface class HardwareAccess {
  /// Returns the current access state without showing any prompt.
  Future<AccessReport> checkAccess([DeviceHandle? device]);

  /// Requests access, which may show system dialogs.
  ///
  /// On the web this must be called from a user gesture such as a tap.
  Future<AccessReport> requestAccess([DeviceHandle? device]);

  /// Opens this app's page in the system settings.
  ///
  /// Returns `false` when the platform has no such page.
  Future<bool> openSettings();
}
