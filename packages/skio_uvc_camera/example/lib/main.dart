// A USB camera viewer built on skio_uvc_camera.
//
// Works with UVC cameras such as endoscopes, microscopes, inspection cameras
// and USB webcams, on Android over USB OTG and in the browser.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:skio_uvc_camera/skio_uvc_camera.dart';

import 'delete_file.dart';

void main() {
  // Log skio events in debug builds (see `flutter logs`).
  if (kDebugMode) {
    SkioLog.level = LogLevel.debug;
    SkioLog.records.listen((r) => debugPrint('$r'));
  }
  runApp(const ViewerApp());
}

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
  SaveTo _saveTo = SaveTo.cache;
  final _shots = <Shot>[];
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
      final shot = switch (_saveTo) {
        // Default: a file in the app's cache folder.
        SaveTo.cache => await _shotFrom(camera.capture(quality: 90)),
        // Straight into the app's own folder, no move or copy needed.
        SaveTo.appFolder => await _shotFrom(
          camera.capture(
            quality: 90,
            directory:
                '${(await getApplicationDocumentsDirectory()).path}'
                '/photos',
            fileName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        ),
        // Bytes only, for uploading or your own storage code.
        SaveTo.memory => Shot(null, await camera.captureBytes(quality: 90)),
      };
      if (mounted) setState(() => _shots.insert(0, shot));
    } on HardwareException catch (e) {
      _toast(e.message);
    }
  }

  static Future<Shot> _shotFrom(Future<XFile> capture) async {
    final file = await capture;
    // Web captures have no path; they live in memory.
    return Shot(kIsWeb ? null : file.path, await file.readAsBytes());
  }

  Future<void> _delete(Shot shot) async {
    setState(() => _shots.remove(shot));
    final path = shot.path;
    if (path == null) return;
    try {
      await deleteCapturedFile(path);
    } on Exception catch (e) {
      _toast('Could not delete the file: $e');
    }
  }

  Future<void> _view(Shot shot) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Image.memory(shot.bytes, fit: BoxFit.contain)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      shot.path ?? 'In memory, not saved',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Close'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (delete ?? false) await _delete(shot);
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

  Widget _cameraBar(UvcCamera? camera) {
    final picker = DropdownButtonFormField<DeviceHandle>(
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
          DropdownMenuItem(
            value: d,
            child: Text(_label(d), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: camera == null ? (d) => setState(() => _selected = d) : null,
    );
    final buttons = [
      OutlinedButton.icon(
        onPressed: camera == null ? _refresh : null,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      const SizedBox(width: 8),
      camera == null
          ? FilledButton(
              onPressed: _selected == null || _busy ? null : _open,
              child: const Text('Open'),
            )
          : FilledButton.tonal(onPressed: _close, child: const Text('Close')),
    ];
    return Padding(
      padding: const EdgeInsets.all(12),
      // On narrow screens the buttons go below the camera box so its name
      // stays readable.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                children: [
                  picker,
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: buttons,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: picker),
                  const SizedBox(width: 8),
                  ...buttons,
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB camera viewer'),
        actions: [
          PopupMenuButton<SaveTo>(
            tooltip: 'Where photos go',
            onSelected: (v) => setState(() => _saveTo = v),
            itemBuilder: (_) => [
              for (final v in SaveTo.values)
                // Browsers have no app folder to write to.
                if (!kIsWeb || v != SaveTo.appFolder)
                  CheckedPopupMenuItem(
                    value: v,
                    checked: v == _saveTo,
                    child: Text(v.label),
                  ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_alt),
                  SizedBox(width: 6),
                  Text('Save to'),
                ],
              ),
            ),
          ),
          if (camera != null)
            PopupMenuButton<UvcSize>(
              tooltip: 'Preview size',
              onSelected: _reopenAt,
              itemBuilder: (_) => [
                for (final s in camera.supportedSizes)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: s == camera.previewSize,
                    child: Text('$s'),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.aspect_ratio),
                    SizedBox(width: 6),
                    Text('Size'),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _cameraBar(camera),
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
                  '${camera.previewSize} · ${_saveTo.label.toLowerCase()} · '
                  'press the camera button or tap capture',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // Room on the right so the capture button doesn't cover the
                // last thumbnail.
                padding: const EdgeInsets.fromLTRB(8, 8, 150, 8),
                itemCount: _shots.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _Thumbnail(
                  shot: _shots[i],
                  onTap: () => _view(_shots[i]),
                  onDelete: () => _delete(_shots[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: camera == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture'),
            ),
    );
  }
}

/// Where captured photos go.
enum SaveTo {
  cache('Cache folder'),
  appFolder('App folder'),
  memory('Memory only');

  const SaveTo(this.label);

  final String label;
}

/// A captured photo: where it was saved (null if only in memory) and its
/// bytes for display.
class Shot {
  Shot(this.path, this.bytes);

  final String? path;
  final Uint8List bytes;
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.shot,
    required this.onTap,
    required this.onDelete,
  });

  final Shot shot;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Material(
            child: Ink.image(
              image: MemoryImage(shot.bytes),
              fit: BoxFit.cover,
              child: InkWell(onTap: onTap),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
