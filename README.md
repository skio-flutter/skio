# skio

Flutter plugins for **USB hardware**, with native access through JNI and
the browser's own APIs (no platform channels).

| Package | What it does | Platforms | Status |
| --- | --- | --- | --- |
| [`skio_usb_serial`](packages/skio_usb_serial) | Send and receive data with USB serial devices: Arduino, ESP32, USB-to-serial adapters (CH340, CP210x, FTDI, PL2303) | Android (USB OTG), web (Chrome, Edge) | Stable |
| [`skio_uvc_camera`](packages/skio_uvc_camera) | USB cameras (endoscopes, microscopes, webcams): live preview, JPEG photos, the camera's snapshot button | Android (USB OTG), web | Beta |
| [`skio_core`](packages/skio_core) | Shared building blocks: permissions, error types, device filters, logging | All | Stable |

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
