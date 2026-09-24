import 'dart:async';

import 'package:skio_core/skio_core.dart';
import 'package:test/test.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    sub = SkioLog.records.listen(records.add);
  });

  tearDown(() async {
    SkioLog.level = LogLevel.off;
    await sub.cancel();
  });

  test('silent by default and message builder not called', () async {
    var built = false;
    SkioLog.log(LogLevel.error, 'test', () {
      built = true;
      return 'x';
    });
    await Future<void>.delayed(Duration.zero);
    expect(records, isEmpty);
    expect(built, isFalse);
  });

  test('emits records at or above the level', () async {
    SkioLog.level = LogLevel.info;
    SkioLog.log(LogLevel.trace, 'test', () => 'bytes');
    SkioLog.log(LogLevel.debug, 'test', () => 'step');
    SkioLog.log(LogLevel.info, 'test', () => 'opened');
    SkioLog.log(LogLevel.error, 'test', () => 'failed', error: 'boom');
    await Future<void>.delayed(Duration.zero);
    expect(records.map((r) => r.message), ['opened', 'failed']);
    expect(records.last.error, 'boom');
  });

  test('off as a record level is never emitted', () async {
    SkioLog.level = LogLevel.trace;
    SkioLog.log(LogLevel.off, 'test', () => 'x');
    await Future<void>.delayed(Duration.zero);
    expect(records, isEmpty);
  });

  test('toString includes level, source, device and error', () {
    final r = LogRecord(
      time: DateTime.utc(2026),
      level: LogLevel.warning,
      source: 'skio_usb_serial',
      message: 'Disconnected',
      device: const DeviceHandle(id: 'usb-1'),
      error: 'IOException',
    );
    expect(
      r.toString(),
      '2026-01-01T00:00:00.000Z WARNING skio_usb_serial [usb-1]: '
      'Disconnected (IOException)',
    );
  });

  test('hex formats and truncates', () {
    expect(SkioLog.hex([0x00, 0x0a, 0xff]), '00 0a ff');
    expect(SkioLog.hex([1, 2, 3, 4], max: 2), '01 02 … (+2)');
  });
}
