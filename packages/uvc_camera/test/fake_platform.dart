import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:uvc_camera/platform_interface.dart';
import 'package:uvc_camera/uvc_camera.dart';

final class FakeUvcCameraPlatform extends UvcCameraPlatform {
  FakeUvcCameraPlatform({this.cameras = const []});

  List<DeviceHandle> cameras;
  final opened = <FakeSession>[];
  Object? openError;
  List<UvcSize> supported = const [
    UvcSize(1280, 720, fps: 25, format: UvcFrameFormat.mjpeg),
    UvcSize(640, 480, fps: 25, format: UvcFrameFormat.mjpeg),
    UvcSize(640, 480, fps: 30, format: UvcFrameFormat.yuyv),
  ];

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.granted);

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async =>
      const AccessReport(AccessStatus.granted);

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<List<DeviceHandle>> devices() async => cameras;

  @override
  Stream<DeviceEvent> get events => const Stream.empty();

  @override
  Future<UvcCameraSession> open(
    DeviceHandle device,
    List<UvcSize> preferred,
  ) async {
    if (openError case final e?) throw e;
    final session = FakeSession(
      supported,
      selectPreviewSize(supported, preferred)!,
    );
    opened.add(session);
    return session;
  }
}

final class FakeSession implements UvcCameraSession {
  FakeSession(this.supportedSizes, this.previewSize);

  @override
  final List<UvcSize> supportedSizes;

  @override
  final UvcSize previewSize;

  final buttons = StreamController<int>.broadcast();
  final statuses = StreamController<UvcCameraStatus>.broadcast();
  int captures = 0;
  int closeCount = 0;
  Completer<void>? captureGate;

  @override
  Widget buildPreview(BuildContext context) => const SizedBox(key: Key('fake'));

  @override
  Stream<int> get buttonStates => buttons.stream;

  @override
  Stream<UvcCameraStatus> get status => statuses.stream;

  @override
  Future<XFile> capture({required int quality}) async {
    captures++;
    if (captureGate case final gate?) await gate.future;
    return XFile.fromData(
      Uint8List.fromList([0xff, 0xd8, quality]),
      name: 'capture$captures.jpg',
      path: 'capture$captures.jpg',
    );
  }

  @override
  Future<void> close() async => closeCount++;
}
