## 0.3.0-beta.1

- **Windows support (beta).** Lists USB COM ports through the SetupAPI,
  with vendor, product and serial number (also for FTDI's own driver and
  for composite boards such as ESP32-S3 and RP2040); built-in and Bluetooth
  COM ports are left out. `device.id` is the port name (`COM3`) and
  `device.name` is what Device Manager shows. Ports open with overlapped
  I/O through kernel32, all through `dart:ffi`: no C++ plugin code. Every
  `SerialConfig` setting the driver accepts, DTR/RTS lines, plug and
  unplug events. Reading runs on a background isolate; writes never block
  the UI. A port another program holds throws `DeviceBusy`.
- The Windows port I/O follows skio_uart's tested Windows backend.
- Example: runs on Windows, with Windows hints.
- Not yet tested with real adapters on Windows; reports are welcome.

## 0.2.1

- `SerialConfig`, `Parity`, `StopBits`, `FlowControl` and `LineReader` now
  come from skio_core 0.2.0, shared with the new
  [`skio_uart`](https://pub.dev/packages/skio_uart) package. No API changes:
  imports through `skio_usb_serial` work as before, and apps can now use
  both packages together.
- README points Windows, Linux and Android panel UART users to `skio_uart`.

## 0.2.0

- **macOS support.** Lists USB serial ports through IOKit (with vendor,
  product and serial number) and opens them with POSIX termios, all through
  `dart:ffi`: no Swift, Objective-C or CocoaPods. Any baud rate, 5 to 8 data
  bits, odd/even parity, 1 or 2 stop bits, RTS/CTS, DTR/DSR and XON/XOFF flow
  control, DTR/RTS lines, plug and unplug events. Reading runs on a
  background isolate; writes never block the UI. Other processes are kept
  out of an open port, and opening the same port twice in one app throws
  `DeviceBusy`.
- Sandboxed macOS apps need the `com.apple.security.device.serial`
  entitlement; without it `open` throws `AccessDenied` saying so.
- Example: runs on macOS, with macOS-specific hints.
- Verified on a Mac with an ESP32 through its CH340 chip.

## 0.1.3

- README: badges, a FAQ for common questions and a fair comparison with
  other packages, plus a guide for migrating from `usb_serial`.
- pub.dev: clearer description, topics and a link to skio-flutter.dev.

## 0.1.2

- Tested hardware in the README now lists the boards (ESP32, STM32,
  Nordic nRF) and phones (vivo, OPPO, Samsung, POCO) the package has been used with.
- Includes the 0.1.1 documentation changes below (0.1.1 was not published
  separately).

## 0.1.1 (not published separately)

- README rewritten: every feature explained with an example (finding and
  picking ports, permission, settings, receiving, line reading, sending,
  DTR/RTS, plug events, closing), plus an errors table, troubleshooting,
  tested hardware and limitations.
- Example: text labels on every button, a layout that fits phone screens,
  and a guide to each control in its README.

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
