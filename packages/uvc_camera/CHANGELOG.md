## 0.1.0-beta.1

First beta. The API may still change before 0.1.0. Android and web
backends are verified on an emulator and in Chromium, but not yet with a
real UVC camera; please report results with `SkioLog` output.


- `UvcCamera`: list devices, open with preferred sizes, live preview through
  `UvcPreview`, JPEG capture (a double-tap produces one image), hardware
  button presses (press-only, debounced), status stream, idempotent close.
- `UvcSize`, `UvcFrameFormat` and `selectPreviewSize` for choosing from the
  sizes a camera reports.
- Platform interface with `UvcCameraPlatform` for fakes in tests.
- Android backend: UVCAndroid 1.0.13 through JNI (jnigen), preview into a
  Flutter texture that follows the surface lifecycle, CAMERA + USB
  permission in one call, JPEG capture encoded in Java, hardware button,
  unplug detection. Declares only the CAMERA permission.
- Web backend: `getUserMedia` preview in an `HtmlElementView`, vendor and
  product IDs from Chrome labels, attach/detach via `devicechange`, JPEG
  capture from the video frame.
- Example app: USB camera viewer.
