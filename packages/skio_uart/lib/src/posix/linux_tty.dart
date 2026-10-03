// Line settings for Linux and Android through the kernel's own termios
// ioctls (TCGETS2/TCSETS2).
//
// These are used instead of libc's tcsetattr and cfmakeraw because they
// behave the same under glibc and Android's bionic, and `struct termios2`
// takes any baud rate (BOTHER), not only the standard ones.
// Values are from the kernel's asm-generic termbits.h and ioctls.h.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:skio_core/skio_core.dart';

import 'libc.dart';
import 'tty.dart';

// ioctls.h
const TCFLSH = 0x540B;
const TCGETS2 = 0x802C542A; // _IOR('T', 0x2A, struct termios2)
const TCSETS2 = 0x402C542B; // _IOW('T', 0x2B, struct termios2)

// TCFLSH arguments
const TCIFLUSH = 0;
const TCOFLUSH = 1;
const TCIOFLUSH = 2;

// c_iflag
const IGNBRK = 0x1;
const BRKINT = 0x2;
const PARMRK = 0x8;
const INPCK = 0x10;
const ISTRIP = 0x20;
const INLCR = 0x40;
const IGNCR = 0x80;
const ICRNL = 0x100;
const IXON = 0x400;
const IXANY = 0x800;
const IXOFF = 0x1000;

// c_oflag
const OPOST = 0x1;

// c_lflag
const ISIG = 0x1;
const ICANON = 0x2;
const ECHO = 0x8;
const ECHONL = 0x40;
const IEXTEN = 0x8000;

// c_cflag
const CBAUD = 0x100F;
const BOTHER = 0x1000;
const CSIZE = 0x30;
const CS5 = 0x00;
const CS6 = 0x10;
const CS7 = 0x20;
const CS8 = 0x30;
const CSTOPB = 0x40;
const CREAD = 0x80;
const PARENB = 0x100;
const PARODD = 0x200;
const CLOCAL = 0x800;
const CIBAUD = 0x100F0000;
const CMSPAR = 0x40000000;
const CRTSCTS = 0x80000000;

// c_cc indexes
const VTIME = 5;
const VMIN = 6;

/// The kernel's codes for the standard rates. Others are set with [BOTHER].
const baudCodes = {
  50: 0x1, 75: 0x2, 110: 0x3, 134: 0x4, 150: 0x5, 200: 0x6, 300: 0x7, //
  600: 0x8, 1200: 0x9, 1800: 0xA, 2400: 0xB, 4800: 0xC, 9600: 0xD,
  19200: 0xE, 38400: 0xF, 57600: 0x1001, 115200: 0x1002, 230400: 0x1003,
  460800: 0x1004, 500000: 0x1005, 576000: 0x1006, 921600: 0x1007,
  1000000: 0x1008, 1152000: 0x1009, 1500000: 0x100A, 2000000: 0x100B,
  2500000: 0x100C, 3000000: 0x100D, 3500000: 0x100E, 4000000: 0x100F,
};

/// The kernel's `struct termios2`.
final class Termios2 extends Struct {
  @Uint32()
  external int c_iflag;
  @Uint32()
  external int c_oflag;
  @Uint32()
  external int c_cflag;
  @Uint32()
  external int c_lflag;
  @Uint8()
  external int c_line;
  @Array(19)
  external Array<Uint8> c_cc;
  @Uint32()
  external int c_ispeed;
  @Uint32()
  external int c_ospeed;
}

/// [Tty] for the Linux kernel (Linux and Android).
final class LinuxTty extends Tty {
  /// Creates the Linux implementation.
  const LinuxTty();

  @override
  void check(SerialConfig config, DeviceHandle device) {
    if (config.stopBits == StopBits.onePointFive) {
      throw Unsupported(
        'Linux does not support 1.5 stop bits.',
        device: device,
      );
    }
    if (config.flowControl == FlowControl.dtrDsr) {
      throw Unsupported(
        'Linux does not support DTR/DSR flow control. Use RTS/CTS.',
        device: device,
      );
    }
  }

  @override
  void configure(int fd, SerialConfig config, DeviceHandle device) {
    using((arena) {
      final t = arena<Termios2>();
      if (LibC.ioctl(fd, TCGETS2, t.cast()) != 0) {
        throw ProtocolError(
          'Could not read the port settings. Is this a serial port?',
          device: device,
          cause: PosixError('ioctl(TCGETS2)'),
        );
      }
      final termios = t.ref;

      // Raw mode, as cfmakeraw would set it, with flow control cleared.
      termios.c_iflag &=
          ~(IGNBRK |
              BRKINT |
              PARMRK |
              ISTRIP |
              INLCR |
              IGNCR |
              ICRNL |
              INPCK |
              IXON |
              IXOFF |
              IXANY);
      if (config.flowControl == FlowControl.xonXoff) {
        termios.c_iflag |= IXON | IXOFF;
      }
      termios.c_oflag &= ~OPOST;
      termios.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
      termios.c_line = 0;

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
      // With CIBAUD cleared, input runs at the output speed.
      cflag |= baudCodes[config.baudRate] ?? BOTHER;
      termios.c_cflag = cflag;
      termios.c_ispeed = config.baudRate;
      termios.c_ospeed = config.baudRate;

      termios.c_cc[VMIN] = 0;
      termios.c_cc[VTIME] = 0;

      if (LibC.ioctl(fd, TCSETS2, t.cast()) != 0) {
        throw Unsupported(
          'This port does not support $config.',
          device: device,
          cause: PosixError('ioctl(TCSETS2)'),
        );
      }
    });
  }

  @override
  int flush(int fd, {required bool input, required bool output}) {
    final queue = input && output
        ? TCIOFLUSH
        : input
        ? TCIFLUSH
        : TCOFLUSH;
    return LibC.ioctl(fd, TCFLSH, Pointer.fromAddress(queue));
  }
}
