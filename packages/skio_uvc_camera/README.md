# skio_uvc_camera

Use **USB cameras** in a Flutter app: endoscopes, microscopes, inspection
cameras, document cameras and ordinary USB webcams. These all follow the
**USB Video Class (UVC)** standard. The package shows a **live preview**,
takes **JPEG photos**, and reports presses of the camera's own **snapshot
button**.

Part of the [skio](https://github.com/skio-flutter/skio) family of Flutter
hardware plugins.


## Contents

- [Platforms](#platforms)
- [Install](#install)
- [Quick start](#quick-start)
- [Features](#features)
  - [Find cameras](#find-cameras)
  - [Ask for permission](#ask-for-permission)
  - [Open a camera](#open-a-camera)
  - [Choose the resolution](#choose-the-resolution)
  - [Show the live preview](#show-the-live-preview)
  - [Take a photo](#take-a-photo)
  - [Use the camera's snapshot button](#use-the-cameras-snapshot-button)
  - [Know when the camera stops or is unplugged](#know-when-the-camera-stops-or-is-unplugged)
  - [Close the camera](#close-the-camera)
- [Errors and what to do](#errors-and-what-to-do)
- [Debug logging](#debug-logging)
- [Troubleshooting](#troubleshooting)
- [Tested hardware](#tested-hardware)
- [Limitations](#limitations)
- [Example app](#example-app)
- [Testing your app without a camera](#testing-your-app-without-a-camera)

## Platforms

| Feature | Android | Web (Chrome, Edge) |
| --- | --- | --- |
| Find cameras | Yes, plugged in with a USB OTG cable | Yes, cameras the browser can see |
| Live preview | Yes | Yes |
| Take a JPEG photo | Yes, saved as a file | Yes, kept in memory |
| Choose the resolution | Yes, from the sizes the camera reports | Yes, the browser picks the closest |
| Snapshot button on the camera | Yes | No, browsers do not give pages access |
| Plug and unplug events | Yes | Yes |
| Minimum version | Android 7.0 (API 24) | Page served over https or localhost |

iOS, macOS, Windows and Linux are not supported yet. On those platforms the
package reports `AccessStatus.unsupported` instead of failing.

## Install

```bash
flutter pub add skio_uvc_camera
```

**Android:** nothing else to add. The package declares the `CAMERA`
permission (Android 9 and later require it for USB cameras) and marks USB host
and camera hardware as optional, so your app still installs on phones
without them. It removes extra permissions the underlying UVC library would
otherwise add (microphone, storage, foreground service), so Play Store reviews
don't flag them.

**Web:** serve the page over **https** (or `http://localhost` while
developing). Browsers only allow camera access on secure pages.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:skio_uvc_camera/skio_uvc_camera.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  UvcCamera? _camera;

  Future<void> _open() async {
    // 1. Find cameras.
    final cameras = await UvcCamera.devices();
    if (cameras.isEmpty) return;

    // 2. Ask for permission (Android shows two dialogs, the web one).
    final access = await UvcCamera.access.requestAccess(cameras.first);
    if (!access.isUsable) return;

    // 3. Open it at the best size the camera supports.
    final camera = await UvcCamera.open(
      cameras.first,
      preferred: const [UvcSize(1920, 1080), UvcSize(1280, 720)],
    );
    setState(() => _camera = camera);
  }

  @override
  void dispose() {
    _camera?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _camera == null
        ? Center(child: FilledButton(onPressed: _open, child: const Text('Open camera')))
        : UvcPreview(camera: _camera!),
    floatingActionButton: _camera == null
        ? null
        : FloatingActionButton(
            onPressed: () async {
              final photo = await _camera!.capture(quality: 90);
              debugPrint('Saved ${photo.path}');
            },
            child: const Icon(Icons.camera_alt),
          ),
  );
}
```

## Features

### Find cameras

```dart
final cameras = await UvcCamera.devices();
for (final camera in cameras) {
  print('${camera.name}  vendor ${camera.vendorId}  product ${camera.productId}');
}
```

Only video devices are listed; other USB devices (for example a serial
adapter on the same hub) are ignored. To look for one particular camera
model, pass a filter with its USB vendor and product IDs:

```dart
final cameras = await UvcCamera.devices(
  filters: const [DeviceFilter(vendorId: 0x0c45, productId: 0x64ab)],
);
```

On the web, names and IDs stay hidden until the page has camera permission;
before that, cameras appear as "Camera 1", "Camera 2" and so on.

### Ask for permission

```dart
final access = await UvcCamera.access.requestAccess(camera);

if (access.isUsable) {
  // Ready to open.
} else if (access.status == AccessStatus.permanentlyDenied) {
  // The user chose "Don't ask again". Only the settings page can fix it.
  await UvcCamera.access.openSettings();
} else if (access.status == AccessStatus.unsupported) {
  // No USB camera support on this platform. access.hint says why.
} else {
  // The user said no. You can ask again later.
}
```

- **Android** asks twice in one call: first the **Camera** permission, then
  **USB access to this particular camera**.
- **Web** shows the browser's camera prompt. Call `requestAccess` from a
  button press; browsers ignore requests that don't come from a user action.
- `checkAccess(camera)` tells you the current state without showing any
  dialog.

### Open a camera

```dart
final camera = await UvcCamera.open(device);
```

Opening starts the camera and its preview. It throws a `HardwareException`
if it can't, for example `AccessDenied` without permission or `DeviceBusy`
when another app is using the camera (see
[Errors and what to do](#errors-and-what-to-do)).

### Choose the resolution

Every camera supports its own list of sizes. After opening, you can see the
list and the size in use:

```dart
print(camera.supportedSizes);
// [1280x720 25fps mjpeg, 640x480 25fps mjpeg, 640x480 30fps yuyv, ...]
print(camera.previewSize); // 1280x720 25fps mjpeg
```

To ask for a width and height, list the sizes you want **in order of
preference**. The first one the camera supports is used:

```dart
final camera = await UvcCamera.open(
  device,
  preferred: const [
    UvcSize(1920, 1080),                             // Full HD if possible
    UvcSize(1280, 720, fps: 30),                     // else 720p at 30 fps
    UvcSize(640, 480, format: UvcFrameFormat.mjpeg), // else 480p, MJPEG
  ],
);
```

- **Width and height** are required; **fps** (frame rate) and **format** are
  optional.
- **Formats:** `UvcFrameFormat.mjpeg` is compressed and allows high
  resolutions; `UvcFrameFormat.yuyv` is uncompressed and usually limited to
  small sizes. When both match, MJPEG is preferred.
- **If nothing matches**, the camera opens at its largest MJPEG size up to
  1920x1080.
- Many inexpensive cameras only offer 1280x720 and 640x480, so always list a
  fallback.
- **To change the size of an open camera,** close it and open it again with
  the new size.
- **Photos use the preview size:** a 1280x720 preview gives 1280x720 JPEGs.
- On the **web**, the size is a preference that the browser matches as
  closely as the camera allows.

`selectPreviewSize(supported, preferred)` is the function that makes this
choice, if you want to use the same rule in your own code.

### Show the live preview

```dart
UvcPreview(
  camera: camera,
  placeholder: const Text('Camera closed'), // shown after the camera closes
)
```

The preview keeps the camera's aspect ratio and is centred in the space you
give it. On Android it pauses by itself when the app goes to the background
and resumes when it comes back.

### Take a photo

```dart
final XFile photo = await camera.capture(quality: 90); // quality 1 to 100
final bytes = await photo.readAsBytes();
```

- **Android:** the photo is a JPEG file in your app's cache folder
  (`photo.path`). Move it somewhere permanent, or delete it when you no longer
  need it.
- **Web:** the photo is kept in memory; use `readAsBytes()`.
- Calling `capture` again while a photo is being taken returns the same photo,
  so a double tap produces one image, not two.

### Use the camera's snapshot button

Many USB cameras (endoscopes, microscopes) have a button on the cable or
body. Each press arrives as one event:

```dart
camera.buttonPresses.listen((_) => camera.capture());
```

Cameras usually report both press and release, and some report a single
press several times. Only real presses are passed on; a second press within
700 ms is ignored. Change that with
`UvcCamera.open(device, buttonDebounce: const Duration(milliseconds: 300))`.

This works on **Android only**. Browsers don't give web pages access to the
camera's button.

### Know when the camera stops or is unplugged

```dart
camera.status.listen((status) {
  final text = switch (status) {
    UvcCameraStatus.previewing => 'Frames are arriving',
    UvcCameraStatus.paused => 'App in background; resumes by itself',
    UvcCameraStatus.disconnected => 'Unplugged: the camera is now closed',
    UvcCameraStatus.closed => 'Closed by the app',
  };
  print(text);
});
```

To react to cameras being plugged in or out even when none is open:

```dart
UvcCamera.events.listen((event) {
  switch (event) {
    case DeviceAttached(:final device):
      print('Plugged in: ${device.name}');
    case DeviceDetached(:final device):
      print('Unplugged: ${device.name}');
  }
});
```

After an unplug, plug the camera back in and call `UvcCamera.open` again.

### Close the camera

```dart
await camera.close();
```

This stops the preview and frees the camera for other apps. Calling it more
than once is safe. Close the camera in your widget's `dispose()`.

## Errors and what to do

Every error is a `HardwareException` (from
[`skio_core`](https://pub.dev/packages/skio_core)), so one `try`/`catch`
covers them all:

```dart
try {
  final camera = await UvcCamera.open(device);
} on HardwareException catch (e) {
  showMessage(e.message); // a short, readable message
}
```

| Error | What it means | What to do |
| --- | --- | --- |
| `AccessDenied` | No permission for the camera. | Call `UvcCamera.access.requestAccess(device)` first. |
| `DeviceBusy` | Another app (or browser tab) is using the camera. | Close the other app or tab, then open again. |
| `DeviceNotFound` | The camera was unplugged. | Plug it in, refresh the list with `UvcCamera.devices()`. |
| `Disconnected` | The camera went away while in use. | Plug it back in and open it again. |
| `OperationTimeout` | No picture arrived in time for a photo. | Check the preview is showing, then try again. |
| `Unsupported` | Not available on this platform, or the camera rejected the requested size. | Check `access.hint`, or pick a size from `supportedSizes`. |
| `ProtocolError` | The camera reported something unexpected. | Turn on [debug logging](#debug-logging) and report it. |

## Debug logging

Logging is off by default. Turn it on to see what the package does:

```dart
SkioLog.level = LogLevel.debug; // info, debug or trace
SkioLog.records.listen(print);
```

Example output:

```
2026-09-24T12:42:31.081 INFO skio_uvc_camera [/dev/bus/usb/002/004]: USB permission granted
2026-09-24T12:42:31.087 INFO skio_uvc_camera [/dev/bus/usb/002/004]: Opened at 1280x720 25fps mjpeg
2026-09-24T12:44:18.085 DEBUG skio_uvc_camera [/dev/bus/usb/002/004]: Button
```

Please include this output in bug reports. Nothing is ever sent anywhere by
the package.

## Troubleshooting

| Problem | Likely cause and fix |
| --- | --- |
| No cameras found on Android | The phone needs USB host (OTG) support, and the camera must be plugged in with an OTG cable or adapter. Some phones need OTG turned on in settings. Try a powered USB hub for cameras with LEDs. |
| Permission dialog never appears (Android) | Another app may be set to open this camera automatically. Clear its defaults in Settings > Apps. |
| Preview is black | Check the camera's LED is on, and try another size from `supportedSizes`; some cameras only stream MJPEG at their larger sizes. |
| Picture is smaller than requested | The camera doesn't support that size; it opened at the closest one. Check `previewSize`. |
| Button presses do nothing | Not every camera has a button, and the web has no access to it. |
| Camera works once, then `DeviceBusy` | The camera wasn't closed. Call `close()` in `dispose()`. |

## Tested hardware

| Camera | Phone or browser | Result |
| --- | --- | --- |
| Sonix-based USB camera (0c45:64ab), MJPEG 1280x720 | POCO M7 5G, Android 16 | Listing, permissions, preview, photo capture, snapshot button, background and resume, unplug and replug all work |

Tried another camera or phone? Please
[open an issue](https://github.com/skio-flutter/skio/issues) with the result
and your debug log.

## Limitations

- Only one resolution per open camera; close and open again to change it.
- No video recording yet, only photos.
- No camera controls yet (focus, exposure, brightness).
- Android and web only.

## Example app

The [`example`](example) folder is a complete USB camera viewer. See its
[README](example/README.md) for what each button does.

```bash
cd example
flutter run            # on an Android phone with a USB camera attached
flutter run -d chrome  # in the browser
```

## Testing your app without a camera

Replace the platform with a fake in your tests:

```dart
import 'package:skio_uvc_camera/platform_interface.dart';

setUp(() => UvcCameraPlatform.instance = MyFakeCameraPlatform());
```

## How it works (Android)

The package uses the [UVCAndroid](https://github.com/shiyinghan/UVCAndroid)
library (Apache-2.0) and calls it directly from Dart through JNI, with no
platform channels. Only four small Java classes exist, for what JNI can't
do: attaching the preview to a Flutter texture, receiving the permission
result, turning a camera frame into a JPEG, and receiving the snapshot
button from native code.

## The skio family

| Package | What it does |
| --- | --- |
| [`skio_core`](https://pub.dev/packages/skio_core) | Shared types used by all skio packages: permissions, errors, device filters, logging |
| [`skio_usb_serial`](https://pub.dev/packages/skio_usb_serial) | USB serial ports (Arduino, ESP32, USB-to-serial adapters) |
| `skio_uvc_camera` | USB cameras (this package) |

## License

BSD 3-Clause. The Android part uses UVCAndroid (Apache-2.0).
