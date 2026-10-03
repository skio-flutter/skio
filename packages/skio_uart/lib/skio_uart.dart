/// Serial ports by path for Flutter and Dart: UART, RS-232 and RS-485 on
/// Android panels, Linux boards such as Jetson and Raspberry Pi, Windows and
/// macOS.
///
/// Start with [SerialPort.list] or a known path, then [SerialPort.open].
library;

import 'src/serial_port.dart';

export 'package:skio_core/skio_core.dart';

export 'src/backend.dart' show ModemStatus;
export 'src/serial_port.dart';
