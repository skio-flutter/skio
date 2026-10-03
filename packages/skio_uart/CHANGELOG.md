## 0.1.0-beta.1

First beta. The API may still change before 0.1.0.

- **Serial ports by path** on Android (built-in UARTs such as
  `/dev/ttyS3`), Linux (`/dev/ttyTHS1` on Jetson, `/dev/ttyAMA0` on
  Raspberry Pi, `/dev/ttyUSB0`), Windows (`COM3`) and macOS
  (`/dev/cu.*`).
- **Pure Dart FFI.** Talks to libc and kernel32 directly; nothing native to
  compile, and it runs in Dart command-line tools too.
- `SerialPort.list()` with USB vendor and product IDs on Linux and macOS,
  and `SerialPort.events` for ports being added and removed.
- Any baud rate, 5–8 data bits, every parity and stop-bit setting the
  platform supports, RTS/CTS, DTR/DSR and XON/XOFF flow control.
- `write`, `drain`, `flush`, `sendBreak`, `setSignals` (DTR/RTS) and
  `getSignals` (CTS/DSR/DCD/RI).
- Errors are skio_core's `HardwareException`s with messages that say how to
  fix them, for example how to check an Android panel's port permissions or
  join Linux's `dialout` group.
- Example app: a serial terminal for Android, Linux, Windows and macOS.
