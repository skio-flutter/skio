# skio_core

Shared pure-Dart types for the skio Flutter hardware plugins: one permission
API, one error family and one way to match devices across USB serial and
UVC cameras. No Flutter dependency and no platform code.

You normally don't depend on this package directly. Each skio plugin
re-exports it.

> **Beta.** The API may still change before 0.1.0.

```dart
import 'package:skio_core/skio_core.dart';

const filter = DeviceFilter(vendorId: 0x10c4, productId: 0xea60);

try {
  // ... call any skio plugin
} on HardwareException catch (e) {
  switch (e) {
    case AccessDenied():
      // ask the user again, or point them to settings
    case Disconnected():
      // show "reconnect the device"
    default:
      print(e.message);
  }
}
```

## What's inside

| Type | Purpose |
| --- | --- |
| `HardwareAccess`, `AccessStatus`, `AccessReport` | The same `checkAccess` / `requestAccess` / `openSettings` API in every plugin |
| `HardwareException` (sealed) | `AccessDenied`, `DeviceNotFound`, `DeviceBusy`, `Disconnected`, `OperationTimeout`, `Unsupported`, `ProtocolError` |
| `AccessConfigurationError` | A developer error that names the exact manifest or config change to make |
| `DeviceHandle`, `DeviceFilter`, `DeviceEvent` | Device identity, declarative matching and attach/detach events |
| `SkioLog`, `LogLevel`, `LogRecord` | Opt-in logging shared by all skio packages, silent by default |

## The skio family

| Package | Purpose |
| --- | --- |
| `skio_core` | Shared types (this package) |
| `skio_usb_serial` | USB serial port: Android USB OTG, Web Serial |
| `skio_uvc_camera` | USB Video Class camera on Android |

Source and issues: [github.com/skio-flutter/skio](https://github.com/skio-flutter/skio).
