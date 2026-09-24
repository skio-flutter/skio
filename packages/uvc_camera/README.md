# uvc_camera

USB Video Class (UVC) cameras for Flutter: endoscopes, microscopes,
inspection cameras and USB webcams. Live preview, JPEG capture and the
camera's own hardware button, on **Android** (USB OTG) and the **web**.
Part of the [skio](https://github.com/skio-flutter/skio) family.

> Status: in development. Android and web backends are in place; they have
> not yet been tested with a real UVC camera.

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

## Android

- USB host (OTG) through [UVCAndroid](https://github.com/shiyinghan/UVCAndroid)
  1.0.13 (Apache-2.0) from Maven Central, called from Dart through JNI. Only
  three small Java classes exist: the texture/permission bridge, the preview
  texture's surface lifecycle, and JPEG encoding of a captured frame.
- Permissions: `requestAccess(device)` asks for `CAMERA` (required from
  Android 9 for USB video devices), then the USB grant for the device.
- The plugin declares only `android.permission.CAMERA`. It removes the extra
  permissions the UVC library declares (`RECORD_AUDIO`, storage,
  `MANAGE_EXTERNAL_STORAGE`, `FOREGROUND_SERVICE`) and marks USB host and
  camera hardware as optional, so Play Store reviews don't flag them.
- Captured JPEGs go to the app's cache directory; move or delete them.
- Cheap cameras often report only 1280x720 and 640x480 (MJPEG) plus YUYV
  sizes; use `supportedSizes` rather than assuming 1080p.

## Web

- A UVC camera is an ordinary webcam in the browser, so this uses
  `getUserMedia`. Call `requestAccess()` from a user gesture; labels and
  ids stay hidden until the page has camera permission.
- Vendor and product IDs are read from Chrome's camera labels
  (`Name (0c45:6366)`), so `DeviceFilter` works there too.
- `supportedSizes` lists common sizes up to what the camera's track allows.
- Capture encodes the current video frame as JPEG and returns an in-memory
  `XFile`.
- The camera's hardware button is not available to web pages.

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
