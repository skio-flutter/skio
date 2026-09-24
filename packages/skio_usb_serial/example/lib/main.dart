// A general-purpose USB serial terminal built on skio_usb_serial.
//
// Works with any USB serial adapter or board (CP210x, CH340, FTDI, CDC-ACM,
// Arduino, ESP32, ...) on Android over USB OTG and in desktop Chrome/Edge.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:skio_usb_serial/skio_usb_serial.dart';

void main() => runApp(const TerminalApp());

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'skio serial terminal',
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

  final _received = BytesBuilder();
  bool _showHex = false;
  bool _sendHex = false;
  LineEnding _ending = LineEnding.lf;

  final _sendController = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<DeviceEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = UsbSerialPort.events.listen((event) {
      _toast(switch (event) {
        DeviceAttached() => 'Attached: ${_label(event.device)}',
        DeviceDetached() => 'Detached: ${_label(event.device)}',
      });
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
    try {
      final device = await UsbSerialPort.request();
      await _refresh();
      if (device != null) setState(() => _selected = device);
    } on HardwareException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _connect() async {
    final device = _selected;
    if (device == null) return;
    try {
      var access = await UsbSerialPort.access.checkAccess(device);
      if (!access.isUsable) {
        access = await UsbSerialPort.access.requestAccess(device);
      }
      if (!access.isUsable) {
        _toast('Permission ${access.status.name}. ${access.hint ?? ''}');
        return;
      }
      final port = await UsbSerialPort.open(
        device,
        config: _config.copyWith(dtr: _dtr, rts: _rts),
      );
      port.input.listen(
        _onData,
        onError: (Object e) =>
            _toast(e is HardwareException ? e.message : '$e'),
        onDone: () {
          if (mounted) setState(() => _port = null);
        },
      );
      setState(() => _port = port);
    } on HardwareException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _disconnect() async {
    await _port?.close();
    setState(() => _port = null);
  }

  void _onData(Uint8List bytes) {
    setState(() => _received.add(bytes));
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
      _sendController.clear();
    } on HardwareException catch (e) {
      _toast(e.message);
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
      _toast(e.message);
    }
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
            onPressed: () => setState(_received.clear),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _connectionBar(connected),
            if (!connected) _settings(),
            if (connected) _signals(),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    _output(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
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
            decoration: const InputDecoration(
              labelText: 'Port',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            hint: const Text('No ports found'),
            items: [
              for (final d in _devices)
                DropdownMenuItem(value: d, child: Text(_label(d))),
            ],
            onChanged: connected ? null : (d) => setState(() => _selected = d),
          ),
        ),
        const SizedBox(width: 8),
        if (UsbSerialPort.requiresUserSelection)
          IconButton.outlined(
            tooltip: 'Pick a port',
            onPressed: connected ? null : _pickPort,
            icon: const Icon(Icons.add_link),
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
                onPressed: _selected == null ? null : _connect,
                child: const Text('Connect'),
              ),
      ],
    ),
  );

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
        Text('${_config.baudRate} baud'),
        const Spacer(),
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
