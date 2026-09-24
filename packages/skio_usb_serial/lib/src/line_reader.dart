import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Turns a serial byte stream into text lines.
///
/// Handles lines split across reads, multi-byte UTF-8 characters split across
/// reads, and `\n`, `\r\n` or `\r` line endings. Invalid UTF-8 becomes U+FFFD
/// instead of an error.
///
/// ```dart
/// port.input.transform(const LineReader()).listen(print);
/// ```
final class LineReader extends StreamTransformerBase<Uint8List, String> {
  /// Creates a line reader.
  ///
  /// A line longer than [maxLineLength] characters is emitted in pieces of
  /// that length, so a device that never sends a newline can't grow memory
  /// without bound.
  const LineReader({this.maxLineLength = 64 * 1024})
    : assert(maxLineLength > 0);

  /// Maximum characters buffered before a partial line is emitted.
  final int maxLineLength;

  @override
  Stream<String> bind(Stream<Uint8List> stream) =>
      _LineSplitter(maxLineLength)
          .bind(const Utf8Decoder(allowMalformed: true).bind(stream));
}

final class _LineSplitter extends StreamTransformerBase<String, String> {
  const _LineSplitter(this.maxLineLength);

  final int maxLineLength;

  @override
  Stream<String> bind(Stream<String> stream) {
    final buffer = StringBuffer();
    var skipLf = false;
    return stream.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (chunk, sink) {
          for (var i = 0; i < chunk.length; i++) {
            final c = chunk.codeUnitAt(i);
            if (skipLf) {
              skipLf = false;
              if (c == 0x0A) continue;
            }
            if (c == 0x0A || c == 0x0D) {
              sink.add(buffer.toString());
              buffer.clear();
              skipLf = c == 0x0D;
            } else {
              buffer.writeCharCode(c);
              if (buffer.length >= maxLineLength) {
                sink.add(buffer.toString());
                buffer.clear();
              }
            }
          }
        },
        handleDone: (sink) {
          if (buffer.isNotEmpty) sink.add(buffer.toString());
          sink.close();
        },
      ),
    );
  }
}
