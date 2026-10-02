import 'dart:async';

import 'package:skio_core/skio_core.dart';

/// Turns a device listing into attach and detach events by calling [list]
/// every [interval] while the stream has listeners.
Stream<DeviceEvent> pollDeviceEvents(
  Future<List<DeviceHandle>> Function() list,
  Duration interval,
) {
  Timer? timer;
  var known = <String, DeviceHandle>{};
  late final StreamController<DeviceEvent> controller;
  Future<void> poll() async {
    final now = {for (final d in await list()) d.id: d};
    for (final d in now.values) {
      if (!known.containsKey(d.id)) controller.add(DeviceAttached(d));
    }
    for (final d in known.values) {
      if (!now.containsKey(d.id)) controller.add(DeviceDetached(d));
    }
    known = now;
  }

  controller = StreamController<DeviceEvent>.broadcast(
    onListen: () async {
      known = {for (final d in await list()) d.id: d};
      // The listener may have cancelled while the first list() ran.
      if (!controller.hasListener) return;
      timer = Timer.periodic(interval, (_) => unawaited(poll()));
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  return controller.stream;
}
