import 'dart:async';

import 'device.dart';

/// Severity of a [LogRecord], from most to least detailed.
enum LogLevel {
  /// Every byte sent and received, in hex.
  trace,

  /// Signal changes, retries and other internal steps.
  debug,

  /// Opening, closing and permission results.
  info,

  /// Recoverable problems, such as a device going away.
  warning,

  /// Failures the app should know about.
  error,

  /// Nothing is logged. The default.
  off,
}

/// One log entry from a skio package.
final class LogRecord {
  /// Creates a log record.
  const LogRecord({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.device,
    this.error,
  });

  /// When the entry was created.
  final DateTime time;

  /// Severity.
  final LogLevel level;

  /// The package that logged it, for example `skio_usb_serial`.
  final String source;

  /// What happened.
  final String message;

  /// The device involved, if any.
  final DeviceHandle? device;

  /// An error or exception attached to the entry, if any.
  final Object? error;

  @override
  String toString() {
    final t = time.toIso8601String();
    final on = device == null ? '' : ' [${device!.id}]';
    final err = error == null ? '' : ' ($error)';
    return '$t ${level.name.toUpperCase()} $source$on: $message$err';
  }
}

/// Opt-in logging shared by all skio packages.
///
/// Silent by default. Set [level] and listen to [records]:
///
/// ```dart
/// SkioLog.level = LogLevel.debug;
/// SkioLog.records.listen(print);
/// ```
///
/// Nothing is written anywhere unless the app does it; skio never sends logs
/// over the network.
abstract final class SkioLog {
  /// The lowest level that is emitted. [LogLevel.off] (the default) disables
  /// logging entirely.
  static LogLevel level = LogLevel.off;

  static final _controller = StreamController<LogRecord>.broadcast();

  /// All emitted records.
  static Stream<LogRecord> get records => _controller.stream;

  /// Whether records at [recordLevel] are currently emitted.
  static bool isEnabled(LogLevel recordLevel) =>
      recordLevel != LogLevel.off &&
      level != LogLevel.off &&
      recordLevel.index >= level.index &&
      _controller.hasListener;

  /// Emits a record if [recordLevel] is enabled.
  ///
  /// [message] is only called when the record is emitted, so building
  /// expensive messages (such as hex dumps) costs nothing when logging is off.
  static void log(
    LogLevel recordLevel,
    String source,
    String Function() message, {
    DeviceHandle? device,
    Object? error,
  }) {
    if (!isEnabled(recordLevel)) return;
    _controller.add(
      LogRecord(
        time: DateTime.now(),
        level: recordLevel,
        source: source,
        message: message(),
        device: device,
        error: error,
      ),
    );
  }

  /// Formats [bytes] as space-separated hex, truncated after [max] bytes.
  static String hex(List<int> bytes, {int max = 64}) {
    final shown = bytes.length > max ? bytes.sublist(0, max) : bytes;
    final text = shown
        .map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return bytes.length > max ? '$text … (+${bytes.length - max})' : text;
  }
}
