# Serial terminal (skio_usb_serial example)

A complete serial terminal for any USB serial adapter or board: CH340,
CP210x, FTDI, PL2303, Arduino, ESP32 and others. It runs on Android phones
(with a USB OTG cable) and in desktop Chrome or Edge.

```bash
flutter run            # Android phone with the device plugged in
flutter run -d chrome  # browser (Chrome or Edge)
```

## Using it

1. **Plug in** your adapter or board.
2. **Android:** pick it under **Port** (tap **Refresh** if it isn't listed).
   **Web:** click **Choose port** and pick it in the browser popup.
3. Set **Baud** (and **Data**, **Parity**, **Stop** if your device needs
   something other than 8N1).
4. Tap **Connect**. On Android, allow the USB permission dialog.
5. Incoming data appears in the middle of the screen. Type in **Text to
   send** and tap **Send**.

## What each control does

| Control | What it does |
| --- | --- |
| **Port** | The serial port to use. On the web it lists ports you already picked for this site. |
| **Choose port** (web) | Opens the browser's popup to pick a port. |
| **Refresh** (Android) | Looks for newly plugged-in adapters. |
| **Connect** / **Disconnect** | Opens or closes the port with the settings below. |
| **Baud** | Speed; must match the device. 74880 shows ESP32/ESP8266 boot messages. |
| **Data**, **Parity**, **Stop** | Line settings; 8, none, 1 (8N1) is what most devices use. |
| **DTR**, **RTS** switches | The port's control lines. Switching them resets many ESP32 and Arduino boards. |
| **RX / TX** counters | Bytes received and sent since connecting. |
| **Hex** / **Text** (top bar) | Show incoming data as hex bytes or as text. |
| **Clear** (top bar) | Empty the received data and counters. |
| **Logs** (top bar) | Opens the log page (below). |
| **+lf**, **+cr**, **+crlf**, **text** | The line ending added to what you send; **text** sends nothing extra. |
| **hex** (send menu) | Send raw bytes typed as hex, for example `01 A0 ff`. |
| **Send** | Sends what you typed. |
| Red message box | Shows what went wrong and what to do; tap **✕** to hide it. |

## Logs page

The **Logs** page shows what the package is doing, useful when something
doesn't work:

- **Level:** **Info** (opens, closes, permissions), **Debug** (plus internal
  steps) or **Trace (all bytes)** (plus every byte sent and received, in hex).
- **Copy:** copies the whole log to paste into a bug report.
- **Clear:** empties the log.

In debug builds the log is also printed to the console (`flutter logs`).
