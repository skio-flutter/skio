// Checks the Windows backend's bindings against the real kernel32 and
// advapi32. CI machines have no COM ports, so opening is tested by its
// errors.
@TestOn('windows')
library;

import 'package:skio_uart/skio_uart.dart';
import 'package:skio_uart/src/backend.dart';
import 'package:skio_uart/src/windows/kernel32.dart';
import 'package:skio_uart/src/windows/windows_backend.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => SerialBackend.instance = WindowsBackend());

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
      Win32.GetCommModemStatus,
      Win32.PurgeComm,
      Win32.SetCommBreak,
      Win32.ClearCommBreak,
      Win32.ClearCommError,
      Win32.RegOpenKeyExW,
      Win32.RegEnumValueW,
      Win32.RegCloseKey,
    ];
    expect(functions, hasLength(25));
  });

  test('list returns COM names', () async {
    for (final port in await SerialPort.list()) {
      expect(port.id, matches(RegExp(r'^[A-Za-z]')));
    }
  });

  test('a missing port is not found', () async {
    await expectLater(
      SerialPort.open('COM250', config: const SerialConfig(baudRate: 9600)),
      throwsA(
        isA<DeviceNotFound>().having((e) => e.device?.id, 'device', 'COM250'),
      ),
    );
  });

  test('a Unix path is not a port name', () async {
    await expectLater(
      SerialPort.open('/dev/ttyS0', config: const SerialConfig(baudRate: 9600)),
      throwsA(isA<DeviceNotFound>()),
    );
  });
}
