## 0.1.0-dev

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
- Example app: USB camera viewer.
