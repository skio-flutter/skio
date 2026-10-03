// Lists USB serial ports from sysfs, with the USB details of each port's
// parent device.

import 'dart:io';

/// A USB serial port as sysfs reports it.
final class SysfsSerialPort {
  /// Creates a port description.
  const SysfsSerialPort({
    required this.devicePath,
    required this.usbDevicePath,
    required this.vendorId,
    required this.productId,
    this.serialNumber,
    this.productName,
    this.vendorName,
  });

  /// The `/dev/tty*` path, for example `/dev/ttyUSB0` or `/dev/ttyACM0`.
  final String devicePath;

  /// The sysfs directory of the USB device the port belongs to. Ports of a
  /// multi-port adapter share it.
  final String usbDevicePath;

  /// USB vendor ID.
  final int vendorId;

  /// USB product ID.
  final int productId;

  /// USB serial number string.
  final String? serialNumber;

  /// USB product string.
  final String? productName;

  /// USB vendor string.
  final String? vendorName;
}

/// Returns every tty under [classDir] that belongs to a USB device, sorted
/// by device path. Built-in UARTs (`ttyS*`) and virtual terminals are left
/// out because no USB device is among their parents.
List<SysfsSerialPort> listUsbSerialPorts({
  String classDir = '/sys/class/tty',
  String devDir = '/dev',
}) {
  final List<FileSystemEntity> entries;
  try {
    entries = Directory(classDir).listSync(followLinks: false);
  } on FileSystemException {
    return const [];
  }
  final ports = <SysfsSerialPort>[];
  for (final entry in entries) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final String device;
    try {
      // Missing for virtual ttys (tty0, pts, console).
      device = Directory('${entry.path}/device').resolveSymbolicLinksSync();
    } on FileSystemException {
      continue;
    }
    final usb = _usbParent(device);
    if (usb == null) continue;
    final vendorId = _hex(_read(usb, 'idVendor'));
    final productId = _hex(_read(usb, 'idProduct'));
    if (vendorId == null || productId == null) continue;
    ports.add(
      SysfsSerialPort(
        devicePath: '$devDir/$name',
        usbDevicePath: usb,
        vendorId: vendorId,
        productId: productId,
        serialNumber: _read(usb, 'serial'),
        productName: _read(usb, 'product'),
        vendorName: _read(usb, 'manufacturer'),
      ),
    );
  }
  ports.sort((a, b) => a.devicePath.compareTo(b.devicePath));
  return ports;
}

/// The nearest directory at or above [path] with an `idVendor` file, which
/// is the USB device (interfaces and usb-serial ports sit below it).
String? _usbParent(String path) {
  var dir = Directory(path);
  // A real sysfs path is never this deep; the limit guards against loops.
  for (var i = 0; i < 16; i++) {
    if (File('${dir.path}/idVendor').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

String? _read(String dir, String file) {
  try {
    final value = File('$dir/$file').readAsStringSync().trim();
    return value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

int? _hex(String? value) =>
    value == null ? null : int.tryParse(value, radix: 16);
