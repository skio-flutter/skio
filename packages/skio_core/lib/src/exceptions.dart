import 'device.dart';

/// Base class of every runtime error a skio plugin throws.
///
/// Switch over the subtypes to handle each case. [message] is safe to show
/// to users; [cause] holds the raw native or JavaScript error for logs.
sealed class HardwareException implements Exception {
  const HardwareException(this.message, {this.device, this.cause});

  /// A short, user-safe description.
  final String message;

  /// The device involved, if known.
  final DeviceHandle? device;

  /// The underlying platform error, for logging only.
  final Object? cause;

  String get _type;

  @override
  String toString() {
    final on = device == null ? '' : ' [$device]';
    final why = cause == null ? '' : ' (cause: $cause)';
    return '$_type: $message$on$why';
  }
}

/// The user or system refused access to the device.
final class AccessDenied extends HardwareException {
  /// Creates an access-denied error.
  const AccessDenied(super.message, {super.device, super.cause});

  @override
  String get _type => 'AccessDenied';
}

/// The requested device is not attached or not found.
final class DeviceNotFound extends HardwareException {
  /// Creates a device-not-found error.
  const DeviceNotFound(super.message, {super.device, super.cause});

  @override
  String get _type => 'DeviceNotFound';
}

/// The device is held by another app, tab or connection.
final class DeviceBusy extends HardwareException {
  /// Creates a device-busy error.
  const DeviceBusy(super.message, {super.device, super.cause});

  @override
  String get _type => 'DeviceBusy';
}

/// The device went away during use (unplugged, powered off, suspended).
final class Disconnected extends HardwareException {
  /// Creates a disconnected error.
  const Disconnected(super.message, {super.device, super.cause});

  @override
  String get _type => 'Disconnected';
}

/// A command did not complete within its timeout.
///
/// Named `OperationTimeout` rather than `Timeout` so it does not clash with
/// `Timeout` from `package:test`.
final class OperationTimeout extends HardwareException {
  /// Creates a timeout error.
  const OperationTimeout(
    super.message, {
    required this.timeout,
    super.device,
    super.cause,
  });

  /// The timeout that elapsed.
  final Duration timeout;

  @override
  String get _type => 'OperationTimeout(${timeout.inMilliseconds} ms)';
}

/// The platform or device does not support the requested operation.
final class Unsupported extends HardwareException {
  /// Creates an unsupported-operation error.
  const Unsupported(super.message, {super.device, super.cause});

  @override
  String get _type => 'Unsupported';
}

/// The device responded in an unexpected way.
final class ProtocolError extends HardwareException {
  /// Creates a protocol error.
  const ProtocolError(super.message, {super.device, super.cause});

  @override
  String get _type => 'ProtocolError';
}

/// The app is misconfigured, for example a permission is missing from
/// `AndroidManifest.xml`.
///
/// This is a developer error, so it extends [Error] rather than
/// [HardwareException] and should not be caught in production code.
final class AccessConfigurationError extends Error {
  /// Creates a configuration error that tells the developer how to fix it.
  AccessConfigurationError(this.message, {this.fix});

  /// What is wrong.
  final String message;

  /// The exact change to make, for example the manifest line to add.
  final String? fix;

  @override
  String toString() =>
      'AccessConfigurationError: $message${fix == null ? '' : '\nFix: $fix'}';
}
