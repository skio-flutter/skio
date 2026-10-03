# UART terminal (skio_uart example)

A complete serial terminal for any serial port: the UART or RS-232/RS-485
port built into an Android panel, the UART pins on a Jetson or Raspberry
Pi, a Windows COM port, or a USB serial adapter on Linux and macOS.

```bash
flutter run             # Android panel connected over adb
flutter run -d linux    # Linux, Jetson, Raspberry Pi
flutter run -d windows  # Windows
flutter run -d macos    # Mac app
```

## Using it

1. **Wire** your device: its TX to the port's RX, its RX to the port's TX,
   GND to GND. (Or connect the port's TX to its own RX to test without a
   device: everything you send comes back.)
2. Under **Port**, pick a detected port with the arrow, or type its path:
   `/dev/ttyS3` on an Android panel (see the panel's manual),
   `/dev/ttyTHS1` on a Jetson, `/dev/serial0` on a Raspberry Pi, `COM3` on
   Windows.
3. Set **Baud** (and **Data**, **Parity**, **Stop**, **Flow** if your device
   needs something other than 8N1 without flow control).
4. Tap **Connect**. Incoming data appears in the middle of the screen. Type
   in **Text to send** and tap **Send**.

## What each control does

| Control | What it does |
| --- | --- |
| **Port** | The path or COM name to open. The arrow lists the ports found. |
| **Refresh** | Looks for ports again. |
| **Connect** / **Disconnect** | Opens or closes the port with the settings below. |
| **Baud**, **Data**, **Parity**, **Stop** | Line settings; must match the device. 8, none, 1 (8N1) is the most common. |
| **Flow** | Flow control. Leave at **none** unless the device uses RTS/CTS, DTR/DSR or XON/XOFF. |
| **DTR**, **RTS** switches | The port's output control lines. |
| **Read CTS/DSR** | Reads the port's input control lines. |
| **RX / TX** counters | Bytes received and sent since connecting. |
| **Hex** / **Text** (top bar) | Show incoming data as hex bytes or as text. |
| **Clear** (top bar) | Empty the received data and counters. |
| **Logs** (top bar) | Opens the log page, with every byte at the Trace level. |
| **+crlf**, **+lf**, **+cr**, **text** | The line ending added to what you send. |
| **hex** (send menu) | Send raw bytes typed as hex, for example a Modbus frame `01 03 00 00 00 02 C4 0B`. |
| Red message box | What went wrong and what to do; tap **✕** to hide it. |

## Platform notes

- **Android panels:** the port must be open to apps. If connecting shows
  "Android refused access", check `adb shell ls -lZ /dev/ttyS3` and ask the
  panel maker for a build that allows it.
- **Linux:** add your user to the `dialout` group and log in again.
- **macOS:** the example's entitlements include
  `com.apple.security.device.serial`, which sandboxed Mac apps need. Add the
  same key to your own app.
