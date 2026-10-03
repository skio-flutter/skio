// Line settings for macOS through libc's termios functions.
//
// Constants and struct layouts are from the macOS SDK headers
// (sys/termios.h, IOKit/serial/ioss.h) for 64-bit Darwin, where tcflag_t
// and speed_t are `unsigned long`.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import 'libc.dart';
import 'tty.dart';

// c_cflag
const CSIZE = 0x300;
const CS5 = 0x000;
const CS6 = 0x100;
const CS7 = 0x200;
const CS8 = 0x300;
const CSTOPB = 0x400;
const CREAD = 0x800;
const PARENB = 0x1000;
const PARODD = 0x2000;
const CLOCAL = 0x8000;
const CCTS_OFLOW = 0x10000;
const CRTS_IFLOW = 0x20000;
const CDTR_IFLOW = 0x40000;
const CDSR_OFLOW = 0x80000;

// c_iflag
const IXON = 0x200;
const IXOFF = 0x400;
const IXANY = 0x800;

// c_cc indexes and tcsetattr/tcflush actions
const VMIN = 16;
const VTIME = 17;
const TCSANOW = 0;
const TCIFLUSH = 1;
const TCOFLUSH = 2;
const TCIOFLUSH = 3;

// IOKit/serial/ioss.h: set any baud rate.
const IOSSIOSPEED = 0x80085402; // _IOW('T', 2, speed_t)

/// Baud rates termios accepts directly. Others go through [IOSSIOSPEED].
const standardBaudRates = {
  50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800, 7200, //
  9600, 14400, 19200, 28800, 38400, 57600, 76800, 115200, 230400,
};

/// `struct termios`.
final class Termios extends Struct {
  @UnsignedLong()
  external int c_iflag;
  @UnsignedLong()
  external int c_oflag;
  @UnsignedLong()
  external int c_cflag;
  @UnsignedLong()
  external int c_lflag;
  @Array(20)
  external Array<UnsignedChar> c_cc;
  @UnsignedLong()
  external int c_ispeed;
  @UnsignedLong()
  external int c_ospeed;
}

abstract final class _Termios {
  static final _lib = DynamicLibrary.process();

  static final tcgetattr = _lib
      .lookupFunction<
        Int Function(Int, Pointer<Termios>),
        int Function(int, Pointer<Termios>)
      >('tcgetattr');

  static final tcsetattr = _lib
      .lookupFunction<
        Int Function(Int, Int, Pointer<Termios>),
        int Function(int, int, Pointer<Termios>)
      >('tcsetattr');

  static final tcflush = _lib
      .lookupFunction<Int Function(Int, Int), int Function(int, int)>(
        'tcflush',
      );

  static final cfmakeraw = _lib
      .lookupFunction<
        Void Function(Pointer<Termios>),
        void Function(Pointer<Termios>)
      >('cfmakeraw');

  static final cfsetspeed = _lib
      .lookupFunction<
        Int Function(Pointer<Termios>, UnsignedLong),
        int Function(Pointer<Termios>, int)
      >('cfsetspeed');
}

/// [Tty] for macOS.
final class DarwinTty extends Tty {
  /// Creates the macOS implementation.
  const DarwinTty();

  @override
  void check(SerialConfig config, DeviceHandle device) {
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
  }

  @override
  void configure(int fd, SerialConfig config, DeviceHandle device) {
    using((arena) {
      final t = arena<Termios>();
      if (_Termios.tcgetattr(fd, t) != 0) {
        throw ProtocolError(
          'Could not read the port settings. Is this a serial port?',
          device: device,
          cause: PosixError('tcgetattr'),
        );
      }
      _Termios.cfmakeraw(t);
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
      _Termios.cfsetspeed(t, standard ? config.baudRate : 9600);
      if (_Termios.tcsetattr(fd, TCSANOW, t) != 0) {
        throw Unsupported(
          'This port does not support $config.',
          device: device,
          cause: PosixError('tcsetattr'),
        );
      }
      if (!standard) {
        final speed = arena<UnsignedLong>()..value = config.baudRate;
        if (LibC.ioctl(fd, IOSSIOSPEED, speed.cast()) != 0) {
          throw Unsupported(
            'This port does not support ${config.baudRate} baud.',
            device: device,
            cause: PosixError('ioctl(IOSSIOSPEED)'),
          );
        }
      }
    });
  }

  @override
  int flush(int fd, {required bool input, required bool output}) =>
      _Termios.tcflush(
        fd,
        input && output
            ? TCIOFLUSH
            : input
            ? TCIFLUSH
            : TCOFLUSH,
      );
}
