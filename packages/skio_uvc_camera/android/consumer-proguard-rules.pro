# skio_uvc_camera calls these classes from Dart through JNI, which R8 cannot see.
-keep class dev.skio.uvc_camera.** { *; }
-keep interface dev.skio.uvc_camera.** { *; }
-keep class com.serenegiant.usb.** { *; }
-keep interface com.serenegiant.usb.** { *; }
