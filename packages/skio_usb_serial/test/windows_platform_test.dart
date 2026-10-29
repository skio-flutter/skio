// Checks the Windows platform's bindings against the real kernel32,
// advapi32, setupapi and cfgmgr32. CI machines have no USB serial devices,
// so opening is tested by its errors.
@TestOn('windows')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/platform_interface.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';
import 'package:skio_usb_serial/src/windows/kernel32.dart';
import 'package:skio_usb_serial/src/windows/setupapi.dart';
import 'package:skio_usb_serial/src/windows/usb_serial_windows.dart';

void main() {
  setUp(() => UsbSerialPlatform.instance = WindowsUsbSerialPlatform());

  test('every function resolves', () {
    // Each look-up is lazy; touching it finds typos in names or libraries.
    final functions = <Object>[
      Win32.CreateFileW,
      Win32.CloseHandle,
      Win32.GetLastError,
      Win32.GetCommState,
      Win32.SetCommState,
      Win32.SetCommTimeouts,
      Win32.SetupComm,
      Win32.ReadFile,
      Win32.WriteFile,
      Win32.GetOverlappedResult,
      Win32.CancelIoEx,
      Win32.CreateEventW,
      Win32.SetEvent,
      Win32.ResetEvent,
      Win32.WaitForSingleObject,
      Win32.WaitForMultipleObjects,
      Win32.EscapeCommFunction,
      Win32.PurgeComm,
      Win32.RegQueryValueExW,
      Win32.RegCloseKey,
      SetupApi.SetupDiGetClassDevsW,
      SetupApi.SetupDiEnumDeviceInfo,
      SetupApi.SetupDiGetDeviceInstanceIdW,
      SetupApi.SetupDiGetDeviceRegistryPropertyW,
      SetupApi.SetupDiOpenDevRegKey,
      SetupApi.SetupDiDestroyDeviceInfoList,
      SetupApi.CM_Get_Parent,
      SetupApi.CM_Get_Device_IDW,
    ];
    expect(functions, hasLength(28));
  });

  test('listing runs and returns only USB COM ports', () async {
    // Built-in or virtual COM ports may exist on the machine; they must not
    // appear, and every listed port must carry USB IDs.
    for (final port in listComPorts()) {
      expect(port.port, startsWith('COM'));
    }
    for (final device in await UsbSerialPort.list()) {
      expect(device.id, matches(RegExp(r'^COM\d+$')));
      expect(device.vendorId, isNotNull);
      expect(device.productId, isNotNull);
    }
  });

  test('access needs no prompt and there is no chooser', () async {
    expect(
      (await UsbSerialPort.access.checkAccess()).status,
      AccessStatus.notRequired,
    );
    expect(UsbSerialPort.requiresUserSelection, isFalse);
    await expectLater(UsbSerialPort.request(), throwsA(isA<Unsupported>()));
  });

  test('a missing port is not found', () async {
    await expectLater(
      UsbSerialPort.open(
        const DeviceHandle(id: 'COM250'),
        config: const SerialConfig(baudRate: 9600),
      ),
      throwsA(isA<DeviceNotFound>()),
    );
  });

  test('a path that is not a COM name is not found', () async {
    await expectLater(
      UsbSerialPort.open(
        const DeviceHandle(id: '/dev/ttyUSB0'),
        config: const SerialConfig(baudRate: 9600),
      ),
      throwsA(isA<DeviceNotFound>()),
    );
  });
}
