import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/device_poller.dart';
import '../platform/usb_serial_platform.dart';
import '../posix/libc.dart';
import '../posix/posix_serial.dart';
import 'sysfs.dart';
import 'termios2.dart';

/// [UsbSerialPlatform] for Linux: lists ports from sysfs and talks to
/// `/dev/ttyUSB*` and `/dev/ttyACM*` with termios2, through `dart:ffi`.
///
/// The user needs read and write access to the device node, which most
/// distributions give to the `dialout` group (`uucp` on Arch).
final class LinuxUsbSerialPlatform extends UsbSerialPlatform {
  /// Creates the Linux platform. [sysClassTty] and [devDir] are for tests.
  LinuxUsbSerialPlatform({
    this.sysClassTty = '/sys/class/tty',
    this.devDir = '/dev',
  });

  /// Where sysfs lists ttys.
  final String sysClassTty;

  /// Where device nodes live.
  final String devDir;

  /// Registers this implementation. Called by Flutter's plugin registrant.
  static void registerWith() {
    UsbSerialPlatform.instance = LinuxUsbSerialPlatform();
  }

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  static const _permissionHint =
      'Add your user to the group that owns the port (usually dialout, '
      'or uucp on Arch): sudo usermod -aG dialout \$USER, then log out and '
      'back in.';

  @override
  bool get requiresUserSelection => false;

  // ---------------------------------------------------------------- access

  /// Whether this user can read and write the port's device node. Linux
  /// can't prompt for this; [requestAccess] reports the same result with a
  /// hint on how to fix it.
  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async {
    if (device == null) return const AccessReport(AccessStatus.notRequired);
    return canAccessPath(device.id)
        ? const AccessReport(AccessStatus.granted)
        : const AccessReport(AccessStatus.denied, hint: _permissionHint);
  }

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) =>
      checkAccess(device);

  @override
  Future<bool> openSettings() async => false;

  // ----------------------------------------------------------- discovery

  @override
  Future<List<DeviceHandle>> list() async {
    final ports = listUsbSerialPorts(classDir: sysClassTty, devDir: devDir);
    final perDevice = <String, int>{};
    for (final port in ports) {
      perDevice.update(port.usbDevicePath, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final port in ports)
        DeviceHandle(
          id: port.devicePath,
          name: _name(port, shared: perDevice[port.usbDevicePath]! > 1),
          vendorId: port.vendorId,
          productId: port.productId,
          serialNumber: port.serialNumber,
        ),
    ];
  }

  /// Multi-port adapters (FT2232, CP2105) get the tty name added so their
  /// ports can be told apart.
  static String _name(SysfsSerialPort port, {required bool shared}) {
    final tty = port.devicePath.split('/').last;
    final product = port.productName;
    if (product == null) return tty;
    return shared ? '$product ($tty)' : product;
  }

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(
        'Linux has no port chooser. Use UsbSerialPort.list().',
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
    if (config.stopBits == StopBits.onePointFive) {
      throw Unsupported(
        'Linux does not support 1.5 stop bits.',
        device: device,
      );
    }
    if (config.flowControl == FlowControl.dtrDsr) {
      throw Unsupported(
        'Linux does not support DTR/DSR flow control.',
        device: device,
      );
    }
    return openPosixPort(
      device,
      config,
      configure: (fd) => _configure(fd, config, device),
      accessDenied: 'No permission to open the port. $_permissionHint',
    );
  }

  static void _configure(int fd, SerialConfig config, DeviceHandle device) {
    using((arena) {
      final t = arena<Termios2>();
      if (LibC.ioctl(fd, TCGETS2, t.cast()) != 0) {
        throw ProtocolError(
          'Could not read the port settings.',
          device: device,
          cause: PosixError('ioctl(TCGETS2)'),
        );
      }
      final termios = t.ref;

      // Raw mode, as cfmakeraw would set it, and no software flow control
      // unless asked for.
      var iflag =
          termios.c_iflag &
          ~(IGNBRK |
              BRKINT |
              PARMRK |
              ISTRIP |
              INLCR |
              IGNCR |
              ICRNL |
              IXON |
              IXOFF |
              IXANY);
      if (config.flowControl == FlowControl.xonXoff) iflag |= IXON | IXOFF;
      termios
        ..c_iflag = iflag
        ..c_oflag = termios.c_oflag & ~OPOST
        ..c_lflag = termios.c_lflag & ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);

      var cflag =
          termios.c_cflag &
          ~(CSIZE |
              CSTOPB |
              PARENB |
              PARODD |
              CMSPAR |
              CRTSCTS |
              CBAUD |
              CIBAUD);
      cflag |= CREAD | CLOCAL;
      cflag |= switch (config.dataBits) {
        5 => CS5,
        6 => CS6,
        7 => CS7,
        _ => CS8,
      };
      if (config.stopBits == StopBits.two) cflag |= CSTOPB;
      cflag |= switch (config.parity) {
        Parity.none => 0,
        Parity.odd => PARENB | PARODD,
        Parity.even => PARENB,
        Parity.mark => PARENB | CMSPAR | PARODD,
        Parity.space => PARENB | CMSPAR,
      };
      if (config.flowControl == FlowControl.rtsCts) cflag |= CRTSCTS;
      // BOTHER takes the rate from c_ospeed as a number, so any rate the
      // adapter supports works. CIBAUD left at 0 makes input follow output.
      termios
        ..c_cflag = cflag | BOTHER
        ..c_ispeed = config.baudRate
        ..c_ospeed = config.baudRate;

      termios.c_cc[VMIN] = 0;
      termios.c_cc[VTIME] = 0;

      if (LibC.ioctl(fd, TCSETS2, t.cast()) != 0) {
        throw Unsupported(
          'This adapter does not support $config.',
          device: device,
          cause: PosixError('ioctl(TCSETS2)'),
        );
      }
    });
  }
}
