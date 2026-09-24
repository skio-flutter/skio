// A USB camera viewer built on skio_uvc_camera.
//
// Works with UVC cameras such as endoscopes, microscopes, inspection cameras
// and USB webcams, on Android over USB OTG and in the browser.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:skio_uvc_camera/skio_uvc_camera.dart';

void main() => runApp(const ViewerApp());

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'USB camera viewer',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const ViewerPage(),
  );
}

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  static const _preferred = [
    UvcSize(1920, 1080),
    UvcSize(1280, 720),
    UvcSize(640, 480),
  ];

  List<DeviceHandle> _cameras = const [];
  DeviceHandle? _selected;
  UvcCamera? _camera;
  UvcSize? _size;
  bool _busy = false;
  final _shots = <Uint8List>[];
  StreamSubscription<DeviceEvent>? _events;
  StreamSubscription<void>? _button;

  @override
  void initState() {
    super.initState();
    _events = UvcCamera.events.listen((event) {
      _toast(switch (event) {
        DeviceAttached() => 'Camera attached',
        DeviceDetached() => 'Camera detached',
      });
      unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_button?.cancel());
    unawaited(_camera?.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    final cameras = await UvcCamera.devices();
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      if (!cameras.contains(_selected)) {
        _selected = cameras.isEmpty ? null : cameras.first;
      }
    });
  }

  Future<void> _open() async {
    final device = _selected;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      final access = await UvcCamera.access.requestAccess(device);
      if (!access.isUsable) {
        _toast('Permission ${access.status.name}');
        if (access.canOpenSettings) await UvcCamera.access.openSettings();
        return;
      }
      final camera = await UvcCamera.open(
        device,
        preferred: [?_size, ..._preferred],
      );
      _button = camera.buttonPresses.listen((_) => _capture());
      camera.status.listen((status) {
        if (!camera.isOpen && mounted) {
          _toast('Camera ${status.name}');
          setState(() => _camera = null);
        }
      });
      setState(() {
        _camera = camera;
        _size = camera.previewSize;
      });
    } on HardwareException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    await _button?.cancel();
    await _camera?.close();
    setState(() => _camera = null);
  }

  Future<void> _reopenAt(UvcSize size) async {
    _size = size;
    await _close();
    await _open();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      final file = await camera.capture(quality: 90);
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _shots.insert(0, bytes));
    } on HardwareException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _label(DeviceHandle d) {
    String hex(int v) => v.toRadixString(16).padLeft(4, '0');
    final ids = d.vendorId == null
        ? ''
        : ' (${hex(d.vendorId!)}:${hex(d.productId ?? 0)})';
    return '${d.name ?? 'USB camera'}$ids';
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB camera viewer'),
        actions: [
          if (camera != null)
            PopupMenuButton<UvcSize>(
              tooltip: 'Preview size',
              icon: const Icon(Icons.aspect_ratio),
              onSelected: _reopenAt,
              itemBuilder: (_) => [
                for (final s in camera.supportedSizes)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == camera.previewSize,
                    child: Text('$s'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<DeviceHandle>(
                      initialValue: _selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Camera',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      hint: const Text('No cameras found'),
                      items: [
                        for (final d in _cameras)
                          DropdownMenuItem(value: d, child: Text(_label(d))),
                      ],
                      onChanged: camera == null
                          ? (d) => setState(() => _selected = d)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Refresh',
                    onPressed: camera == null ? _refresh : null,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  camera == null
                      ? FilledButton(
                          onPressed: _selected == null || _busy ? null : _open,
                          child: const Text('Open'),
                        )
                      : FilledButton.tonal(
                          onPressed: _close,
                          child: const Text('Close'),
                        ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: camera == null
                    ? Center(
                        child: Text(
                          _busy ? 'Opening…' : 'No camera open',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      )
                    : UvcPreview(camera: camera),
              ),
            ),
            if (camera != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${camera.previewSize} · press the camera button or tap capture',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: _shots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_shots[i], fit: BoxFit.cover, width: 96),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: camera == null
          ? null
          : FloatingActionButton(
              tooltip: 'Capture',
              onPressed: _capture,
              child: const Icon(Icons.camera_alt),
            ),
    );
  }
}
