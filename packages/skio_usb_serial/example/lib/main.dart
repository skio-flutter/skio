// A general-purpose USB serial terminal built on skio_usb_serial.
//
// Works with any USB serial adapter or board (CP210x, CH340, FTDI, CDC-ACM,
// Arduino, ESP32, ...) on Android over USB OTG and in desktop Chrome/Edge.
// The Logs page shows skio's own log, so problems can be diagnosed on the
// device without a debugger.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

/// In-memory log shared by the terminal and the Logs page.
final logBook = LogBook();

void main() {
  logBook.start(kDebugMode ? LogLevel.debug : LogLevel.info);
  runApp(const TerminalApp());
}

/// Keeps the most recent skio log records for the Logs page.
class LogBook extends ChangeNotifier {
  static const _max = 2000;
  final records = <LogRecord>[];
  StreamSubscription<LogRecord>? _sub;

  LogLevel get level => SkioLog.level;

  void start(LogLevel level) {
    SkioLog.level = level;
    _sub ??= SkioLog.records.listen((r) {
      if (kDebugMode) debugPrint('$r');
      records.add(r);
      if (records.length > _max) records.removeRange(0, records.length - _max);
      notifyListeners();
    });
  }

  void setLevel(LogLevel level) {
    SkioLog.level = level;
    notifyListeners();
  }

  /// Adds a line from the app itself (not from skio).
  void note(String message, {LogLevel level = LogLevel.info, Object? error}) {
    records.add(
      LogRecord(
        time: DateTime.now(),
        level: level,
        source: 'app',
        message: message,
        error: error,
      ),
    );
    notifyListeners();
  }

  void clear() {
    records.clear();
    notifyListeners();
  }

  String asText() => records.map((r) => '$r').join('\n');
}

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'skio serial terminal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const TerminalPage(),
  );
}

enum LineEnding {
  none(''),
  lf('\n'),
  cr('\r'),
  crlf('\r\n');

  const LineEnding(this.value);
  final String value;
}

/// A problem shown inline above the terminal, with what to do about it.
class Problem {
  const Problem(this.title, [this.hint]);
  final String title;
  final String? hint;
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  static const _baudRates = [
    9600,
    19200,
    38400,
    57600,
    74880,
    115200,
    230400,
    460800,
    921600,
  ];

  List<DeviceHandle> _devices = const [];
  DeviceHandle? _selected;
  SerialConfig _config = const SerialConfig(baudRate: 115200);
  UsbSerialPort? _port;
  bool _dtr = false;
  bool _rts = false;
  bool _connecting = false;
  bool _supported = true;
  Problem? _problem;

  final _received = BytesBuilder();
  int _rxBytes = 0;
  int _txBytes = 0;
  bool _showHex = false;
  bool _sendHex = false;
  LineEnding _ending = LineEnding.lf;

  final _sendController = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DeviceEvent>? _events;

