# skio_uart

[![pub package](https://img.shields.io/pub/v/skio_uart.svg)](https://pub.dev/packages/skio_uart)
[![pub points](https://img.shields.io/pub/points/skio_uart)](https://pub.dev/packages/skio_uart/score)
[![CI](https://github.com/skio-flutter/skio/actions/workflows/ci.yaml/badge.svg)](https://github.com/skio-flutter/skio/actions/workflows/ci.yaml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/skio-flutter/skio/blob/main/LICENSE)

Open **serial ports by path** from Flutter or plain Dart: the **UART,
RS-232 and RS-485 ports** built into **Android HMI panels** (`/dev/ttyS3`),
**Jetson and Raspberry Pi** boards (`/dev/ttyTHS1`, `/dev/ttyAMA0`),
**Windows COM ports** (`COM3`), and USB serial adapters on **Linux and
macOS** (`/dev/ttyUSB0`, `/dev/cu.usbserial-0001`). Connect a sensor, a
meter, a PLC or a microcontroller and **send and receive bytes or text**.

It is **pure Dart FFI**: the package calls the operating system directly
(libc on Android, Linux and macOS, kernel32 on Windows), so there is **no
C, Java, Kotlin or Swift to compile**, no CMake, CocoaPods or Swift Package
Manager setup, and it also runs in Dart command-line tools.

Part of the [skio](https://github.com/skio-flutter/skio) family of Flutter
hardware plugins.

## Contents

- [Which package do I need?](#which-package-do-i-need)
- [Platforms](#platforms)
- [Install](#install)
- [Quick start](#quick-start)
- [Features](#features)
- [Wiring a UART device](#wiring-a-uart-device)
- [Errors and what to do](#errors-and-what-to-do)
- [Debug logging](#debug-logging)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Example app](#example-app)
- [Testing your app without hardware](#testing-your-app-without-hardware)
- [FAQ](#faq)
- [Compared with other packages](#compared-with-other-packages)
- [How it works](#how-it-works)

## Which package do I need?

| Your setup | Package |
| --- | --- |
| A port built into the device: an Android panel's `/dev/ttyS*`, a Jetson's `/dev/ttyTHS*`, a Raspberry Pi's `/dev/ttyAMA0` | **skio_uart** |
| A Windows or Linux PC, with any serial port or USB adapter | **skio_uart** |
| A phone with a USB serial adapter or board on an OTG cable | [`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) |
| A web app (Chrome, Edge) | [`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) |
| A USB adapter on macOS | Either; both use the same `SerialConfig` and errors |

A phone has no UART pins, and Android only lets normal apps reach USB
adapters through its USB permission dialog, which `skio_usb_serial` handles.
Android panels and boards wire their UARTs to the processor, and the system
shows them as `/dev/tty*` files, which is what this package opens.

## Platforms

| Feature | Android | Linux | Windows | macOS |
| --- | --- | --- | --- | --- |
| Ports | Built-in UARTs (`/dev/ttyS*`, `/dev/ttyHS*`, ...) and `/dev/ttyUSB*`, `/dev/ttyACM*` where the system allows | Any tty: `/dev/ttyS*`, `/dev/ttyTHS*`, `/dev/ttyAMA*`, `/dev/ttyUSB*`, `/dev/ttyACM*`, `/dev/serial/by-id/*` | Any COM port | Any `/dev/cu.*` |
| Finding ports | From sysfs where readable; otherwise open by path | From sysfs, with USB vendor and product IDs | From the registry | From IOKit, with USB details |
| Baud rate | Any rate the UART supports | Any rate the UART supports | Any rate the driver supports | Any rate |
| Data bits, parity, stop bits | 5–8; none, odd, even, mark, space; 1 or 2 | Same as Android | 5–8; all parities; 1, 1.5 or 2 | 5–8; none, odd, even; 1 or 2 |
| Flow control | RTS/CTS, XON/XOFF | RTS/CTS, XON/XOFF | RTS/CTS, DTR/DSR, XON/XOFF | RTS/CTS, DTR/DSR, XON/XOFF |
| DTR/RTS out, CTS/DSR/DCD/RI in | Where the port has the lines | Same | Yes | Yes |
| Break, flush, drain | Yes | Yes | Yes | Yes |
| Added and removed ports | Checked once a second | Checked once a second | Checked once a second | Checked once a second |

iOS and the web have no serial ports apps can open; there, `list` is empty
and `open` throws `Unsupported`.

Linux support covers arm, arm64, x86, x86-64 and RISC-V, which includes
every Android device, Jetson, Raspberry Pi and PC. (MIPS, PowerPC and SPARC
use different kernel constants and are not supported.)

## Install

```bash
flutter pub add skio_uart     # Flutter apps
dart pub add skio_uart        # Dart command-line tools
```

There is nothing else to set up on Android, Linux or Windows: no
permissions in the manifest and no native build.

**Android panels:** the port file must be readable and writable by apps.
Many industrial panels ship that way; on others the panel maker provides a
build or a setting for it. Check with:

```bash
adb shell ls -lZ /dev/ttyS3
```

`crw-rw-rw-` means any app can open it. If it is `crw-------` or
`crw-rw----` and owned by `root` or `system`, `open` throws `AccessDenied`;
ask the panel maker how to give apps access.

**Linux:** your user must be allowed to open serial ports, usually by
being in the `dialout` group:

```bash
sudo usermod -aG dialout $USER
```

Log out and in again afterwards.

**macOS:** sandboxed apps need the serial entitlement in both
`macos/Runner/DebugProfile.entitlements` and
`macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.device.serial</key>
<true/>
```

## Quick start

```dart
import 'dart:convert';

import 'package:skio_uart/skio_uart.dart';

Future<void> readSensor() async {
  // 1. Open the port: 9600 baud, 8 data bits, no parity, 1 stop bit.
  final port = await SerialPort.open(
    '/dev/ttyS3', // 'COM3' on Windows, '/dev/ttyTHS1' on a Jetson
    config: const SerialConfig(baudRate: 9600),
  );

  // 2. Print every line the device sends.
  port.input.transform(const LineReader()).listen(print);

  // 3. Send a command.
  await port.write(utf8.encode('READ\r\n'));

  // ...later
  await port.close();
}
```

## Features

### Find serial ports

```dart
final ports = await SerialPort.list();
for (final p in ports) {
  print('${p.id}  ${p.name}  ${p.vendorId}:${p.productId}');
}
// /dev/ttyS1  ttyS1  null:null
// /dev/ttyUSB0  CP2102 USB to UART Bridge Controller (ttyUSB0)  4292:60000
```

Each `id` is the path to pass to `open`. USB ports carry their vendor and
product IDs, so you can pick one with a filter:

```dart
final cp2102 = await SerialPort.list(
  filters: const [DeviceFilter(vendorId: 0x10c4, productId: 0xea60)],
);
```

On Linux the list leaves out the `ttyS*` entries the kernel creates for
UARTs that don't exist. On Android the system often hides this
information from apps; then the list may be empty, and you open the port
by the path from the panel's manual.

### Open a port with the right settings

`SerialConfig` describes the line settings; the defaults are 8 data bits,
no parity, 1 stop bit (8N1) and no flow control:

```dart
const config = SerialConfig(
  baudRate: 19200,
  dataBits: 8,
  parity: Parity.even,
  stopBits: StopBits.one,
  flowControl: FlowControl.none,
);
final port = await SerialPort.open('/dev/ttyS1', config: config);
```

Settings the platform can't apply throw `Unsupported` (see
[Platforms](#platforms)).

### Receive data

```dart
port.input.listen((Uint8List bytes) {
  print('got ${bytes.length} bytes');
});
```

Bytes arrive in whatever chunks the driver had ready, not as messages.
Data that arrives before you listen is kept, so a device's first message
isn't lost. If the port goes away (a USB adapter is unplugged), `input`
emits `Disconnected` and closes.

### Read text line by line

```dart
port.input.transform(const LineReader()).listen((line) {
  print(line); // without the \n, \r\n or \r
});
```

`LineReader` joins lines split across chunks and handles UTF-8 characters
split across chunks.

### Send data

```dart
await port.write(utf8.encode('hello\r\n'));            // text
await port.write([0x01, 0x03, 0x00, 0x00, 0x00, 0x02, 0xC4, 0x0B]); // bytes
```

Writes are sent in call order. `write` completes once the system has
taken the data; `drain` waits until the last byte has left the port:

```dart
await port.write(frame);
await port.drain();
```

### Control and read the modem lines

```dart
await port.setSignals(dtr: true, rts: false);
final status = await port.getSignals();
print('CTS ${status.cts}, DSR ${status.dsr}');
```

Pass `dtr: false, rts: false` in `SerialConfig` to set them right when the
port opens; boards with an auto-reset circuit (ESP32, Arduino) otherwise
restart. Many panel UARTs only have TX and RX; on those, the lines read as
off or throw `ProtocolError`.

### Flush and send a break

```dart
await port.flush();            // discard unread input and unsent output
await port.flush(output: false); // only discard input
await port.sendBreak();        // hold TX low for 250 ms
```

### Know when a port is added or removed

```dart
SerialPort.events.listen((event) {
  switch (event) {
    case DeviceAttached(:final device):
      print('added ${device.id}');
    case DeviceDetached(:final device):
      print('removed ${device.id}');
  }
});
```

Ports are checked once a second while you listen. This matters for USB
adapters; built-in UARTs don't come and go.

### Close the port

```dart
await port.close();
```

Closing is safe to call more than once. `port.done` completes when the
port closes, whether by `close` or because it went away.

## Wiring a UART device

| Your device | Port (panel, board or adapter) |
| --- | --- |
| TX | RX |
| RX | TX |
| GND | GND |

- **Cross TX and RX**, and always connect GND.
- **Match the voltage.** Jetson and Raspberry Pi header pins are 3.3 V;
  5 V signals can damage them. Panel connectors marked RS-232 use ±12 V
  and must never be wired to 3.3 V or 5 V pins directly.
- **RS-485** uses two wires, A and B (plus GND), and only one side talks at
  a time. Most panels switch their RS-485 transceiver between sending and
  receiving automatically, so a plain `SerialPort` works. Built-in kernel
  RS-485 mode is planned.
- **Quick test without a device:** connect the port's TX to its own RX with
  a jumper wire. Everything you send comes straight back.

## Errors and what to do

Every error is a `HardwareException` (from
[`skio_core`](https://pub.dev/packages/skio_core)), so one `try`/`catch`
covers them all. Messages say what to do:

```dart
try {
  final port = await SerialPort.open('/dev/ttyS3', config: config);
} on HardwareException catch (e) {
  showMessage(e.message);
}
```

| Error | What it means | What to do |
| --- | --- | --- |
| `AccessDenied` | The system doesn't let this app open the port. | Android: the panel's system image must allow it (see [Install](#install)). Linux: join the `dialout` group. macOS: add the entitlement. |
| `DeviceBusy` | Another app has the port open, or this app already does. On Windows this includes ports Windows itself reports as "access denied". | Close serial monitors, IDEs and consoles using the port. On a Jetson, stop the serial console service if it uses the port. |
| `DeviceNotFound` | No port at that path or name. | Check the path; panel manuals list their ports. On Windows, check Device Manager under "Ports (COM & LPT)". |
| `Disconnected` | The port went away while in use, or it is closed. | Check the cable, then open again. |
| `OperationTimeout` | The port didn't accept data in time. | Usually flow control: the other side isn't raising CTS. Turn flow control off or wire CTS. |
| `Unsupported` | A setting this platform can't apply, or a platform without serial ports. | 8N1 without flow control works everywhere. |
| `ProtocolError` | The path isn't a serial port, or the port lacks a feature (for example modem lines). | Check the path; see [debug logging](#debug-logging). |

## Debug logging

Logging is off by default. Turn it on to see every byte sent and
received:

```dart
SkioLog.level = LogLevel.trace; // info, debug or trace (every byte in hex)
SkioLog.records.listen(print);
```

```
2026-10-03T10:36:38.326 INFO skio_uart [/dev/ttyS3]: Opened with SerialConfig(9600 8N1, flow: none)
2026-10-03T10:36:38.358 TRACE skio_uart [/dev/ttyS3]: TX 8: 01 03 00 00 00 02 c4 0b
2026-10-03T10:36:38.371 TRACE skio_uart [/dev/ttyS3]: RX 9: 01 03 04 03 f5 00 00 fa 5d
```

Nothing is ever sent anywhere by the package.

## Troubleshooting

| Problem | Likely cause and fix |
| --- | --- |
| Garbled characters | Wrong baud rate or parity. Use the device's documented settings. |
| Nothing received | TX and RX not crossed, GND missing, wrong port, or the device needs a command before it sends. Try the TX–RX jumper test first. |
| `AccessDenied` on an Android panel | The port isn't open to apps. Check `adb shell ls -lZ /dev/ttyS3` and ask the panel maker. |
| `list` is empty on Android | Android hides sysfs from apps on many systems. Open the port by path. |
| `DeviceBusy` on a Jetson or Raspberry Pi | The serial console uses that UART. Disable the console on that port (for example the `nvgetty` service on Jetson, or the serial console in `raspi-config`). |
| Random characters appear on a Raspberry Pi | The Linux console is writing to the port. Disable the serial console. |
| The board restarts when you connect | DTR/RTS reset it. Open with `SerialConfig(..., dtr: false, rts: false)`. |
| Writes time out | RTS/CTS flow control is on but CTS isn't wired. Turn it off. |

## Limitations

- **New package:** it is covered by automated tests against
  pseudo-terminals on Linux and macOS, and by unit tests for Windows
  settings. Reports from real panels, boards and adapters are very welcome
  ([open an issue](https://github.com/skio-flutter/skio/issues)).
- Linux and Android have no DTR/DSR flow control and no 1.5 stop bits;
  macOS has no mark/space parity and no 1.5 stop bits. These throw
  `Unsupported`.
- `drain` on Windows waits for the driver's buffer, not the UART's last few
  bytes in hardware.
- Windows port names come from the registry; USB vendor and product IDs are
  not shown there yet.
- No built-in RS-485 direction control or Modbus yet; both are planned.

## Example app

[`example/`](example) is a complete serial terminal for Android, Linux,
Windows and macOS: type a port path or pick a detected port, choose the
settings, and send text or hex. It shows the modem lines and has a Logs
page.

```bash
cd example
flutter run -d linux     # or windows, macos, or an Android panel
```

## Testing your app without hardware

On Linux and macOS a pseudo-terminal behaves like a serial port. The
package's own tests open one with `openpty` and talk to it through
`SerialPort`; see
[`test/posix_pty_test.dart`](test/posix_pty_test.dart). On Windows,
[com0com](https://com0com.sourceforge.net/) creates pairs of linked
virtual COM ports.

## FAQ

**How do I read a sensor connected to an Android panel's RS-232 or RS-485
port from Flutter?**
Find the port's path in the panel's manual (often `/dev/ttyS1` to
`/dev/ttyS4`), wire the sensor, and use `SerialPort.open(path, config:
SerialConfig(baudRate: ...))` as in the [quick start](#quick-start). If it
throws `AccessDenied`, see [Install](#install).

**How do I use the UART pins on a Jetson or Raspberry Pi?**
Open `/dev/ttyTHS1` (Jetson header pins 8 and 10; check your module's
pinout) or `/dev/serial0` (Raspberry Pi), after adding your user to
`dialout` and disabling the serial console on that port.

**Can I use it on a phone?**
Phones have no UART pins. Use a USB serial adapter with
[`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial), which handles
Android's USB permission.

**Does it need root on Android?**
No, as long as the panel's system lets apps open the port. The package
never asks for root.

**Can I use it without Flutter?**
Yes. It depends only on `dart:ffi`, so it works in Dart command-line tools,
for example on a Jetson.

**Does it support Modbus RTU?**
Not yet. You can send and receive Modbus frames as bytes today; a Modbus
package on top of skio_uart is planned.

**Does it collect data or use the network?**
No. The package has no network access and no telemetry.

## Compared with other packages

A fair summary to help you choose (as of October 2026):

| Package | Android built-in UARTs | Linux | Windows | macOS | Native build step |
| --- | --- | --- | --- | --- | --- |
| **skio_uart** | Yes | Yes | Yes | Yes | None (pure Dart FFI) |
| [flutter_libserialport](https://pub.dev/packages/flutter_libserialport) | Yes | Yes | Yes | Yes | Builds the libserialport C library |
| [serial_port_win32](https://pub.dev/packages/serial_port_win32) | No | No | Yes | No | None |
| [skio_usb_serial](https://pub.dev/packages/skio_usb_serial) | No (USB adapters only) | No | No | Yes | None |

## How it works

On Android, Linux and macOS the package opens the port's device file with
`open`, sets it up with the kernel's termios interface (on Linux the
`termios2` ioctls, which take any baud rate), and reads on a background
isolate that waits in `poll`, so the UI never blocks. On Windows it opens
the COM port for overlapped I/O and reads on a background isolate the same
way. Everything goes through `dart:ffi` straight to the operating system;
there is no native code in the package. Queueing, line reading and error
handling are Dart code shared with `skio_usb_serial`.

## The skio family

| Package | What it does |
| --- | --- |
| [`skio_core`](https://pub.dev/packages/skio_core) | Shared types used by all skio packages: permissions, errors, serial settings, logging |
| `skio_uart` | Serial ports by path: built-in UARTs, COM ports, adapters on desktop (this package) |
| [`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) | USB serial adapters on Android phones, macOS and the web |
| [`skio_uvc_camera`](https://pub.dev/packages/skio_uvc_camera) | USB cameras: preview, photos, snapshot button |

## License

BSD 3-Clause.
