import 'package:skio_core/skio_core.dart';

import 'darwin_tty.dart';
import 'libc.dart';
import 'linux_tty.dart';

/// The parts of serial I/O that differ between the Linux kernel and macOS.
abstract base class Tty {
  /// Const constructor for subclasses.
  const Tty();

  /// The implementation for this system.
  static final Tty current = isLinuxKernel
      ? const LinuxTty()
      : const DarwinTty();

  /// Throws [Unsupported] for settings this system can't apply.
  void check(SerialConfig config, DeviceHandle device);

  /// Applies [config] to [fd] in raw mode with non-blocking reads.
  void configure(int fd, SerialConfig config, DeviceHandle device);

  /// Discards queued input and/or output. Returns 0 or -1 with `errno` set.
  int flush(int fd, {required bool input, required bool output});
}
