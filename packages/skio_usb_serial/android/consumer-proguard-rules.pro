# skio_usb_serial calls these classes from Dart through JNI, which R8 cannot
# see. Keep them so release builds don't fail with ClassNotFoundException or
# NoSuchMethodError.
-keep class com.hoho.android.usbserial.** { *; }
-keep interface com.hoho.android.usbserial.** { *; }
