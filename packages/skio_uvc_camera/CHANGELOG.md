## 0.1.0-beta.3

- README rewritten: every feature explained with an example, including how
  to choose the resolution, plus an errors table, troubleshooting, tested
  hardware and limitations.
- Example: text labels on every button (Size, Refresh, Capture), a layout
  that fits phone screens, and a guide to each control in its README.
- Includes the hardware-button crash fix below (0.1.0-beta.2 was not
  published separately).

## 0.1.0-beta.2

- Fix a crash on Android when the camera's hardware button is pressed. The
  UVC library calls the button callback directly from native code, which
  must be a plain Java object; a small `ButtonForwarder` class now receives
  it and forwards to Dart.
- Verified on a POCO M7 5G (Android 16) with a Sonix UVC camera
  (0c45:64ab): listing, permissions, 1280x720 MJPEG preview, JPEG capture,
  hardware button, background/resume and unplug/replug.
- Example: delete photos from the thumbnail strip or the full-size viewer;
  debug builds print skio logs.

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
