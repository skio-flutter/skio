// Parses the device instance IDs and names Windows reports for COM ports.
// Plain Dart, so it can be tested on any system.

/// USB details from a device instance ID.
typedef UsbIds = ({int vendorId, int productId, String? serialNumber});

final _vid = RegExp(r'VID_([0-9A-F]{4})', caseSensitive: false);
final _pid = RegExp(r'PID_([0-9A-F]{4})', caseSensitive: false);
final _ftdiSerial = RegExp(r'PID_[0-9A-F]{4}\+([^\\+]+)', caseSensitive: false);

/// Reads the vendor ID, product ID and serial number from a device instance
/// ID, or returns `null` when the device isn't on USB (built-in UARTs such
/// as `ACPI\PNP0501\1`, Bluetooth ports under `BTHENUM\`).
///
/// - `USB\VID_1A86&PID_7523\5&2B5B5E1&0&2`: no serial number; Windows made
///   up the last part (it contains `&`).
/// - `USB\VID_2E8A&PID_000A\E6614C311B1F9A2C`: serial `E6614C311B1F9A2C`.
/// - `FTDIBUS\VID_0403+PID_6001+A50285BIA\0000`: FTDI's own driver puts the
///   serial after the product ID.
/// - `USB\VID_303A&PID_1001&MI_00\6&1D3A2B&0&0000`: one interface of a
///   composite device; its serial number is on the parent (see
///   [isInterfaceId]).
UsbIds? parseUsbInstanceId(String id) {
  final vid = _vid.firstMatch(id);
  final pid = _pid.firstMatch(id);
  if (vid == null || pid == null) return null;

  String? serial;
  if (_ftdiSerial.firstMatch(id) case final ftdi?) {
    serial = ftdi.group(1);
  } else if (!isInterfaceId(id)) {
    final parts = id.split(r'\');
    final last = parts.length >= 3 ? parts.last : '';
    if (last.isNotEmpty && !last.contains('&')) serial = last;
  }
  return (
    vendorId: int.parse(vid.group(1)!, radix: 16),
    productId: int.parse(pid.group(1)!, radix: 16),
    serialNumber: serial,
  );
}

/// Whether [id] names one interface (`MI_xx`) of a composite USB device,
/// such as the serial port of an ESP32-S3 or RP2040 with native USB. Its
/// serial number is on the parent device.
bool isInterfaceId(String id) =>
    RegExp(r'[&\\]MI_[0-9A-F]{2}', caseSensitive: false).hasMatch(id);

/// Removes the ` (COM3)` Windows adds to a port's friendly name, so
/// `USB-SERIAL CH340 (COM3)` becomes `USB-SERIAL CH340`.
String trimPortSuffix(String friendlyName, String port) {
  final suffix = ' ($port)';
  final name = friendlyName.trim();
  return name.toUpperCase().endsWith(suffix.toUpperCase())
      ? name.substring(0, name.length - suffix.length).trim()
      : name;
}
