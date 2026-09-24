## 0.1.0-dev

- `UsbSerialPort`: list, open, buffered byte input, ordered writes with
  timeouts, DTR/RTS control, clean close and disconnect handling.
- `SerialConfig` with baud rate, data bits, parity, stop bits and flow control.
- `LineReader` for splitting byte streams into text lines.
- Platform interface with a fake-friendly `UsbSerialPlatform` for tests.
- Web Serial backend (Chrome and Edge): port chooser, granted-port listing,
  connect/disconnect events, open/read/write/close, DTR/RTS.
- Android backend (USB OTG) calling UsbManager and usb-serial-for-android
  3.11.0 directly through JNI (jnigen): device listing (one handle per port
  on multi-port adapters), USB permission dialog without a BroadcastReceiver,
  attach/detach events, line settings, flow control, DTR/RTS, non-blocking
  writes on the library's I/O thread, R8 keep rules included.
- Example app: general-purpose serial terminal.