  bool get _chooser => UsbSerialPort.requiresUserSelection;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSupport());
    _events = UsbSerialPort.events.listen((event) {
      final text = switch (event) {
        DeviceAttached() => 'Attached: ${_label(event.device)}',
        DeviceDetached() => 'Detached: ${_label(event.device)}',
      };
      logBook.note(text);
      _toast(text);
      unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_port?.close());
    _sendController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkSupport() async {
    final access = await UsbSerialPort.access.checkAccess();
    if (!mounted || access.status != AccessStatus.unsupported) return;
    setState(() {
      _supported = false;
      _problem = Problem(
        'USB serial is not available here',
        kIsWeb
            ? 'Use Chrome or Edge on a computer, and open the page over '
                  'https or http://localhost. Safari and Firefox do not '
                  'support Web Serial.'
            : access.hint,
      );
    });
  }

  Future<void> _refresh() async {
    final devices = await UsbSerialPort.list();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      if (!devices.contains(_selected)) {
        _selected = devices.isEmpty ? null : devices.first;
      }
    });
  }

  Future<void> _pickPort() async {
    setState(() => _problem = null);
    try {
      final device = await UsbSerialPort.request();
      await _refresh();
      if (device == null) {
        logBook.note('Port chooser closed without a choice');
        return;
      }
      logBook.note('Chose ${_label(device)}');
      setState(() => _selected = device);
    } on HardwareException catch (e) {
      _report(e);
    }
  }

  Future<void> _connect() async {
    final device = _selected;
    if (device == null) return;
    setState(() {
      _connecting = true;
      _problem = null;
    });
    try {
      var access = await UsbSerialPort.access.checkAccess(device);
      if (!access.isUsable) {
        access = await UsbSerialPort.access.requestAccess(device);
      }
      if (!access.isUsable) {
        setState(
          () => _problem = Problem(
            'Permission ${access.status.name}',
            access.hint ??
                (kIsWeb
                    ? 'Choose the port again with "Choose port".'
                    : 'Tap Connect and allow the USB dialog.'),
          ),
        );
        return;
      }
      final port = await UsbSerialPort.open(
        device,
        config: _config.copyWith(dtr: _dtr, rts: _rts),
      );
      port.input.listen(
        _onData,
        onError: (Object e) {
          if (e is HardwareException) _report(e);
        },
        onDone: () {
          if (mounted) setState(() => _port = null);
        },
      );
      setState(() => _port = port);
    } on HardwareException catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await _port?.close();
    setState(() => _port = null);
  }

  void _onData(Uint8List bytes) {
    setState(() {
      _received.add(bytes);
      _rxBytes += bytes.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final port = _port;
    if (port == null) return;
    final text = _sendController.text;
    final Uint8List bytes;
    if (_sendHex) {
      final parsed = _parseHex(text);
      if (parsed == null) {
        _toast('Hex must be pairs like "01 A0 ff"');
        return;
      }
      bytes = parsed;
    } else {
      bytes = utf8.encode(text + _ending.value);
    }
    try {
      await port.write(bytes);
      setState(() => _txBytes += bytes.length);
      _sendController.clear();
    } on HardwareException catch (e) {
      _report(e);
    }
  }

  Future<void> _setSignals({bool? dtr, bool? rts}) async {
    setState(() {
      _dtr = dtr ?? _dtr;
      _rts = rts ?? _rts;
    });
    try {
      await _port?.setSignals(dtr: dtr, rts: rts);
    } on HardwareException catch (e) {
      _report(e);
    }
  }

  /// Shows [e] inline with a hint on what to do, and logs it.
  void _report(HardwareException e) {
    logBook.note(e.message, level: LogLevel.warning, error: e.cause);
    final hint = switch (e) {
      DeviceBusy() =>
        kIsWeb
            ? 'Close other tabs or programs using the port (serial '
                  'monitors, Arduino IDE), then connect again.'
            : 'Another app is using the device. Unplug and replug it.',
      AccessDenied() =>
        kIsWeb
            ? 'Click "Choose port" and pick the adapter in the popup.'
            : 'Tap Connect again and allow the USB dialog.',
      DeviceNotFound() =>
        kIsWeb
            ? 'Plug the adapter back in and choose the port again.'
            : 'Plug the adapter back in, then tap Refresh.',
      Disconnected() => 'Check the cable, then connect again.',
      OperationTimeout() =>
        'The device did not accept data. Check the baud rate and flow '
            'control.',
      Unsupported() => 'Try other settings (8N1 works with every adapter).',
      ProtocolError() => 'See Logs for details.',
    };
    if (mounted) setState(() => _problem = Problem(e.message, hint));
  }

  static Uint8List? _parseHex(String text) {
    final clean = text.replaceAll(RegExp(r'[\s,:]'), '');
    if (clean.isEmpty || clean.length.isOdd) return null;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final v = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (v == null) return null;
      out[i] = v;
    }
    return out;
  }

  String _output() {
    final bytes = _received.toBytes();
    if (!_showHex) return utf8.decode(bytes, allowMalformed: true);
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      sb.write((i + 1) % 16 == 0 ? '\n' : ' ');
    }
    return sb.toString();
  }

  static String _label(DeviceHandle d) {
    String hex(int v) => v.toRadixString(16).padLeft(4, '0');
    final ids = d.vendorId == null
        ? ''
        : ' (${hex(d.vendorId!)}:${hex(d.productId ?? 0)})';
    return '${d.name ?? d.id}$ids';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _port != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serial terminal'),
        actions: [
          IconButton(
            tooltip: _showHex ? 'Show text' : 'Show hex',
            icon: Icon(_showHex ? Icons.text_fields : Icons.hexagon_outlined),
            onPressed: () => setState(() => _showHex = !_showHex),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => setState(() {
              _received.clear();
              _rxBytes = 0;
              _txBytes = 0;
            }),
          ),
          IconButton(
            tooltip: 'Logs',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LogsPage())),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _connectionBar(connected),
            if (_problem != null) _problemBanner(_problem!),
            if (!connected && _supported) _settings(),
            if (connected) _signals(),
            const Divider(height: 1),
            Expanded(child: _terminalOrHelp(connected)),
            const Divider(height: 1),
            _sendBar(connected),
          ],
        ),
      ),
    );
  }

  Widget _connectionBar(bool connected) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<DeviceHandle>(
            initialValue: _selected,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Port',
              border: const OutlineInputBorder(),
              isDense: true,
              helperText: _chooser ? 'Ports this site may use' : null,
            ),
            hint: Text(_chooser ? 'No port chosen yet' : 'No ports found'),
            items: [
              for (final d in _devices)
                DropdownMenuItem(
                  value: d,
                  child: Text(_label(d), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: connected ? null : (d) => setState(() => _selected = d),
          ),
        ),
        const SizedBox(width: 8),
        if (_chooser)
          OutlinedButton.icon(
            onPressed: connected || !_supported ? null : _pickPort,
            icon: const Icon(Icons.usb),
            label: const Text('Choose port'),
          )
        else
          IconButton.outlined(
            tooltip: 'Refresh',
            onPressed: connected ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        const SizedBox(width: 8),
        connected
            ? FilledButton.tonal(
                onPressed: _disconnect,
                child: const Text('Disconnect'),
              )
            : FilledButton(
                onPressed: _selected == null || _connecting ? null : _connect,
                child: Text(_connecting ? 'Connecting…' : 'Connect'),
              ),
      ],
    ),
  );

  Widget _problemBanner(Problem problem) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      problem.title,
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (problem.hint != null)
                      Text(
                        problem.hint!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close, color: scheme.onErrorContainer),
                onPressed: () => setState(() => _problem = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _terminalOrHelp(bool connected) {
    if (!connected && _received.isEmpty && _supported) {
      return _Help(chooser: _chooser, hasPorts: _devices.isNotEmpty);
    }
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: SelectableText(
          _output(),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }

  Widget _settings() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown<int>(
          'Baud',
          _config.baudRate,
          _baudRates,
          (v) => '$v',
          (v) => _config = _config.copyWith(baudRate: v),
        ),
        _dropdown<int>(
          'Data',
          _config.dataBits,
          const [8, 7, 6, 5],
          (v) => '$v',
          (v) => _config = _config.copyWith(dataBits: v),
        ),
        _dropdown<Parity>(
          'Parity',
          _config.parity,
          Parity.values,
          (v) => v.name,
          (v) => _config = _config.copyWith(parity: v),
        ),
        _dropdown<StopBits>(
          'Stop',
          _config.stopBits,
          StopBits.values,
          (v) => switch (v) {
            StopBits.one => '1',
            StopBits.onePointFive => '1.5',
            StopBits.two => '2',
          },
          (v) => _config = _config.copyWith(stopBits: v),
        ),
      ],
    ),
  );

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> values,
    String Function(T) text,
    void Function(T) onChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label '),
      DropdownButton<T>(
        value: value,
        items: [
          for (final v in values)
            DropdownMenuItem(value: v, child: Text(text(v))),
        ],
        onChanged: (v) {
          if (v != null) setState(() => onChanged(v));
        },
      ),
    ],
  );

  Widget _signals() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${_config.baudRate} baud · RX $_rxBytes · TX $_txBytes',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Text('DTR'),
        Switch(
          value: _dtr,
          onChanged: (v) => _setSignals(dtr: v),
        ),
        const SizedBox(width: 8),
        const Text('RTS'),
        Switch(
          value: _rts,
          onChanged: (v) => _setSignals(rts: v),
        ),
      ],
    ),
  );

  Widget _sendBar(bool connected) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _sendController,
            enabled: connected,
            decoration: InputDecoration(
              hintText: _sendHex ? 'Hex bytes, e.g. 01 A0 ff' : 'Text to send',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<Object>(
          value: _sendHex ? 'hex' : _ending,
          items: [
            for (final e in LineEnding.values)
              DropdownMenuItem(
                value: e,
                child: Text(e == LineEnding.none ? 'text' : '+${e.name}'),
              ),
            const DropdownMenuItem(value: 'hex', child: Text('hex')),
          ],
          onChanged: (v) => setState(() {
            _sendHex = v == 'hex';
            if (v is LineEnding) _ending = v;
          }),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Send',
          onPressed: connected ? _send : null,
          icon: const Icon(Icons.send),
        ),
      ],
    ),
  );
}

