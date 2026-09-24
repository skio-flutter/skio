# skio_usb_serial example: serial terminal

A general-purpose serial terminal for any USB serial adapter or board
(CP210x, CH340, FTDI, CDC-ACM, Arduino, ESP32).

- Pick a port (web) or choose an attached device (Android)
- Set baud rate, data bits, parity and stop bits
- View incoming data as text or hex
- Send text with a chosen line ending, or raw hex bytes
- Toggle DTR and RTS

```bash
flutter run -d chrome     # Web Serial (Chrome or Edge)
flutter run -d <android>  # Android over USB OTG
```
