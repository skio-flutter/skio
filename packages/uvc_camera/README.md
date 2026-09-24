# uvc_camera

USB Video Class (UVC) cameras for Flutter: endoscopes, microscopes,
inspection cameras and USB webcams. Live preview, JPEG capture and the
camera's own hardware button, on **Android** (USB OTG) and the **web**.
Part of the [skio](https://github.com/skio-flutter/skio) family.

> Status: in development. The Dart API and tests are in place; the Android
> and web backends are being added.

```dart
import 'package:uvc_camera/uvc_camera.dart';

final cameras = await UvcCamera.devices();
final access = await UvcCamera.access.requestAccess(cameras.first);
if (!access.isUsable) return;

final cam = await UvcCamera.open(
  cameras.first,
  // Cheap cameras often only do 1280x720 and 640x480, so list fallbacks.
  preferred: const [UvcSize(1920, 1080), UvcSize(1280, 720)],
);

// In build():
UvcPreview(camera: cam);

final XFile jpeg = await cam.capture(quality: 95);
cam.buttonPresses.listen((_) => cam.capture()); // the camera's own button
await cam.close();
```

## Features

- One call for permissions: `UvcCamera.access.requestAccess(device)`
- Choose a preview size from what the camera really supports
  (`supportedSizes`, `selectPreviewSize`); MJPEG preferred
- `UvcPreview` widget keeps the camera's aspect ratio
- JPEG capture; a double-tap produces one image
- Hardware button: one event per press, releases and bounces filtered out
- `status` stream: previewing, paused, disconnected, closed
- Errors are `HardwareException`s from `skio_core`; opt-in logging via
  `SkioLog`

## Testing your app without hardware

```dart
import 'package:uvc_camera/platform_interface.dart';

UvcCameraPlatform.instance = MyFakePlatform(); // extends UvcCameraPlatform
```

## The skio family

| Package | Purpose |
| --- | --- |
| `skio_core` | Shared types: access status, errors, device filters, logging |
| `skio_usb_serial` | USB serial port |
| `uvc_camera` | USB Video Class camera (this package) |

Source and issues: [github.com/skio-flutter/skio](https://github.com/skio-flutter/skio).
