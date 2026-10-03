import 'package:skio_core/skio_core.dart';

import 'iokit.dart';

/// Built-in ports that are never a device someone plugged in.
const _ignored = {'/dev/cu.Bluetooth-Incoming-Port', '/dev/cu.debug-console'};

/// Serial ports on macOS, from IOKit. Each id is the `/dev/cu.*` path, which
/// opens without waiting for carrier detect.
List<DeviceHandle> listDarwinPorts() => [
  for (final port in listSerialPorts())
    if (!_ignored.contains(port.calloutPath))
      DeviceHandle(
        id: port.calloutPath,
        name: port.productName ?? port.calloutPath.split('/').last,
        vendorId: port.vendorId,
        productId: port.productId,
        serialNumber: port.serialNumber,
      ),
]..sort((a, b) => a.id.compareTo(b.id));
