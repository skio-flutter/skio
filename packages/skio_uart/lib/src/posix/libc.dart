// FFI bindings to the parts of libc that serial I/O needs on Linux, Android
// and macOS.
//
// Values that differ between the systems are picked at run time. Linux
// values are from the kernel's asm-generic headers, which arm, arm64, x86,
// x86_64 and riscv64 all use (MIPS, PowerPC and SPARC differ and are not
// supported). macOS values are from the macOS SDK headers.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether this is Linux or Android (both use the Linux kernel's values).
final bool isLinuxKernel = Platform.isLinux || Platform.isAndroid;

// fcntl.h
const O_RDWR = 0x2;
final O_NONBLOCK = isLinuxKernel ? 0x800 : 0x4;
final O_NOCTTY = isLinuxKernel ? 0x100 : 0x20000;
final O_CLOEXEC = isLinuxKernel ? 0x80000 : 0x1000000;

// errno.h (the low numbers are the same everywhere)
const EPERM = 1;
const ENOENT = 2;
const EINTR = 4;
const EIO = 5;
const ENXIO = 6;
const EACCES = 13;
const EBUSY = 16;
const ENODEV = 19;
final EAGAIN = isLinuxKernel ? 11 : 35;

// poll.h (the same everywhere)
const POLLIN = 0x1;
const POLLOUT = 0x4;
const POLLERR = 0x8;
const POLLHUP = 0x10;
const POLLNVAL = 0x20;

// Modem line bits (the same everywhere).
const TIOCM_DTR = 0x002;
const TIOCM_RTS = 0x004;
const TIOCM_CTS = 0x020;
const TIOCM_CAR = 0x040;
const TIOCM_RNG = 0x080;
const TIOCM_DSR = 0x100;

// Terminal ioctls.
final TIOCEXCL = isLinuxKernel ? 0x540C : 0x2000740d;
final TIOCNXCL = isLinuxKernel ? 0x540D : 0x2000740e;
final TIOCMGET = isLinuxKernel ? 0x5415 : 0x4004746a;
final TIOCMBIS = isLinuxKernel ? 0x5416 : 0x8004746c;
final TIOCMBIC = isLinuxKernel ? 0x5417 : 0x8004746b;
final TIOCOUTQ = isLinuxKernel ? 0x5411 : 0x40047473;
final TIOCSBRK = isLinuxKernel ? 0x5427 : 0x2000747b;
final TIOCCBRK = isLinuxKernel ? 0x5428 : 0x2000747a;

/// Waits until the hardware has sent everything: TCSBRK with a non-zero
/// argument on Linux (what tcdrain does), TIOCDRAIN on macOS.
final TCDRAIN_IOCTL = isLinuxKernel ? 0x5409 : 0x2000745e;

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

  /// `ioctl` with a pointer argument. Integer arguments are passed as
  /// `Pointer.fromAddress(value)`, which has the same calling convention.
  static final ioctl = _lib
      .lookupFunction<
        Int Function(Int, UnsignedLong, VarArgs<(Pointer<Void>,)>),
        int Function(int, int, Pointer<Void>)
      >('ioctl');

  // glibc calls it __errno_location, Android's bionic __errno, macOS __error.
  static final _errno = _lib
      .lookupFunction<Pointer<Int> Function(), Pointer<Int> Function()>(
        Platform.isAndroid
            ? '__errno'
            : Platform.isLinux
            ? '__errno_location'
            : '__error',
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
