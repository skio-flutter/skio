/// A stable description of one hardware device.
///
/// [id] is platform-specific: a USB device name on Android, a BLE address,
/// or a browser-assigned id on the web. The other fields are filled in where
/// the platform exposes them.
final class DeviceHandle {
  /// Creates a device handle.
  const DeviceHandle({
    required this.id,
    this.name,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.interfaceClasses = const [],
    this.serviceUuids = const [],
  });

  /// Platform-specific identifier, unique among currently known devices.
  final String id;

  /// Human-readable name reported by the device, if any.
  final String? name;

  /// USB vendor ID.
  final int? vendorId;

  /// USB product ID.
  final int? productId;

  /// Serial number, when the platform and permissions allow reading it.
  final String? serialNumber;

  /// USB interface class codes, for example `0x0E` for video.
  final List<int> interfaceClasses;

  /// Advertised BLE service UUIDs, lower case.
  final List<String> serviceUuids;

  @override
  bool operator ==(Object other) =>
      other is DeviceHandle &&
      other.id == id &&
      other.vendorId == vendorId &&
      other.productId == productId;

  @override
  int get hashCode => Object.hash(id, vendorId, productId);

  @override
  String toString() {
    final ids = vendorId == null
        ? ''
        : ' ${_hex(vendorId!)}:${productId == null ? '????' : _hex(productId!)}';
    return 'DeviceHandle($id$ids${name == null ? '' : ' "$name"'})';
  }

  static String _hex(int v) => v.toRadixString(16).padLeft(4, '0');
}

/// Declarative criteria for selecting devices.
///
/// Every non-null field must match. A filter with no fields set matches every
/// device.
final class DeviceFilter {
  /// Creates a device filter.
  const DeviceFilter({
    this.vendorId,
    this.productId,
    this.namePrefix,
    this.interfaceClass,
    this.serviceUuids = const [],
  });

  /// Required USB vendor ID.
  final int? vendorId;

  /// Required USB product ID.
  final int? productId;

  /// Required prefix of the device name.
  final String? namePrefix;

  /// Required USB interface class code.
  final int? interfaceClass;

  /// BLE service UUIDs the device must advertise (all of them).
  final List<String> serviceUuids;

  /// Whether [device] satisfies this filter.
  bool matches(DeviceHandle device) {
    if (vendorId != null && device.vendorId != vendorId) return false;
    if (productId != null && device.productId != productId) return false;
    if (namePrefix != null &&
        !(device.name?.startsWith(namePrefix!) ?? false)) {
      return false;
    }
    if (interfaceClass != null &&
        !device.interfaceClasses.contains(interfaceClass)) {
      return false;
    }
    for (final uuid in serviceUuids) {
      if (!device.serviceUuids.contains(uuid.toLowerCase())) return false;
    }
    return true;
  }

  /// Whether [device] matches any of [filters]. An empty list matches all.
  static bool matchesAny(Iterable<DeviceFilter> filters, DeviceHandle device) =>
      filters.isEmpty || filters.any((f) => f.matches(device));
}

/// A change in the set of attached or connected devices.
sealed class DeviceEvent {
  const DeviceEvent(this.device);

  /// The device the event is about.
  final DeviceHandle device;
}

/// A device was attached (USB) or connected (BLE).
final class DeviceAttached extends DeviceEvent {
  /// Creates an attach event.
  const DeviceAttached(super.device);

  @override
  String toString() => 'DeviceAttached($device)';
}

/// A device was detached (USB) or disconnected (BLE).
final class DeviceDetached extends DeviceEvent {
  /// Creates a detach event.
  const DeviceDetached(super.device);

  @override
  String toString() => 'DeviceDetached($device)';
}
