import 'dart:io';

import 'package:skio_core/skio_core.dart';

/// Serial ports on Linux and Android, from sysfs.
///
/// Every tty backed by real hardware has a `device` link under
/// `/sys/class/tty`; virtual consoles and pseudo-terminals don't. USB ports
/// get their vendor and product IDs from the USB device above them.
///
/// Android often blocks sysfs for apps. Then the device nodes in `/dev` are
/// listed by name instead, and if that is blocked too the list is empty;
/// `open` still works with a known path.
List<DeviceHandle> listLinuxPorts() {
  final ports = _fromSysfs() ?? _fromDev();
  return ports..sort((a, b) => _naturalCompare(a.id, b.id));
}

List<DeviceHandle>? _fromSysfs() {
  try {
    final entries = Directory('/sys/class/tty').listSync();
    if (entries.isEmpty) return null;
    final ports = <DeviceHandle>[];
    for (final entry in entries) {
      final name = entry.path.split('/').last;
      final device = Directory('${entry.path}/device');
      if (!device.existsSync()) continue;
      // The 8250 driver registers ttyS0..ttyS31 whether or not the UART
      // exists; missing ones report port type 0 (unknown).
      if (_readTrimmed('${entry.path}/type') == '0') continue;
      final usb = _usbDevice(device.resolveSymbolicLinksSync());
      ports.add(
        DeviceHandle(
          id: '/dev/$name',
          name: usb?.product == null ? name : '${usb!.product} ($name)',
          vendorId: usb?.vendorId,
          productId: usb?.productId,
          serialNumber: usb?.serial,
        ),
      );
    }
    return ports;
  } on FileSystemException {
    return null;
  }
}

/// Device node names that are serial ports on common boards and panels.
final _serialNode = RegExp(
  r'^tty(S|HS|AMA|THS|TCU|USB|ACM|MSM|MT|SAC|GS|XRUSB|mxc|ACT|AS|O|LP)\d+$',
);

List<DeviceHandle> _fromDev() {
  try {
    return [
      for (final entry in Directory('/dev').listSync(followLinks: false))
        if (_serialNode.hasMatch(entry.path.split('/').last))
          DeviceHandle(id: entry.path, name: entry.path.split('/').last),
    ];
  } on FileSystemException {
    return [];
  }
}

typedef _Usb = ({int vendorId, int productId, String? product, String? serial});

/// Walks up from a tty's device directory to the USB device it belongs to.
_Usb? _usbDevice(String path) {
  for (
    var dir = path;
    dir.startsWith('/sys/devices/') && dir.length > '/sys/devices/'.length;
    dir = dir.substring(0, dir.lastIndexOf('/'))
  ) {
    final vendor = _readTrimmed('$dir/idVendor');
    if (vendor == null) continue;
    final product = _readTrimmed('$dir/idProduct');
    return (
      vendorId: int.tryParse(vendor, radix: 16) ?? 0,
      productId: int.tryParse(product ?? '', radix: 16) ?? 0,
      product: _readTrimmed('$dir/product'),
      serial: _readTrimmed('$dir/serial'),
    );
  }
  return null;
}

String? _readTrimmed(String path) {
  try {
    final value = File(path).readAsStringSync().trim();
    return value.isEmpty ? null : value;
  } on FileSystemException {
    return null;
  }
}

/// Orders `ttyS2` before `ttyS10`.
int _naturalCompare(String a, String b) {
  final digits = RegExp(r'(\d+)$');
  final ma = digits.firstMatch(a);
  final mb = digits.firstMatch(b);
  if (ma != null && mb != null) {
    final prefix = a.substring(0, ma.start).compareTo(b.substring(0, mb.start));
    if (prefix != 0) return prefix;
    return int.parse(ma[1]!).compareTo(int.parse(mb[1]!));
  }
  return a.compareTo(b);
}
