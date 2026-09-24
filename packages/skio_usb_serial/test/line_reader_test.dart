import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

Future<List<String>> read(
  List<List<int>> chunks, {
  LineReader reader = const LineReader(),
}) =>
    Stream.fromIterable(chunks.map(Uint8List.fromList))
        .transform(reader)
        .toList();

void main() {
  test('splits on \\n, \\r\\n and \\r', () async {
    expect(await read([utf8.encode('a\nb\r\nc\rd')]), ['a', 'b', 'c', 'd']);
  });

  test('joins a line split across chunks', () async {
    expect(await read([utf8.encode('hel'), utf8.encode('lo\n')]), ['hello']);
  });

  test('\\r\\n split across chunks is one line ending', () async {
    expect(await read([utf8.encode('a\r'), utf8.encode('\nb\n')]), ['a', 'b']);
  });

  test('keeps empty lines', () async {
    expect(await read([utf8.encode('a\n\nb\n')]), ['a', '', 'b']);
  });

  test('decodes a UTF-8 character split across chunks', () async {
    final bytes = utf8.encode('25°C\n'); // ° is 2 bytes
    expect(await read([bytes.sublist(0, 3), bytes.sublist(3)]), ['25°C']);
  });

  test('replaces invalid UTF-8 instead of failing', () async {
    expect(
      await read([
        [0x61, 0xff, 0x62, 0x0a],
      ]),
      ['a�b'],
    );
  });

  test('emits a trailing line without newline on close', () async {
    expect(await read([utf8.encode('a\nb')]), ['a', 'b']);
  });

  test('caps line length', () async {
    expect(
      await read([
        utf8.encode('abcdefg\n'),
      ], reader: const LineReader(maxLineLength: 3)),
      ['abc', 'def', 'g'],
    );
  });
}
