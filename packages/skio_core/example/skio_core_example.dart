// ignore_for_file: avoid_print
import 'package:skio_core/skio_core.dart';

void main() {
  // Pick USB serial adapters by vendor ID (CP210x and CH340).
  const filters = [
    DeviceFilter(vendorId: 0x10c4),
    DeviceFilter(vendorId: 0x1a86),
  ];
  const device = DeviceHandle(id: 'usb-1', vendorId: 0x1a86, productId: 0x7523);
  print('Matches: ${DeviceFilter.matchesAny(filters, device)}');

  // Handle every skio error the same way, whichever plugin threw it.
  try {
    throw const Disconnected('Cable unplugged', device: device);
  } on HardwareException catch (e) {
    final text = switch (e) {
      AccessDenied() => 'Please allow access to the device.',
      Disconnected() || DeviceNotFound() => 'Reconnect the device.',
      DeviceBusy() => 'Close other apps or tabs using the device.',
      OperationTimeout() => 'The device did not answer. Try again.',
      Unsupported() || ProtocolError() => e.message,
    };
    print(text);
  }
}
