// FFI bindings to the parts of libc that serial I/O needs on macOS and Linux.
//
// Values that differ between the two come from [Sys], chosen at runtime.
// macOS values are from the macOS SDK headers; Linux values are the generic
// ones used by x86_64 and arm64 (asm-generic), which glibc and musl share.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// poll.h (same on both)
const POLLIN = 0x1;
const POLLOUT = 0x4;
const POLLERR = 0x8;
const POLLHUP = 0x10;
const POLLNVAL = 0x20;

// errno.h values below 32 are the same on both.
const EPERM = 1;
const ENOENT = 2;
const EINTR = 4;
const EIO = 5;
const ENXIO = 6;
const EACCES = 13;
const EBUSY = 16;
const ENODEV = 19;

// unistd.h access() modes (same on both)
const R_OK = 4;
const W_OK = 2;

// ttycom.h / ioctls.h modem bits (same on both)
const TIOCM_DTR = 0x2;
const TIOCM_RTS = 0x4;

/// Constants whose values differ between macOS and Linux.
abstract final class Sys {
  static final bool _mac = Platform.isMacOS;

  static final int O_RDWR = 0x2;
  static final int O_NONBLOCK = _mac ? 0x4 : 0x800;
  static final int O_NOCTTY = _mac ? 0x20000 : 0x100;
  static final int O_CLOEXEC = _mac ? 0x1000000 : 0x80000;

  static final int EAGAIN = _mac ? 35 : 11;

  static final int TIOCEXCL = _mac ? 0x2000740d : 0x540C;
  static final int TIOCNXCL = _mac ? 0x2000740e : 0x540D;
  static final int TIOCMBIS = _mac ? 0x8004746c : 0x5416;
  static final int TIOCMBIC = _mac ? 0x8004746b : 0x5417;

  static final int TCIOFLUSH = _mac ? 3 : 2;
}

/// `struct pollfd` (same layout on both).
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

  static final access = _lib
      .lookupFunction<
        Int Function(Pointer<Utf8>, Int),
        int Function(Pointer<Utf8>, int)
      >('access');

  // nfds_t is unsigned int on macOS and unsigned long on Linux.
  static final poll = Platform.isMacOS
      ? _lib.lookupFunction<
          Int Function(Pointer<PollFd>, UnsignedInt, Int),
          int Function(Pointer<PollFd>, int, int)
        >('poll')
      : _lib.lookupFunction<
          Int Function(Pointer<PollFd>, UnsignedLong, Int),
          int Function(Pointer<PollFd>, int, int)
        >('poll');

  static final ioctl = _lib
      .lookupFunction<
        Int Function(Int, UnsignedLong, VarArgs<(Pointer<Void>,)>),
        int Function(int, int, Pointer<Void>)
      >('ioctl');

  static final tcflush = _lib
      .lookupFunction<Int Function(Int, Int), int Function(int, int)>(
        'tcflush',
      );

  static final _errno = _lib
      .lookupFunction<Pointer<Int> Function(), Pointer<Int> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
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
