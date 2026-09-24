/// Pixel format a UVC camera streams in.
enum UvcFrameFormat {
  /// Motion JPEG: compressed, allows high resolutions over USB 2.0.
  mjpeg,

  /// Uncompressed YUY2/YUYV: low latency, bandwidth-limited to small sizes.
  yuyv,
}

/// A preview size, optionally with frame rate and format.
final class UvcSize {
  /// Creates a size. [fps] and [format] are optional when used as a
  /// preference; supported sizes reported by a camera always carry them.
  const UvcSize(this.width, this.height, {this.fps, this.format});

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Frames per second, if known.
  final int? fps;

  /// Stream format, if known.
  final UvcFrameFormat? format;

  /// Width × height.
  int get pixels => width * height;

  /// Whether [other] has the same width and height, and the same [fps] and
  /// [format] where this size specifies them.
  bool matches(UvcSize other) =>
      width == other.width &&
      height == other.height &&
      (fps == null || fps == other.fps) &&
      (format == null || format == other.format);

  @override
  bool operator ==(Object other) =>
      other is UvcSize &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.format == format;

  @override
  int get hashCode => Object.hash(width, height, fps, format);

  @override
  String toString() {
    final extra = [
      if (fps != null) '${fps}fps',
      if (format != null) format!.name,
    ];
    return '${width}x$height${extra.isEmpty ? '' : ' ${extra.join(' ')}'}';
  }
}

/// Picks the preview size to use from what a camera [supported].
///
/// Tries each entry of [preferred] in order and returns the first supported
/// size that matches it, preferring MJPEG and then the highest frame rate.
/// With no match (or no preferences) it returns the largest MJPEG size up to
/// 1920x1080, then the largest size of any format. Returns `null` only if
/// [supported] is empty.
UvcSize? selectPreviewSize(
  List<UvcSize> supported, [
  List<UvcSize> preferred = const [],
]) {
  if (supported.isEmpty) return null;

  int rank(UvcSize s) =>
      (s.format == UvcFrameFormat.mjpeg ? 1000 : 0) + (s.fps ?? 0);

  UvcSize? best(Iterable<UvcSize> candidates) {
    UvcSize? result;
    for (final c in candidates) {
      if (result == null ||
          c.pixels > result.pixels ||
          (c.pixels == result.pixels && rank(c) > rank(result))) {
        result = c;
      }
    }
    return result;
  }

  for (final want in preferred) {
    final match = best(supported.where(want.matches));
    if (match != null) return match;
  }
  const hd = 1920 * 1080;
  return best(
        supported.where(
          (s) => s.format == UvcFrameFormat.mjpeg && s.pixels <= hd,
        ),
      ) ??
      best(supported);
}
