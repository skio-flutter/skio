/// USB serial ports for Flutter on Android (USB OTG) and the web (Web Serial).
///
/// Start with [UsbSerialPort.list] (or [UsbSerialPort.request] on the web),
/// then [UsbSerialPort.open].
library;

import 'src/usb_serial_port.dart';

export 'package:skio_core/skio_core.dart';

export 'src/line_reader.dart';
export 'src/serial_config.dart';
export 'src/usb_serial_port.dart';
