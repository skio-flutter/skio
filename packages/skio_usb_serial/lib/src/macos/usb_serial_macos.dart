import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/device_poller.dart';
import '../platform/usb_serial_platform.dart';
import '../posix/libc.dart';
import '../posix/posix_serial.dart';
import 'iokit.dart';
import 'termios.dart';

/// [UsbSerialPlatform] for macOS: lists ports through IOKit and talks to
/// `/dev/cu.*` with POSIX termios, all through `dart:ffi`.
///
/// Sandboxed apps need the `com.apple.security.device.serial` entitlement.
final class MacosUsbSerialPlatform extends UsbSerialPlatform {
  /// Creates the macOS platform.
  MacosUsbSerialPlatform();

  /// Registers this implementation. Called by Flutter's plugin registrant.
  static void registerWith() {
    UsbSerialPlatform.instance = MacosUsbSerialPlatform();
  }

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  @override
  bool get requiresUserSelection => false;

  // ---------------------------------------------------------------- access

  // macOS has no per-device USB permission. Sandboxed apps get access from
  // an entitlement at build time, which can't be checked or requested here.
  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.notRequired);

  @override
  Future<bool> openSettings() async => false;

  // ----------------------------------------------------------- discovery

  /// USB serial ports. Built-in ports such as `Bluetooth-Incoming-Port` are
  /// left out.
  @override
  Future<List<DeviceHandle>> list() async => [
    for (final port in listSerialPorts())
      if (port.vendorId != null)
        DeviceHandle(
          id: port.calloutPath,
          name: port.productName ?? port.calloutPath.split('/').last,
          vendorId: port.vendorId,
          productId: port.productId,
          serialNumber: port.serialNumber,
        ),
  ];

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(
        'macOS has no port chooser. Use UsbSerialPort.list().',
      );

  @override
  Stream<DeviceEvent> get events => pollDeviceEvents(list, pollInterval);

  // ---------------------------------------------------------------- open

  /// Opens the device node named by `device.id`, which must be under `/dev/`.
  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    if (config.parity case Parity.mark || Parity.space) {
      throw Unsupported(
        'macOS does not support ${config.parity.name} parity.',
        device: device,
      );
    }
    if (config.stopBits == StopBits.onePointFive) {
      throw Unsupported(
        'macOS does not support 1.5 stop bits.',
        device: device,
      );
    }
    return openPosixPort(
      device,
      config,
      configure: (fd) => _configure(fd, config, device),
      accessDenied:
          'macOS refused access to the port. Sandboxed apps need the '
          'com.apple.security.device.serial entitlement.',
    );
  }

  static void _configure(int fd, SerialConfig config, DeviceHandle device) {
    using((arena) {
      final t = arena<Termios>();
      if (Termio.tcgetattr(fd, t) != 0) {
        throw ProtocolError(
          'Could not read the port settings.',
          device: device,
          cause: PosixError('tcgetattr'),
        );
      }
      Termio.cfmakeraw(t);
      final termios = t.ref;

      var cflag =
          termios.c_cflag &
          ~(CSIZE |
              CSTOPB |
              PARENB |
              PARODD |
              CCTS_OFLOW |
              CRTS_IFLOW |
              CDTR_IFLOW |
              CDSR_OFLOW);
      cflag |= CREAD | CLOCAL;
      cflag |= switch (config.dataBits) {
        5 => CS5,
        6 => CS6,
        7 => CS7,
        _ => CS8,
      };
      if (config.stopBits == StopBits.two) cflag |= CSTOPB;
      cflag |= switch (config.parity) {
        Parity.odd => PARENB | PARODD,
        Parity.even => PARENB,
        _ => 0,
      };
      cflag |= switch (config.flowControl) {
        FlowControl.rtsCts => CCTS_OFLOW | CRTS_IFLOW,
        FlowControl.dtrDsr => CDTR_IFLOW | CDSR_OFLOW,
        _ => 0,
      };
      termios.c_cflag = cflag;

      var iflag = termios.c_iflag & ~(IXON | IXOFF | IXANY);
      if (config.flowControl == FlowControl.xonXoff) iflag |= IXON | IXOFF;
      termios.c_iflag = iflag;

      termios.c_cc[VMIN] = 0;
      termios.c_cc[VTIME] = 0;

      // termios only takes the standard rates; others are set afterwards
      // with IOSSIOSPEED, which tcsetattr would reset.
      final standard = standardBaudRates.contains(config.baudRate);
      Termio.cfsetspeed(t, standard ? config.baudRate : 9600);
      if (Termio.tcsetattr(fd, TCSANOW, t) != 0) {
        throw Unsupported(
          'This adapter does not support $config.',
          device: device,
          cause: PosixError('tcsetattr'),
        );
      }
      if (!standard) {
        final speed = arena<UnsignedLong>()..value = config.baudRate;
        if (LibC.ioctl(fd, IOSSIOSPEED, speed.cast()) != 0) {
          throw Unsupported(
            'This adapter does not support ${config.baudRate} baud.',
            device: device,
            cause: PosixError('ioctl(IOSSIOSPEED)'),
          );
        }
      }
    });
  }
}
