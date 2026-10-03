// A general-purpose serial terminal built on skio_uart.
//
// Opens any serial port by path: a UART wired to the board (/dev/ttyS3 on
// an Android panel, /dev/ttyTHS1 on a Jetson), a USB serial adapter
// (/dev/ttyUSB0, /dev/cu.usbserial-0001) or a COM port on Windows.
// The Logs page shows skio's own log, so problems can be diagnosed on the
// device without a debugger.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:skio_uart/skio_uart.dart';

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
    title: 'skio UART terminal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
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

/// An example path for this platform, shown in the empty Port box.
String get _examplePath {
  if (Platform.isAndroid) return '/dev/ttyS3';
  if (Platform.isWindows) return 'COM3';
  if (Platform.isMacOS) return '/dev/cu.usbserial-0001';
  return '/dev/ttyUSB0';
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  static const _baudRates = [
    1200,
    2400,
    4800,
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

  List<DeviceHandle> _ports = const [];
  final _pathController = TextEditingController();
  SerialConfig _config = const SerialConfig(baudRate: 9600);
  SerialPort? _port;
  bool _dtr = false;
  bool _rts = false;
  bool _connecting = false;
  Problem? _problem;
  ModemStatus? _status;

  final _received = BytesBuilder();
  int _rxBytes = 0;
  int _txBytes = 0;
  bool _showHex = false;
  bool _sendHex = false;
  LineEnding _ending = LineEnding.crlf;

  final _sendController = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DeviceEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = SerialPort.events.listen((event) {
      final text = switch (event) {
        DeviceAttached() => 'Port added: ${event.device.id}',
        DeviceDetached() => 'Port removed: ${event.device.id}',
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
    _pathController.dispose();
    _sendController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ports = await SerialPort.list();
    if (!mounted) return;
    setState(() {
      _ports = ports;
      if (_pathController.text.isEmpty && ports.isNotEmpty) {
        _pathController.text = ports.first.id;
      }
    });
  }

  Future<void> _connect() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _connecting = true;
      _problem = null;
      _status = null;
    });
    try {
      final port = await SerialPort.open(
        path,
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
        _toast('Hex must be pairs like "01 03 00 00"');
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

  Future<void> _readStatus() async {
    try {
      final status = await _port?.getSignals();
      setState(() => _status = status);
    } on HardwareException catch (e) {
      _report(e);
    }
  }

  /// Shows [e] inline with a hint on what to do, and logs it.
  void _report(HardwareException e) {
    logBook.note(e.message, level: LogLevel.warning, error: e.cause);
    final hint = switch (e) {
      DeviceBusy() =>
        'Close other programs using the port (serial monitors, IDEs, '
            'getty consoles), then connect again.',
      // The message already says how to fix it on this platform.
      AccessDenied() => null,
      DeviceNotFound() =>
        Platform.isWindows
            ? 'Check the COM number in Device Manager under '
                  '"Ports (COM & LPT)".'
            : 'Check the path. Panel makers list their ports in the '
                  'manual, usually /dev/ttyS1 to /dev/ttyS4.',
      Disconnected() => 'Check the cable, then connect again.',
      OperationTimeout() =>
        'The port did not accept data. Check the flow control setting.',
      Unsupported() => 'Try other settings (8N1 works with every port).',
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
        : '  ${hex(d.vendorId!)}:${hex(d.productId ?? 0)}';
    final name = d.name == null || d.name == d.id ? '' : '  ${d.name}';
    return '${d.id}$name$ids';
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
        title: const Text('UART terminal'),
        actions: [
          // Text labels next to the icons, so every button explains itself.
          TextButton.icon(
            onPressed: () => setState(() => _showHex = !_showHex),
            icon: Icon(_showHex ? Icons.text_fields : Icons.hexagon_outlined),
            label: Text(_showHex ? 'Text' : 'Hex'),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _received.clear();
              _rxBytes = 0;
              _txBytes = 0;
            }),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LogsPage())),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Logs'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _connectionBar(connected),
            if (_problem != null) _problemBanner(_problem!),
            if (!connected) _settings(),
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

  Widget _connectionBar(bool connected) {
    final pathField = TextField(
      controller: _pathController,
      enabled: !connected,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Port',
        hintText: _examplePath,
        border: const OutlineInputBorder(),
        isDense: true,
        helperText: _ports.isEmpty
            ? 'None found automatically; type the path'
            : '${_ports.length} found; pick one or type a path',
        suffixIcon: PopupMenuButton<String>(
          tooltip: 'Ports found',
          enabled: !connected && _ports.isNotEmpty,
          icon: const Icon(Icons.arrow_drop_down),
          onSelected: (id) => setState(() => _pathController.text = id),
          itemBuilder: (_) => [
            for (final p in _ports)
              PopupMenuItem(value: p.id, child: Text(_label(p))),
          ],
        ),
      ),
      onSubmitted: (_) => connected ? null : _connect(),
    );
    final buttons = [
      OutlinedButton.icon(
        onPressed: connected ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      const SizedBox(width: 8),
      connected
          ? FilledButton.tonal(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            )
          : ListenableBuilder(
              listenable: _pathController,
              builder: (context, _) => FilledButton(
                onPressed: _pathController.text.trim().isEmpty || _connecting
                    ? null
                    : _connect,
                child: Text(_connecting ? 'Connecting…' : 'Connect'),
              ),
            ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      // On narrow screens the buttons go below the port box so its text
      // stays readable.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                children: [
                  pathField,
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: buttons,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pathField),
                  const SizedBox(width: 8),
                  ...buttons,
                ],
              ),
      ),
    );
  }

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
                    SelectableText(
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
    if (!connected && _received.isEmpty) return const _Help();
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
        _dropdown<FlowControl>(
          'Flow',
          _config.flowControl,
          FlowControl.values,
          (v) => switch (v) {
            FlowControl.none => 'none',
            FlowControl.rtsCts => 'RTS/CTS',
            FlowControl.dtrDsr => 'DTR/DSR',
            FlowControl.xonXoff => 'XON/XOFF',
          },
          (v) => _config = _config.copyWith(flowControl: v),
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

  Widget _signals() {
    final status = _status;
    String on(bool v) => v ? 'on' : 'off';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${_config.baudRate} baud · RX $_rxBytes · TX $_txBytes'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          TextButton.icon(
            onPressed: _readStatus,
            icon: const Icon(Icons.sensors),
            label: Text(
              status == null
                  ? 'Read CTS/DSR'
                  : 'CTS ${on(status.cts)} · DSR ${on(status.dsr)} · '
                        'DCD ${on(status.dcd)} · RI ${on(status.ri)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendBar(bool connected) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _sendController,
            enabled: connected,
            decoration: InputDecoration(
              hintText: _sendHex
                  ? 'Hex bytes, e.g. 01 03 00 00 00 02'
                  : 'Text to send',
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
        FilledButton.icon(
          onPressed: connected ? _send : null,
          icon: const Icon(Icons.send),
          label: const Text('Send'),
        ),
      ],
    ),
  );
}

/// Step-by-step help shown before the first connection.
class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    final steps = Platform.isAndroid
        ? const [
            'Wire your device to the panel\'s UART: its TX to the panel\'s RX, '
                'its RX to the panel\'s TX, and GND to GND.',
            'Type the port path from the panel\'s manual under Port, '
                'usually /dev/ttyS1 to /dev/ttyS4, or pick one from the list.',
            'Set the baud rate and line settings your device uses, then '
                'tap Connect.',
            'If Android refuses access, the panel\'s system image has to '
                'allow it; the error message says how to check.',
          ]
        : Platform.isWindows
        ? const [
            'Plug in or wire up your device.',
            'Pick its COM port under Port. Device Manager lists them under '
                '"Ports (COM & LPT)".',
            'Set the baud rate your device uses, then click Connect.',
          ]
        : Platform.isMacOS
        ? const [
            'Plug in your USB serial adapter or board.',
            'Pick it under Port (click Refresh if it is not listed).',
            'Set the baud rate your device uses, then click Connect.',
          ]
        : const [
            'Wire your device to the board\'s UART pins (TX to RX, RX to '
                'TX, GND to GND) or plug in a USB serial adapter.',
            'Pick the port under Port: /dev/ttyTHS* on Jetson, '
                '/dev/ttyAMA0 or /dev/serial0 on Raspberry Pi, '
                '/dev/ttyUSB* or /dev/ttyACM* for USB.',
            'Make sure your user is in the dialout group.',
            'Set the baud rate your device uses, then click Connect.',
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
          'Quick test without a device: connect the port\'s TX pin to its '
          'own RX pin with a jumper wire. Everything you send comes back.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Something not working? Open Logs and copy the log into your '
          'bug report.',
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
            TextButton.icon(
              label: const Text('Copy'),
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
            TextButton.icon(
              label: const Text('Clear'),
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
