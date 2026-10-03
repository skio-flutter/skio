// Linux termios2: line settings for serial ports, including any baud rate.
//
// Values are from the kernel's asm-generic/termbits.h and ioctls.h, which
// x86_64 and arm64 use. termios2 is set with ioctl, so no glibc termios
// wrapper (with its fixed baud rate table) is involved.
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

// c_iflag
const IGNBRK = 0x1;
const BRKINT = 0x2;
const PARMRK = 0x8;
const ISTRIP = 0x20;
const INLCR = 0x40;
const IGNCR = 0x80;
const ICRNL = 0x100;
const IXON = 0x400;
const IXANY = 0x800;
const IXOFF = 0x1000;

// c_oflag
const OPOST = 0x1;

// c_cflag
const CBAUD = 0x100f;
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
const BOTHER = 0x1000;
const CIBAUD = 0x100f0000;
const CMSPAR = 0x40000000;
const CRTSCTS = 0x80000000;

// c_lflag
const ISIG = 0x1;
const ICANON = 0x2;
const ECHO = 0x8;
const ECHONL = 0x40;
const IEXTEN = 0x8000;

// c_cc indexes
const VTIME = 5;
const VMIN = 6;

// ioctls taking a struct termios2 (44 bytes).
const TCGETS2 = 0x802C542A; // _IOR('T', 0x2A, struct termios2)
const TCSETS2 = 0x402C542B; // _IOW('T', 0x2B, struct termios2)

/// `struct termios2`.
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
