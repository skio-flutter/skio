import 'package:flutter_test/flutter_test.dart';
import 'package:skio_uvc_camera/platform_interface.dart';
import 'package:skio_uvc_camera/skio_uvc_camera.dart';

void main() {
  const mjpeg720 = UvcSize(1280, 720, fps: 25, format: UvcFrameFormat.mjpeg);
  const mjpeg480 = UvcSize(640, 480, fps: 25, format: UvcFrameFormat.mjpeg);
  const yuyv480 = UvcSize(640, 480, fps: 30, format: UvcFrameFormat.yuyv);
  const mjpeg4k = UvcSize(3840, 2160, fps: 15, format: UvcFrameFormat.mjpeg);
  // A typical cheap camera: 720p and 480p MJPEG, 480p YUYV.
  const cheap = [mjpeg720, mjpeg480, yuyv480];

  group('selectPreviewSize', () {
    test('first preferred size that is supported wins', () {
      expect(
        selectPreviewSize(cheap, const [
          UvcSize(1920, 1080),
          UvcSize(1280, 720),
        ]),
        mjpeg720,
      );
    });

    test('prefers MJPEG when a preference matches several formats', () {
      expect(selectPreviewSize(cheap, const [UvcSize(640, 480)]), mjpeg480);
    });

    test('format in the preference is respected', () {
      expect(
        selectPreviewSize(cheap, const [
          UvcSize(640, 480, format: UvcFrameFormat.yuyv),
        ]),
        yuyv480,
      );
    });

    test('without a match, largest MJPEG up to 1080p', () {
      expect(selectPreviewSize([...cheap, mjpeg4k]), mjpeg720);
      expect(selectPreviewSize(cheap, const [UvcSize(800, 600)]), mjpeg720);
    });

    test('falls back to any format, and null when empty', () {
      expect(selectPreviewSize(const [yuyv480]), yuyv480);
      expect(selectPreviewSize(const []), isNull);
    });
  });

  test('UvcSize toString and equality', () {
    expect(mjpeg720.toString(), '1280x720 25fps mjpeg');
    expect(const UvcSize(1280, 720).toString(), '1280x720');
    expect(
      mjpeg720,
      const UvcSize(1280, 720, fps: 25, format: UvcFrameFormat.mjpeg),
    );
    expect(const UvcSize(1280, 720).matches(mjpeg720), isTrue);
    expect(mjpeg720.matches(const UvcSize(1280, 720)), isFalse);
  });

  group('ButtonDebouncer', () {
    test('drops releases and presses inside the window', () {
      var now = DateTime(2026);
      final d = ButtonDebouncer(clock: () => now);
      expect(d.accept(1), isTrue);
      expect(d.accept(0), isFalse);
      now = now.add(const Duration(milliseconds: 300));
      expect(d.accept(1), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(d.accept(1), isTrue);
    });
  });
}
