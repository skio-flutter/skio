## 0.1.0-dev

- `UsbSerialPort`: list, open, buffered byte input, ordered writes with
  timeouts, DTR/RTS control, clean close and disconnect handling.
- `SerialConfig` with baud rate, data bits, parity, stop bits and flow control.
- `LineReader` for splitting byte streams into text lines.
- Platform interface with a fake-friendly `UsbSerialPlatform` for tests.
- Web Serial backend (Chrome and Edge): port chooser, granted-port listing,
  connect/disconnect events, open/read/write/close, DTR/RTS.
- Example app: general-purpose serial terminal.
