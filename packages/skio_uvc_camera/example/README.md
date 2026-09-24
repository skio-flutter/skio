# USB camera viewer (skio_uvc_camera example)

A complete viewer for USB cameras: endoscopes, microscopes, inspection
cameras and webcams. It runs on Android phones (with a USB OTG cable) and in
the browser.

```bash
flutter run            # Android phone with the camera plugged in
flutter run -d chrome  # browser
```

## Using it

1. **Plug in** the camera.
2. Pick it under **Camera** (tap **Refresh** if it isn't listed).
3. Tap **Open**. On Android, allow **Camera** access and then **USB access**
   to the camera.
4. The live picture appears. Tap **Capture**, or press the camera's own
   snapshot button, to take a photo.
5. Photos appear as small pictures at the bottom.

## What each control does

| Control | What it does |
| --- | --- |
| **Camera** | The USB camera to use. |
| **Refresh** | Looks for newly plugged-in cameras. |
| **Open** / **Close** | Starts or stops the camera. |
| **Size** (top bar, when open) | Lists every resolution the camera supports; pick one to reopen at that size. The current one is ticked. |
| Text under the picture | The size in use, for example `1280x720 25fps mjpeg`. |
| **Capture** | Takes a JPEG photo. The camera's snapshot button does the same (Android only). |
| Photo at the bottom | Tap it to see it full size, with **Close** and **Delete**. |
| **✕** on a photo | Deletes that photo straight away (also its file on Android). |

Messages at the bottom of the screen tell you when a camera is plugged in or
out. In debug builds the package's log is printed to the console
(`flutter logs`).
