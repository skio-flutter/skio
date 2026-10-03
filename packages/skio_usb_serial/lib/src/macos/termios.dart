// macOS termios: line settings for serial ports.
//
// Constants and struct layouts are from the macOS SDK headers (sys/termios.h,
// IOKit/serial/ioss.h) for 64-bit Darwin, where tcflag_t and speed_t are
// `unsigned long`. Everything shared with Linux is in ../posix/libc.dart.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

// termios.h: c_cflag
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

// termios.h: c_iflag
const IXON = 0x200;
const IXOFF = 0x400;
const IXANY = 0x800;

// termios.h: c_cc indexes and actions
const VMIN = 16;
const VTIME = 17;
const TCSANOW = 0;

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

/// macOS termios functions.
abstract final class Termio {
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
