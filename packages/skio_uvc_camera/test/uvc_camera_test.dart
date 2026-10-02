import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skio_uvc_camera/platform_interface.dart';
import 'package:skio_uvc_camera/skio_uvc_camera.dart';

import 'fake_platform.dart';

void main() {
  const cam = DeviceHandle(id: 'usb-1', vendorId: 0x0c45, productId: 0x6366);
  const other = DeviceHandle(id: 'usb-2', vendorId: 0x1bcf, productId: 0x2c99);
  late FakeUvcCameraPlatform platform;

  setUp(() {
    platform = FakeUvcCameraPlatform(cameras: [cam, other]);
    UvcCameraPlatform.instance = platform;
  });

  test('devices applies filters', () async {
    expect(await UvcCamera.devices(), [cam, other]);
    expect(
      await UvcCamera.devices(filters: const [DeviceFilter(vendorId: 0x1bcf)]),
      [other],
    );
  });

  test('open picks the first preferred size the camera supports', () async {
    final c = await UvcCamera.open(
      cam,
      preferred: const [UvcSize(1920, 1080), UvcSize(640, 480)],
    );
    expect(c.previewSize, platform.supported[1]); // 640x480 MJPEG
    expect(c.isOpen, isTrue);
    expect(c.currentStatus, UvcCameraStatus.previewing);
  });

  test('open errors propagate', () async {
    platform.openError = const DeviceBusy('in use');
    await expectLater(UvcCamera.open(cam), throwsA(isA<DeviceBusy>()));
  });

  test(
    'capture returns the file; concurrent calls share one capture',
    () async {
      final c = await UvcCamera.open(cam);
      final session = platform.opened.single..captureGate = Completer<void>();
      final a = c.capture(quality: 80);
      final b = c.capture();
      session.captureGate!.complete();
      final files = await Future.wait([a, b]);
      expect(identical(files[0], files[1]), isTrue);
      expect(session.captures, 1);
      expect(await files[0].readAsBytes(), [0xff, 0xd8, 80]);
    },
  );

  test('capture validates quality and state', () async {
    final c = await UvcCamera.open(cam);
    expect(() => c.capture(quality: 0), throwsArgumentError);
    expect(() => c.capture(quality: 101), throwsArgumentError);
    await c.close();
    expect(() => c.capture(), throwsA(isA<Disconnected>()));
  });

  test('capture writes to the given directory and file name', () async {
    final c = await UvcCamera.open(cam);
    final file = await c.capture(directory: '/data/photos', fileName: 'a.jpg');
    expect(file.path, '/data/photos/a.jpg');
    expect(platform.opened.single.calls, ['file 90 /data/photos a.jpg']);
  });

  test('capture rejects file names that leave the directory', () async {
    final c = await UvcCamera.open(cam);
    for (final bad in ['', '.', '..', '../a.jpg', 'x/a.jpg', r'x\a.jpg']) {
      expect(
        () => c.capture(directory: '/data', fileName: bad),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(() => c.capture(directory: ''), throwsArgumentError);
    expect(platform.opened.single.captures, 0);
  });

  test('captureBytes returns JPEG bytes without a file', () async {
    final c = await UvcCamera.open(cam);
    expect(await c.captureBytes(quality: 70), [0xff, 0xd8, 70]);
    expect(platform.opened.single.calls, ['bytes 70']);
  });

  test('captureBytes validates quality and state', () async {
    final c = await UvcCamera.open(cam);
    expect(() => c.captureBytes(quality: 0), throwsArgumentError);
    await c.close();
    expect(() => c.captureBytes(), throwsA(isA<Disconnected>()));
  });

  test('concurrent captureBytes calls share one capture', () async {
    final c = await UvcCamera.open(cam);
    final session = platform.opened.single..captureGate = Completer<void>();
    final a = c.captureBytes();
    final b = c.captureBytes();
    session.captureGate!.complete();
    final results = await Future.wait([a, b]);
    expect(identical(results[0], results[1]), isTrue);
    expect(session.captures, 1);
  });

  test('different captures run one after another', () async {
    final c = await UvcCamera.open(cam);
    final session = platform.opened.single..captureGate = Completer<void>();
    final file = c.capture(fileName: 'a.jpg');
    final other = c.capture(fileName: 'b.jpg');
    final bytes = c.captureBytes();
    await pumpEventQueue();
    expect(session.calls, ['file 90 null a.jpg']);
    session.captureGate!.complete();
    expect((await file).name, 'a.jpg');
    expect((await other).name, 'b.jpg');
    expect(await bytes, [0xff, 0xd8, 90]);
    expect(session.calls, [
      'file 90 null a.jpg',
      'file 90 null b.jpg',
      'bytes 90',
    ]);
  });

  test('a failed capture does not block the next one', () async {
    final c = await UvcCamera.open(cam);
    final session = platform.opened.single..captureGate = Completer<void>();
    final first = c.capture();
    final next = c.captureBytes();
    session.captureGate!.completeError(const ProtocolError('boom'));
    await expectLater(first, throwsA(isA<ProtocolError>()));
    session.captureGate = null;
    expect(await next, [0xff, 0xd8, 90]);
  });

  test('button presses are press-only and debounced', () async {
    final c = await UvcCamera.open(
      cam,
      buttonDebounce: const Duration(milliseconds: 50),
    );
    final presses = <void>[];
    c.buttonPresses.listen(presses.add);
    final buttons = platform.opened.single.buttons
      ..add(1) // press
      ..add(0) // release
      ..add(1); // bounce, within window
    await pumpEventQueue();
    expect(presses, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    buttons.add(1);
    await pumpEventQueue();
    expect(presses, hasLength(2));
  });

  test('paused and resumed statuses are forwarded', () async {
    final c = await UvcCamera.open(cam);
    final seen = <UvcCameraStatus>[];
    c.status.listen(seen.add);
    platform.opened.single.statuses
      ..add(UvcCameraStatus.paused)
      ..add(UvcCameraStatus.previewing);
    await pumpEventQueue();
    expect(seen, [UvcCameraStatus.paused, UvcCameraStatus.previewing]);
    expect(c.isOpen, isTrue);
  });

  test('disconnect closes the camera once', () async {
    final c = await UvcCamera.open(cam);
    final seen = <UvcCameraStatus>[];
    c.status.listen(seen.add);
    platform.opened.single.statuses.add(UvcCameraStatus.disconnected);
    await pumpEventQueue();
    expect(seen, [UvcCameraStatus.disconnected]);
    expect(c.isOpen, isFalse);
    await c.close();
    expect(platform.opened.single.closeCount, 1);
  });

  test('close is idempotent', () async {
    final c = await UvcCamera.open(cam);
    await Future.wait([c.close(), c.close()]);
    expect(platform.opened.single.closeCount, 1);
    expect(c.currentStatus, UvcCameraStatus.closed);
  });

  test('unsupported platform', () async {
    UvcCameraPlatform.instance = UnsupportedUvcCameraPlatform();
    expect(await UvcCamera.devices(), isEmpty);
    expect(
      (await UvcCamera.access.checkAccess()).status,
      AccessStatus.unsupported,
    );
    await expectLater(UvcCamera.open(cam), throwsA(isA<Unsupported>()));
  });

  testWidgets('UvcPreview shows the session preview, then placeholder', (
    tester,
  ) async {
    final c = await UvcCamera.open(cam);
    await tester.pumpWidget(
      UvcPreview(
        camera: c,
        placeholder: const Text('closed', textDirection: TextDirection.ltr),
      ),
    );
    expect(find.byKey(const Key('fake')), findsOneWidget);
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, 1280 / 720);
    await tester.runAsync(c.close);
    await tester.pump();
    expect(find.text('closed'), findsOneWidget);
  });
}