/// Step-by-step help shown before the first connection.
class _Help extends StatelessWidget {
  const _Help({required this.chooser, required this.hasPorts});

  final bool chooser;
  final bool hasPorts;

  @override
  Widget build(BuildContext context) {
    final steps = chooser
        ? [
            'Plug in your USB serial adapter or board.',
            'Click "Choose port" and pick it in the browser popup '
                '(for example "USB Serial" or "cu.usbserial…").',
            'Set the baud rate your device uses, then click Connect.',
            'Chosen ports are remembered for this site next time.',
          ]
        : [
            'Plug in the adapter with a USB OTG cable or adapter.',
            hasPorts
                ? 'Pick it under Port and tap Connect.'
                : 'Tap Refresh if it does not appear under Port.',
            'Allow the USB permission dialog.',
            'Set the baud rate your device uses.',
          ];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Getting started', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final (i, step) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 12, child: Text('${i + 1}')),
                const SizedBox(width: 12),
                Expanded(child: Text(step)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Something not working? Open Logs (bug icon) and copy the log '
          'into your bug report.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Shows skio's log with a level selector, copy and clear.
class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  static const _levels = [
    LogLevel.info,
    LogLevel.debug,
    LogLevel.trace,
    LogLevel.off,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: logBook,
    builder: (context, _) {
      final records = logBook.records;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          actions: [
            DropdownButton<LogLevel>(
              value: logBook.level,
              underline: const SizedBox.shrink(),
              items: [
                for (final l in _levels)
                  DropdownMenuItem(
                    value: l,
                    child: Text(switch (l) {
                      LogLevel.trace => 'Trace (all bytes)',
                      LogLevel.off => 'Off',
                      _ => l.name[0].toUpperCase() + l.name.substring(1),
                    }),
                  ),
              ],
              onChanged: (l) {
                if (l != null) logBook.setLevel(l);
              },
            ),
            IconButton(
              tooltip: 'Copy all',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: logBook.asText()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied ${records.length} lines')),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: logBook.clear,
            ),
          ],
        ),
        body: records.isEmpty
            ? const Center(child: Text('Nothing logged yet'))
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(8),
                itemCount: records.length,
                itemBuilder: (context, i) {
                  final r = records[records.length - 1 - i];
                  return _LogLine(record: r);
                },
              ),
      );
    },
  );
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.record});

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (record.level) {
      LogLevel.error || LogLevel.warning => scheme.error,
      LogLevel.trace => scheme.outline,
      _ => scheme.onSurface,
    };
    final t = record.time;
    String two(int v) => v.toString().padLeft(2, '0');
    final time =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final error = record.error == null ? '' : '  (${record.error})';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        '$time ${record.level.name.toUpperCase().padRight(7)} '
        '${record.message}$error',
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color),
      ),
    );
  }
}
