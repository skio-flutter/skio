import 'package:skio_core/skio_core.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceFilter', () {
    const cp2102 = DeviceHandle(
      id: '/dev/bus/usb/001/002',
      name: 'CP2102 USB to UART',
      vendorId: 0x10c4,
      productId: 0xea60,
      interfaceClasses: [0xff],
    );
    const sensor = DeviceHandle(
      id: 'AA:BB:CC:DD:EE:FF',
      name: 'Sensor-7',
      serviceUuids: ['6e400001-b5a3-f393-e0a9-e50e24dcca9e'],
    );

    test('empty filter matches everything', () {
      expect(const DeviceFilter().matches(cp2102), isTrue);
      expect(const DeviceFilter().matches(sensor), isTrue);
    });

    test('matches vendor and product IDs', () {
      expect(
        const DeviceFilter(vendorId: 0x10c4, productId: 0xea60).matches(cp2102),
        isTrue,
      );
      expect(const DeviceFilter(vendorId: 0x1a86).matches(cp2102), isFalse);
    });

    test('name prefix does not match a device without a name', () {
      const unnamed = DeviceHandle(id: 'x');
      expect(const DeviceFilter(namePrefix: 'Sensor').matches(sensor), isTrue);
      expect(
        const DeviceFilter(namePrefix: 'Sensor').matches(unnamed),
        isFalse,
      );
    });

    test('service UUIDs compare case-insensitively on the filter side', () {
      const filter = DeviceFilter(
        serviceUuids: ['6E400001-B5A3-F393-E0A9-E50E24DCCA9E'],
      );
      expect(filter.matches(sensor), isTrue);
      expect(filter.matches(cp2102), isFalse);
    });

    test('interface class', () {
      expect(const DeviceFilter(interfaceClass: 0xff).matches(cp2102), isTrue);
      expect(const DeviceFilter(interfaceClass: 0x0e).matches(cp2102), isFalse);
    });

    test('matchesAny', () {
      expect(DeviceFilter.matchesAny(const [], cp2102), isTrue);
      expect(
        DeviceFilter.matchesAny(const [
          DeviceFilter(vendorId: 0x1a86),
          DeviceFilter(vendorId: 0x10c4),
        ], cp2102),
        isTrue,
      );
    });
  });

  group('AccessReport', () {
    test('isUsable', () {
      expect(const AccessReport(AccessStatus.granted).isUsable, isTrue);
      expect(const AccessReport(AccessStatus.notRequired).isUsable, isTrue);
      expect(const AccessReport(AccessStatus.denied).isUsable, isFalse);
      expect(
        const AccessReport(AccessStatus.permanentlyDenied).isUsable,
        isFalse,
      );
    });
  });

  group('HardwareException', () {
    test('switch is exhaustive over the sealed family', () {
      String describe(HardwareException e) => switch (e) {
        AccessDenied() => 'denied',
        DeviceNotFound() => 'not found',
        DeviceBusy() => 'busy',
        Disconnected() => 'disconnected',
        OperationTimeout(:final timeout) => 'timeout ${timeout.inSeconds}s',
        Unsupported() => 'unsupported',
        ProtocolError() => 'protocol',
      };
      expect(
        describe(const OperationTimeout('read', timeout: Duration(seconds: 1))),
        'timeout 1s',
      );
    });

    test('toString includes device and cause', () {
      const e = DeviceBusy(
        'Port is open in another tab',
        device: DeviceHandle(id: 'p1', vendorId: 0x1a86, productId: 0x7523),
        cause: 'NetworkError',
      );
      expect(
        e.toString(),
        'DeviceBusy: Port is open in another tab '
        '[DeviceHandle(p1 1a86:7523)] (cause: NetworkError)',
      );
    });
  });
}
