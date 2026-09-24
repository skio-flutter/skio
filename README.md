# skio

Flutter hardware plugins that call native APIs directly (jnigen, ffigen,
`dart:js_interop`) instead of platform channels.

| Package | What it does | Status |
| --- | --- | --- |
| [`skio_core`](packages/skio_core) | Shared types: access/permission status, errors, device filters, logging | Stable |
| [`skio_usb_serial`](packages/skio_usb_serial) | USB serial port (Android USB OTG, Web Serial) | Stable |
| [`skio_uvc_camera`](packages/skio_uvc_camera) | USB Video Class camera (Android, web) | Beta |

Design notes are kept privately for now.

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
