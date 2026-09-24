import 'dart:typed_data';

import 'package:skio_core/skio_core.dart';

import '../serial_config.dart';
import 'default_platform.dart'
    if (dart.library.js_interop) '../web/usb_serial_web.dart'
    if (dart.library.ffi) '../android/usb_serial_android.dart';

/// The platform side of `skio_usb_serial`.
///
/// Apps don't use this directly; they use `UsbSerialPort`. Tests can replace
/// [instance] with a fake to exercise app code without hardware.
abstract base class UsbSerialPlatform implements HardwareAccess {
  /// Constructor for subclasses.
  UsbSerialPlatform();

  static UsbSerialPlatform? _instance;

  /// The active platform implementation.
  static UsbSerialPlatform get instance =>
      _instance ??= createDefaultPlatform();

  /// Replaces the platform implementation, for tests and custom backends.
  static set instance(UsbSerialPlatform platform) => _instance = platform;

  /// Whether the user must pick a port in a system chooser ([request]) before
  /// it appears in [list]. True on the web.
  bool get requiresUserSelection;

  /// Serial ports currently attached (Android) or already granted (web).
  Future<List<DeviceHandle>> list();

  /// Shows the system port chooser, if the platform has one.
  ///
  /// Returns the chosen port, or `null` when the user cancels.
  Future<DeviceHandle?> request(List<DeviceFilter> filters);

  /// Attach and detach events.
  Stream<DeviceEvent> get events;

  /// Opens [device] with [config].
  Future<SerialConnection> open(DeviceHandle device, SerialConfig config);
}

/// An open port as seen by the platform layer.
abstract interface class SerialConnection {
  /// Incoming bytes. Emits a [HardwareException] error before closing when the
  /// device goes away, and closes after [close].
  Stream<Uint8List> get input;

  /// Writes all of [data], failing with [OperationTimeout] after [timeout].
  Future<void> write(Uint8List data, Duration timeout);

  /// Sets modem control lines. `null` leaves a line unchanged.
  Future<void> setSignals({bool? dtr, bool? rts});

  /// Releases the port. Safe to call more than once.
  Future<void> close();
}
