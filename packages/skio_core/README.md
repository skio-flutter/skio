# skio_core

[![pub package](https://img.shields.io/pub/v/skio_core.svg)](https://pub.dev/packages/skio_core)
[![pub points](https://img.shields.io/pub/points/skio_core)](https://pub.dev/packages/skio_core/score)
[![CI](https://github.com/skio-flutter/skio/actions/workflows/ci.yaml/badge.svg)](https://github.com/skio-flutter/skio/actions/workflows/ci.yaml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/skio-flutter/skio/blob/main/LICENSE)

The shared building blocks of the [skio](https://github.com/skio-flutter/skio)
Flutter hardware plugins. It gives every skio package **the same way to ask
for permission, the same error types, the same way to pick devices, and the
same logging**, so an app that uses a USB serial device and a USB camera
handles both the same way.

**You normally don't add this package yourself.**
[`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) and
[`skio_uvc_camera`](https://pub.dev/packages/skio_uvc_camera) include it and
re-export everything below. It is pure Dart, with no Flutter dependency and no
platform code.

## Contents

- [Permissions: `HardwareAccess`](#permissions-hardwareaccess)
- [Errors: `HardwareException`](#errors-hardwareexception)
- [Devices: `DeviceHandle` and `DeviceFilter`](#devices-devicehandle-and-devicefilter)
- [Plug and unplug events: `DeviceEvent`](#plug-and-unplug-events-deviceevent)
- [Logging: `SkioLog`](#logging-skiolog)

## Permissions: `HardwareAccess`

Every skio package has an `access` object with the same three methods:

| Method | What it does |
| --- | --- |
| `checkAccess([device])` | Tells you whether you have permission now. Never shows a dialog. |
| `requestAccess([device])` | Asks for permission, showing system dialogs if needed. |
| `openSettings()` | Opens your app's page in the system settings (Android). |

Both `checkAccess` and `requestAccess` return an `AccessReport`:

| Field | Meaning |
| --- | --- |
| `status` | One of the `AccessStatus` values below |
| `isUsable` | `true` when you can use the device (`granted` or `notRequired`) |
| `missing` | Platform permissions still missing, for example `android.permission.CAMERA` |
| `canOpenSettings` | `true` when only the settings page can fix it |
| `hint` | A short explanation for developers, for example "call this from a button press" |

| `AccessStatus` | Meaning |
| --- | --- |
| `granted` | Permission given; the device can be used. |
| `denied` | The user said no, but you can ask again. |
| `permanentlyDenied` | The user chose "Don't ask again". Send them to the settings page. |
| `restricted` | Blocked by the device's policy (parental controls, company management). |
| `notRequired` | This platform needs no permission for it. |
| `unsupported` | This feature doesn't exist on this platform. |

```dart
final report = await UvcCamera.access.requestAccess(camera);
if (report.isUsable) {
  // go ahead
} else if (report.canOpenSettings) {
  await UvcCamera.access.openSettings();
}
```

## Errors: `HardwareException`

All skio packages throw the same error types. They are a sealed family, so
Dart can check that a `switch` handles every one:

```dart
try {
  // any skio call
} on HardwareException catch (e) {
  final advice = switch (e) {
    AccessDenied() => 'Please allow access to the device.',
    DeviceNotFound() || Disconnected() => 'Please reconnect the device.',
    DeviceBusy() => 'Close other apps using the device.',
    OperationTimeout() => 'The device did not answer. Try again.',
    Unsupported() => 'This is not supported here.',
    ProtocolError() => 'Something went wrong. See the log.',
  };
  print('${e.message}: $advice');
}
```

| Error | Meaning |
| --- | --- |
| `AccessDenied` | No permission for the device. |
| `DeviceNotFound` | The device isn't attached (anymore). |
| `DeviceBusy` | Another app, browser tab or connection is using it. |
| `Disconnected` | The device went away while in use. |
| `OperationTimeout` | An operation didn't finish in time (`timeout` says how long). |
| `Unsupported` | Not available on this platform or with these settings. |
| `ProtocolError` | The device or platform reported something unexpected. |

Every error has a readable `message`, the `device` involved (if known), and
the original platform error in `cause` for logs.

`AccessConfigurationError` is different: it means the **app** is set up
wrong (for example a missing manifest entry). It is an `Error`, not an
exception, and its `fix` tells the developer exactly what to change.

## Devices: `DeviceHandle` and `DeviceFilter`

A `DeviceHandle` describes one device:

| Field | Meaning |
| --- | --- |
| `id` | Platform identifier, for example `/dev/bus/usb/001/003` on Android |
| `name` | The name the device reports, if any |
| `vendorId`, `productId` | USB vendor and product IDs, for example `0x1a86` and `0x7523` for a CH340 |
| `serialNumber` | Serial number, where the platform allows reading it |
| `interfaceClasses` | USB interface classes, for example `0x0e` for video |
| `serviceUuids` | Bluetooth service IDs (for future use) |

A `DeviceFilter` picks devices by those fields. Every field you set must
match; fields you leave out match anything:

```dart
const onlyCh340 = DeviceFilter(vendorId: 0x1a86, productId: 0x7523);
const anyNamedSensor = DeviceFilter(namePrefix: 'Sensor');

onlyCh340.matches(device);                                // true or false
DeviceFilter.matchesAny([onlyCh340, anyNamedSensor], device);
```

Pass filters to `UsbSerialPort.list(filters: ...)` or
`UvcCamera.devices(filters: ...)` to list only matching devices.

## Plug and unplug events: `DeviceEvent`

Streams such as `UsbSerialPort.events` and `UvcCamera.events` send a
`DeviceEvent` whenever a device is plugged in or out:

```dart
switch (event) {
  case DeviceAttached(:final device):
    print('Plugged in: ${device.name}');
  case DeviceDetached(:final device):
    print('Unplugged: ${device.name}');
}
```

## Logging: `SkioLog`

Logging is **off by default**. Turn it on to see what every skio package is
doing, one stream for all of them:

```dart
SkioLog.level = LogLevel.debug;
SkioLog.records.listen(print);
```

| `LogLevel` | What you see |
| --- | --- |
| `error` | Only failures |
| `warning` | Also recoverable problems, such as a device being unplugged |
| `info` | Also opening, closing and permission results |
| `debug` | Also internal steps, such as signal changes and retries |
| `trace` | Also every byte sent and received, in hex |
| `off` | Nothing (the default) |

Each `LogRecord` has a `time`, `level`, `source` (the package), `message`,
and optionally the `device` and an `error`. Messages are only built when
logging is on, so leaving it off costs nothing. skio never sends logs
anywhere; what you do with them is up to your app.

## The skio family

| Package | What it does |
| --- | --- |
| `skio_core` | Shared types (this package) |
| [`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) | USB serial ports (Arduino, ESP32, USB-to-serial adapters) |
| [`skio_uvc_camera`](https://pub.dev/packages/skio_uvc_camera) | USB cameras: preview, photos, snapshot button |

## License

BSD 3-Clause.
