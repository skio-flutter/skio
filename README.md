# skio

Flutter plugins for **hardware I/O**: USB serial, built-in UARTs and USB
cameras, with native access through JNI (Android), FFI (desktop and
Android UARTs) and the browser's own APIs (no platform channels).

| Package | What it does | Platforms | Status |
| --- | --- | --- | --- |
| [`skio_usb_serial`](packages/skio_usb_serial) | Send and receive data with USB serial devices: Arduino, ESP32, USB-to-serial adapters (CH340, CP210x, FTDI, PL2303) | Android (USB OTG), macOS, Linux, web (Chrome, Edge) | Stable (Linux new in 0.3.0) |
| [`skio_uart`](packages/skio_uart) | Open serial ports by path: the UART, RS-232 and RS-485 ports built into Android panels (`/dev/ttyS*`), Jetson and Raspberry Pi pins, Windows COM ports, and USB adapters on desktop. Pure Dart FFI | Android, Linux, Windows, macOS | Beta (new) |
| [`skio_uvc_camera`](packages/skio_uvc_camera) | USB cameras (endoscopes, microscopes, webcams): live preview, JPEG photos, the camera's snapshot button | Android (USB OTG), web | Stable |
| [`skio_core`](packages/skio_core) | Shared building blocks: permissions, error types, device filters, serial settings, logging | All | Stable |

Each package's README explains every feature with examples, and each has an
example app with a guide to its buttons.

Website: [skio-flutter.dev](https://skio-flutter.dev).

## Development

This repository is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces).
One `pub get` at the root resolves every package:

```bash
git config core.hooksPath .githooks   # once per clone: blocks private files
flutter pub get
dart format .
dart analyze --fatal-infos
(cd packages/skio_core && dart test)
```

## Releasing

Releases are published by GitHub Actions when a maintainer pushes a tag named
`<package>-v<version>` (for example `skio_core-v0.1.1`) and approves the run
in the `pub.dev` environment. See [SECURITY.md](SECURITY.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE).
