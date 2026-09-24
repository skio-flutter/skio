import 'package:flutter/widgets.dart';

import 'uvc_camera.dart';

/// Shows the live preview of an open [UvcCamera].
///
/// The preview keeps the camera's aspect ratio and is centred within the
/// available space. Shows [placeholder] once the camera is closed.
class UvcPreview extends StatelessWidget {
  /// Creates a preview for [camera].
  const UvcPreview({
    required this.camera,
    this.placeholder = const SizedBox.shrink(),
    super.key,
  });

  /// The camera to show.
  final UvcCamera camera;

  /// Shown when the camera is not open.
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: camera.status,
    builder: (context, _) {
      if (!camera.isOpen) return placeholder;
      final size = camera.previewSize;
      return Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: camera.session.buildPreview(context),
        ),
      );
    },
  );
}
