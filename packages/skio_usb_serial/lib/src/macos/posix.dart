// FFI bindings to the parts of libc that serial I/O needs on macOS.
//
// Constants and struct layouts are from the macOS SDK headers (sys/termios.h,
// sys/ttycom.h, sys/fcntl.h, sys/errno.h, IOKit/serial/ioss.h) for 64-bit
// Darwin, where tcflag_t and speed_t are `unsigned long`.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// fcntl.h
const O_RDWR = 0x2;
const O_NONBLOCK = 0x4;
const O_NOCTTY = 0x20000;
const O_CLOEXEC = 0x1000000;

// errno.h
const EPERM = 1;
const ENOENT = 2;
const EINTR = 4;
const EIO = 5;
const ENXIO = 6;
const EACCES = 13;
const EBUSY = 16;
const ENODEV = 19;
const EAGAIN = 35;

// poll.h
const POLLIN = 0x1;
const POLLOUT = 0x4;
const POLLERR = 0x8;
const POLLHUP = 0x10;
const POLLNVAL = 0x20;

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
const TCIOFLUSH = 3;

// ttycom.h ioctls
const TIOCEXCL = 0x2000740d; // _IO('t', 13)
const TIOCMBIS = 0x8004746c; // _IOW('t', 108, int)
const TIOCMBIC = 0x8004746b; // _IOW('t', 107, int)
const TIOCM_DTR = 0x2;
const TIOCM_RTS = 0x4;

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

/// `struct pollfd`.
final class PollFd extends Struct {
  @Int()
  external int fd;
  @Short()
  external int events;
  @Short()
  external int revents;
}

/// libc functions. Look-ups are lazy and shared per isolate.
abstract final class LibC {
  static final _lib = DynamicLibrary.process();

  static final open = _lib
      .lookupFunction<
        Int Function(Pointer<Utf8>, Int, VarArgs<(Int,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');

  static final close = _lib
      .lookupFunction<Int Function(Int), int Function(int)>('close');

  static final read = _lib
      .lookupFunction<
        IntPtr Function(Int, Pointer<Uint8>, Size),
        int Function(int, Pointer<Uint8>, int)
      >('read');

  static final write = _lib
      .lookupFunction<
        IntPtr Function(Int, Pointer<Uint8>, Size),
        int Function(int, Pointer<Uint8>, int)
      >('write');

  static final pipe = _lib
      .lookupFunction<Int Function(Pointer<Int>), int Function(Pointer<Int>)>(
        'pipe',
      );

  static final poll = _lib
      .lookupFunction<
        Int Function(Pointer<PollFd>, UnsignedInt, Int),
        int Function(Pointer<PollFd>, int, int)
      >('poll');

  static final ioctl = _lib
      .lookupFunction<
        Int Function(Int, UnsignedLong, VarArgs<(Pointer<Void>,)>),
        int Function(int, int, Pointer<Void>)
      >('ioctl');

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

  static final _errno = _lib
      .lookupFunction<Pointer<Int> Function(), Pointer<Int> Function()>(
        '__error',
      );

  static final _strerror = _lib
      .lookupFunction<Pointer<Utf8> Function(Int), Pointer<Utf8> Function(int)>(
        'strerror',
      );

  /// The calling thread's `errno`. Read it right after the failing call.
  static int get errno => _errno().value;

  /// The system's description of [code].
  static String describe(int code) => _strerror(code).toDartString();
}

/// An `errno` captured from a failed call, for exception causes.
final class PosixError {
  /// Captures the current `errno` for [call].
  PosixError(this.call) : code = LibC.errno;

  /// The failing function, for example `open`.
  final String call;

  /// The `errno` value.
  final int code;

  @override
  String toString() => '$call: ${LibC.describe(code)} (errno $code)';
}
