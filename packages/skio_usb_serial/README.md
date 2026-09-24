# skio_usb_serial

USB serial ports for Flutter on **Android** (USB OTG) and the **web** (Web
Serial in Chrome and Edge). Works with CP210x, CH340/CH9102, FTDI, CDC-ACM and
ESP32 native USB. Android calls the OS directly through JNI (jnigen), so there
are no platform channels.

> Status: in development. The Dart API and the Web Serial backend are in
> place; the Android backend is being added.

```dart
import 'package:skio_usb_serial/skio_usb_serial.dart';

final ports = await UsbSerialPort.list();
final port = await UsbSerialPort.open(
  ports.first,
  config: const SerialConfig(baudRate: 115200), // 8N1 by default
);

port.input.transform(const LineReader()).listen(print);
await port.write(utf8.encode('hello\n'));
await port.close();
```

On the web, the browser only lists ports the user has picked. Call
`UsbSerialPort.request()` from a button tap first.

## Features

- List ports and filter by vendor/product ID with `DeviceFilter`
- Baud rate, data bits, parity, stop bits, flow control
- Byte `Stream` input that buffers until you listen
- Ordered writes with timeouts
- DTR/RTS control, plus `dtr`/`rts` on open to avoid resetting ESP32 and
  Arduino boards
- `LineReader` handles lines and UTF-8 characters split across reads
- One error type for everything: `AccessDenied`, `DeviceBusy`,
  `Disconnected`, `OperationTimeout` and others from `skio_core`

## Testing your app without hardware

Replace the platform with a fake:

```dart
import 'package:skio_usb_serial/platform_interface.dart';

UsbSerialPlatform.instance = MyFakePlatform();
```

## The skio family

| Package | Purpose |
| --- | --- |
| `skio_core` | Shared types: access status, errors, device filters |
| `skio_usb_serial` | USB serial port (this package) |
| `uvc_camera` | USB Video Class camera |

Source and issues: [github.com/skio-flutter/skio](https://github.com/skio-flutter/skio).
