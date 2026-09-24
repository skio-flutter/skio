# skio_usb_serial

Talk to **USB serial devices** from a Flutter app: Arduino and ESP32 boards,
USB-to-serial adapters (CH340, CP210x, FTDI, PL2303), GPS modules, scales,
barcode readers, lab instruments and anything else that shows up as a serial
port. **Send and receive bytes or text** on **Android** (with a USB OTG
cable) and in the **browser** (Chrome and Edge, using Web Serial).

Part of the [skio](https://github.com/skio-flutter/skio) family of Flutter
hardware plugins.

## Contents

- [Platforms](#platforms)
- [Install](#install)
- [Quick start](#quick-start)
- [Features](#features)
  - [Find serial ports](#find-serial-ports)
  - [Let the user pick a port (web)](#let-the-user-pick-a-port-web)
  - [Ask for permission (Android)](#ask-for-permission-android)
  - [Open a port with the right settings](#open-a-port-with-the-right-settings)
  - [Receive data](#receive-data)
  - [Read text line by line](#read-text-line-by-line)
  - [Send data](#send-data)
  - [Control DTR and RTS (and avoid board resets)](#control-dtr-and-rts-and-avoid-board-resets)
  - [Know when a device is plugged in or out](#know-when-a-device-is-plugged-in-or-out)
  - [Close the port](#close-the-port)
- [Errors and what to do](#errors-and-what-to-do)
- [Debug logging](#debug-logging)
- [Troubleshooting](#troubleshooting)
- [Tested hardware](#tested-hardware)
- [Limitations](#limitations)
- [Example app](#example-app)
- [Testing your app without hardware](#testing-your-app-without-hardware)

## Platforms

| Feature | Android | Web (Chrome, Edge) |
| --- | --- | --- |
| How it connects | USB host (OTG) cable or adapter | Web Serial API |
| Finding ports | Lists every attached adapter | The user picks a port in a browser popup; picked ports are remembered |
| Permission | A USB dialog for each device | Picking the port in the popup is the permission |
| Send and receive | Yes | Yes |
| Baud rate, data bits, parity, stop bits | Yes | Yes (7 or 8 data bits; parity none, odd or even; 1 or 2 stop bits) |
| Hardware flow control (RTS/CTS) | Yes, if the chip supports it | Yes |
| DTR/DSR and XON/XOFF flow control | Yes, if the chip supports it | No |
| DTR and RTS lines | Yes | Yes |
| Plug and unplug events | Yes (checked once a second) | Yes |
| Minimum version | Android 7.0 (API 24) | Desktop Chrome or Edge, page served over https or localhost |

Safari, Firefox, iOS, macOS apps, Windows apps and Linux apps are not
supported yet. On those platforms the package reports
`AccessStatus.unsupported` instead of failing.

**Supported chips on Android:** CH340/CH341/CH9102, CP210x, FTDI (FT232,
FT2232, ...), Prolific PL2303, and CDC-ACM devices such as Arduino boards and
ESP32/RP2040 native USB. Adapters with several ports (for example FT2232)
show one entry per port.

## Install

```bash
flutter pub add skio_usb_serial
```

**Android:** nothing else to add. The package needs no runtime permission,
declares USB host as optional (so your app still installs on phones without
it), and includes the rules that keep release builds working with code
shrinking. The Android library it uses (usb-serial-for-android) comes from
JitPack; the package adds that repository for you.

**Web:** serve the page over **https** (or `http://localhost` while
developing), and open it in desktop Chrome or Edge.

## Quick start

```dart
import 'dart:convert';

import 'package:skio_usb_serial/skio_usb_serial.dart';

Future<void> talkToBoard() async {
  // On the web, first let the user pick the port (from a button press):
  if (UsbSerialPort.requiresUserSelection) await UsbSerialPort.request();

  // 1. Find the port.
  final ports = await UsbSerialPort.list();
  if (ports.isEmpty) return;

  // 2. Ask for permission (Android shows a USB dialog).
  final access = await UsbSerialPort.access.requestAccess(ports.first);
  if (!access.isUsable) return;

  // 3. Open it: 115200 baud, 8 data bits, no parity, 1 stop bit.
  final port = await UsbSerialPort.open(
    ports.first,
    config: const SerialConfig(baudRate: 115200),
  );

  // 4. Print every line the device sends.
  port.input.transform(const LineReader()).listen(print);

  // 5. Send a line of text.
  await port.write(utf8.encode('hello\n'));

  // ...later
  await port.close();
}
```

## Features

### Find serial ports

```dart
final ports = await UsbSerialPort.list();
for (final port in ports) {
  print('${port.name}  vendor ${port.vendorId}  product ${port.productId}');
}
```

On **Android** this lists every USB serial adapter plugged into the phone.
On the **web** it lists the ports the user has already picked for this site.

To look for one kind of device, pass its USB vendor (and product) ID:

```dart
// Only CH340 adapters (vendor 0x1a86).
final ports = await UsbSerialPort.list(
  filters: const [DeviceFilter(vendorId: 0x1a86)],
);
```

### Let the user pick a port (web)

Browsers only allow access to ports the user picks. Show a "Choose port"
button and call `request()` from it:

```dart
ElevatedButton(
  onPressed: () async {
    final port = await UsbSerialPort.request(); // opens the browser popup
    if (port == null) return; // the user closed the popup
    // port is ready to open
  },
  child: const Text('Choose port'),
)
```

- `UsbSerialPort.requiresUserSelection` is `true` on the web and `false` on
  Android, so the same code can decide whether to show the button.
- Pass `filters` to `request()` to show only matching adapters in the popup.
- The browser remembers picked ports for your site, so next time `list()`
  returns them without the popup.
- `request()` must be called from a user action such as a button press; on
  Android it throws `Unsupported` (use `list()` there).

### Ask for permission (Android)

```dart
final access = await UsbSerialPort.access.requestAccess(device);
if (!access.isUsable) {
  // The user tapped Cancel in the USB dialog.
}
```

Android asks the user once per device ("Allow the app to access USB
Serial?"). `checkAccess(device)` tells you whether permission is already
granted, without showing a dialog. On the web, picking the port is the
permission, so `requestAccess()` opens the port popup.

### Open a port with the right settings

The settings must match what the device expects. **Baud rate** is the most
common source of problems: wrong baud rate means garbled characters.

```dart
final port = await UsbSerialPort.open(
  device,
  config: const SerialConfig(
    baudRate: 9600,              // required: 9600, 115200, ...
    dataBits: 8,                 // 5 to 8, default 8
    parity: Parity.none,         // none, odd, even, mark, space
    stopBits: StopBits.one,      // one, onePointFive, two
    flowControl: FlowControl.none, // none, rtsCts, dtrDsr, xonXoff
  ),
);
```

The default (just `SerialConfig(baudRate: ...)`) is **8N1 without flow
control**, which is what most devices use.

Two more options on `open`:

- `openDelay`: waits after opening before returning, for boards that restart
  when the port opens.
- `writeTimeout`: how long a write may take before it fails (default 2
  seconds).

### Receive data

```dart
port.input.listen((Uint8List bytes) {
  print('Received ${bytes.length} bytes');
});
```

- Data arrives in **chunks as USB delivers it**, not as whole messages. A
  single line can be split across two chunks, or two lines can arrive in one.
  Use [LineReader](#read-text-line-by-line) for text, or your own framing for
  binary protocols.
- Bytes that arrive before you start listening are **kept, not lost** (for
  example a board's startup message).
- The stream can be listened to once. For several listeners, use
  `port.input.asBroadcastStream()`.
- If the device is unplugged, the stream reports a `Disconnected` error and
  then ends.

### Read text line by line

```dart
port.input.transform(const LineReader()).listen((String line) {
  print('Line: $line');
});
```

`LineReader` joins chunks back into lines. It:

- understands `\n`, `\r\n` and `\r` line endings;
- decodes UTF-8 correctly even when a character is split across chunks;
- replaces invalid bytes with `�` instead of failing;
- limits line length (default 64 KB) so a device that never sends a newline
  can't use up memory: `LineReader(maxLineLength: 1024)`.

### Send data

```dart
await port.write(utf8.encode('READ\r\n'));       // text
await port.write([0x01, 0x03, 0x00, 0x00]);       // raw bytes
await port.write(data, timeout: const Duration(seconds: 5));
```

- Writes are sent **in the order you call them**, even without `await`.
- Writing never freezes your app's UI; on Android the data goes to a
  background thread.
- If the device doesn't accept the data in time, `write` throws
  `OperationTimeout`.

### Control DTR and RTS (and avoid board resets)

DTR and RTS are two control lines of a serial port. Many boards use them:
ESP32 and Arduino boards **restart** when these lines change, which is how
upload tools reset them.

```dart
// Set the lines while the port is open.
await port.setSignals(dtr: false, rts: false);

// Or set them as part of opening, before any data flows:
final port = await UsbSerialPort.open(
  device,
  config: const SerialConfig(baudRate: 115200, dtr: false, rts: false),
);
```

If your board restarts every time you connect, open with `dtr: false` and
`rts: false`. Leave them out (`null`) to keep the adapter's defaults.

### Know when a device is plugged in or out

```dart
UsbSerialPort.events.listen((event) {
  switch (event) {
    case DeviceAttached(:final device):
      print('Plugged in: ${device.name}');
    case DeviceDetached(:final device):
      print('Unplugged: ${device.name}');
  }
});
```

For an open port, watch `port.done`: it completes when the port closes,
whether your app closed it or the device was unplugged. `port.isOpen` tells
you the current state.

### Close the port

```dart
await port.close();
```

This releases the device for other apps. Calling it more than once is safe.
Close the port in your widget's `dispose()`.

## Errors and what to do

Every error is a `HardwareException` (from
[`skio_core`](https://pub.dev/packages/skio_core)), so one `try`/`catch`
covers them all:

```dart
try {
  final port = await UsbSerialPort.open(device, config: config);
} on HardwareException catch (e) {
  showMessage(e.message); // a short, readable message
}
```

| Error | What it means | What to do |
| --- | --- | --- |
| `AccessDenied` | No permission for the device (Android), or the port popup wasn't opened from a user action (web). | Call `requestAccess(device)`; on the web call `request()` from a button press. |
| `DeviceBusy` | Another app, browser tab or serial monitor is using the port. | Close the other program (Arduino IDE, serial monitor, other tab), then open again. |
| `DeviceNotFound` | The device was unplugged. | Plug it in and list the ports again. |
| `Disconnected` | The device went away while in use. | Check the cable, then open again. |
| `OperationTimeout` | The device didn't accept data in time. | Check the baud rate and flow control settings. |
| `Unsupported` | Not available on this platform, or a setting the chip or browser can't do. | 8N1 without flow control works with every adapter. |
| `ProtocolError` | Something unexpected happened. | Turn on [debug logging](#debug-logging) and report it. |

## Debug logging

Logging is off by default. Turn it on to see exactly what happens,
including every byte sent and received:

```dart
SkioLog.level = LogLevel.trace; // info, debug or trace (every byte in hex)
SkioLog.records.listen(print);
```

Example output:

```
2026-09-24T10:36:38.195 INFO skio_usb_serial [/dev/bus/usb/001/003]: USB permission granted
2026-09-24T10:36:38.326 INFO skio_usb_serial [/dev/bus/usb/001/003]: Opened with SerialConfig(115200 8N1, flow: none)
2026-09-24T10:36:38.358 TRACE skio_usb_serial [/dev/bus/usb/001/003]: RX 8: 7b 73 29 82 4a 42 23 ff
```

Please include this output in bug reports. Nothing is ever sent anywhere by
the package.

## Troubleshooting

| Problem | Likely cause and fix |
| --- | --- |
| Garbled characters | Wrong baud rate. Try the device's documented rate; ESP32/ESP8266 boot messages use 74880. |
| The board restarts when you connect | DTR/RTS reset the board. Open with `SerialConfig(..., dtr: false, rts: false)`. |
| Lines arrive cut in half | USB delivers chunks, not messages. Use `LineReader` or your own framing. |
| No ports on Android | The phone needs USB host (OTG) support, and some phones need OTG turned on in settings. Use a powered hub for boards that draw more current. |
| `DeviceBusy` on the web | The port is open in another tab or program. Close it there. |
| The web popup doesn't open | `request()` wasn't called from a button press, the page isn't https/localhost, or the browser isn't Chrome/Edge. |
| Nothing received | Check the device is actually sending, the baud rate, and that TX/RX wires aren't swapped. |

## Tested hardware

**Boards**

| Board | Connection | Result |
| --- | --- | --- |
| ESP32 | Through its CH340 USB-serial chip (1a86:7523) | Listing, permission, open, receive and send work |
| STM32 microcontroller boards | USB serial | Open, receive and send work |

**Phones and browsers**

| Device | Platform | Result |
| --- | --- | --- |
| vivo | Android, USB OTG | Works |
| OPPO | Android, USB OTG | Works |
| Samsung | Android, USB OTG | Works |
| POCO M7 5G | Android 16, USB OTG | Works |
| Chrome on macOS | Web Serial | Works |

Tried another adapter or phone? Please
[open an issue](https://github.com/skio-flutter/skio/issues) with the result
and your debug log.

## Limitations

- Android and web only for now.
- On Android, plug and unplug events are checked once a second.
- Web Serial doesn't support 5 or 6 data bits, mark/space parity, 1.5 stop
  bits, or DTR/DSR and XON/XOFF flow control; these throw `Unsupported`.

## Example app

The [`example`](example) folder is a complete serial terminal: pick a port,
choose settings, see data as text or hex, send text or hex, switch DTR/RTS,
and read the package's log. See its [README](example/README.md) for what
each button does.

```bash
cd example
flutter run            # on an Android phone with a USB serial device attached
flutter run -d chrome  # in the browser
```

## Testing your app without hardware

Replace the platform with a fake in your tests:

```dart
import 'package:skio_usb_serial/platform_interface.dart';

setUp(() => UsbSerialPlatform.instance = MyFakeSerialPlatform());
```

## How it works

On Android the package calls the phone's USB system and the
[usb-serial-for-android](https://github.com/mik3y/usb-serial-for-android)
library (MIT) directly from Dart through JNI, with no platform channels and
no Java code of its own. On the web it uses the browser's Web Serial API.
All queueing, line reading and error handling is Dart code, covered by unit
tests.

## The skio family

| Package | What it does |
| --- | --- |
| [`skio_core`](https://pub.dev/packages/skio_core) | Shared types used by all skio packages: permissions, errors, device filters, logging |
| `skio_usb_serial` | USB serial ports (this package) |
| [`skio_uvc_camera`](https://pub.dev/packages/skio_uvc_camera) | USB cameras: preview, photos, snapshot button |

## License

BSD 3-Clause. The Android part uses usb-serial-for-android (MIT).
