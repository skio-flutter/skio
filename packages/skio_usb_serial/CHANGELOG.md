## 0.1.0

First stable release. No API changes since 0.1.0-beta.1.

- Verified on real hardware with a CH340 adapter: Android 16 (POCO M7 5G)
  over USB OTG, and Chrome on macOS through Web Serial. Listing, USB
  permission, open, receive, send and DTR/RTS work.
- Example: a labelled "Choose port" button on the web, step-by-step help,
  inline error hints and a Logs page with copy for bug reports.

## 0.1.0-beta.1

First beta. Web Serial has been checked in Chromium. The Android backend is
verified on an emulator and against the usb-serial-for-android source, but
not yet on real USB hardware; please report results with `SkioLog` output.


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
- Opt-in logging through `SkioLog`: open/close, errors, permission results
  and hex dumps of every byte at `trace`.
- Example app: general-purpose serial terminal.
