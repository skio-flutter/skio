# skio_usb_serial

USB serial ports for Flutter on **Android** (USB OTG) and the **web** (Web
Serial in desktop Chrome and Edge). Works with CP210x, CH340/CH9102, FTDI,
PL2303, CDC-ACM and ESP32/RP2040 native USB. Android calls the OS directly
through JNI (jnigen), so there are no platform channels, and all queueing and
framing logic is Dart you can unit-test.

```dart
import 'dart:convert';

import 'package:skio_usb_serial/skio_usb_serial.dart';

final ports = await UsbSerialPort.list();
final device = ports.first;

final access = await UsbSerialPort.access.requestAccess(device);
if (!access.isUsable) return;

final port = await UsbSerialPort.open(
  device,
  config: const SerialConfig(baudRate: 115200), // 8N1 by default
);

port.input.transform(const LineReader()).listen(print);
await port.write(utf8.encode('hello\n'));
await port.close();
```

## Platforms

| | Android | Web |
| --- | --- | --- |
| How | USB host (OTG) + usb-serial-for-android | Web Serial API |
| Browsers / OS | Android 7.0+ (API 24) | Chrome and Edge on desktop, https or localhost |
| Finding ports | `list()` shows attached adapters | `request()` opens the browser chooser (from a tap); `list()` shows ports granted before |
| Permission | USB dialog per device: `access.requestAccess(device)` | Picking the port in the chooser is the permission |
| Attach/detach events | Yes (polled every second while listened) | Yes |
| Parity mark/space, 1.5 stop bits, DTR/DSR and XON/XOFF flow control | Depends on the chip | Not supported (`Unsupported`) |

## Setup

**Android:** nothing to add. The plugin declares `android.hardware.usb.host`
as optional, ships R8 keep rules, and needs no runtime permission. The
usb-serial-for-android library comes from JitPack; the plugin adds that
repository for its group only.

**Web:** serve over https (or localhost). Call `UsbSerialPort.request()` from a
button's `onPressed`, because browsers only show the chooser after a user
gesture.

## Features

- List ports and narrow them with `DeviceFilter(vendorId:, productId:)`
- Baud rate, data bits, parity, stop bits and flow control via `SerialConfig`
- Byte `Stream` input that buffers until you listen
- Writes in call order, never blocking the UI thread
- DTR/RTS with `setSignals()`, and `dtr`/`rts` in `SerialConfig` to set them
  on open
- `openDelay` for boards that reset when the port opens
- `LineReader` handles lines and UTF-8 characters split across reads
- Every error is a `HardwareException` from `skio_core`: `AccessDenied`,
  `DeviceNotFound`, `DeviceBusy`, `Disconnected`, `OperationTimeout`,
  `Unsupported`, `ProtocolError`

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| ESP32 or Arduino restarts when you connect | DTR/RTS toggle the board's reset line. Open with `SerialConfig(baudRate: 115200, dtr: false, rts: false)`. |
| Lines arrive cut in half | USB delivers chunks, not messages. Use `LineReader` or your own framing. |
| `DeviceBusy` on the web | The port is open in another tab or app. Close it there. |
| `DeviceBusy` on Android | Another app holds the device. Unplug and replug, then open again. |
| No ports on Android | The phone needs USB OTG, and some need OTG enabled in settings. Try a powered hub for boards that draw more current. |
| Chooser doesn't open on the web | `request()` wasn't called from a user gesture, or the page isn't https/localhost. |

## Testing your app without hardware

```dart
import 'package:skio_usb_serial/platform_interface.dart';

UsbSerialPlatform.instance = MyFakePlatform(); // extends UsbSerialPlatform
```

## Example

[`example/`](example) is a general-purpose serial terminal: pick a port, set
line settings, view text or hex, send text or hex, toggle DTR/RTS.

## The skio family

| Package | Purpose |
| --- | --- |
| `skio_core` | Shared types: access status, errors, device filters |
| `skio_usb_serial` | USB serial port (this package) |
| `uvc_camera` | USB Video Class camera |

## Licences

skio_usb_serial is BSD-3-Clause. On Android it bundles
[usb-serial-for-android](https://github.com/mik3y/usb-serial-for-android)
(MIT).

Source and issues: [github.com/skio-flutter/skio](https://github.com/skio-flutter/skio).
