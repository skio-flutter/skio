import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:skio_core/skio_core.dart';
import 'package:web/web.dart' as web;

import '../platform/usb_serial_platform.dart';
import '../serial_config.dart';
import 'web_serial_bindings.dart';

/// Web Serial implementation entry point, registered by Flutter on the web.
final class UsbSerialWeb {
  UsbSerialWeb._();

  /// Called by the Flutter web plugin registrant.
  static void registerWith(Registrar registrar) {
    UsbSerialPlatform.instance = createDefaultPlatform();
  }
}

/// Picks the Web Serial implementation.
UsbSerialPlatform createDefaultPlatform() => WebSerialPlatform();

/// [UsbSerialPlatform] backed by the browser's Web Serial API.
final class WebSerialPlatform extends UsbSerialPlatform {
  /// Creates the web platform.
  WebSerialPlatform() : _serial = navigatorSerial;

  final Serial? _serial;

  // Web Serial has no stable port id, so ports are numbered in the order this
  // page first sees them. The same SerialPort object is returned for the same
  // port while the page is open.
  final _known = <SerialPort>[];

  static const _unsupported = AccessReport(
    AccessStatus.unsupported,
    hint:
        'Web Serial needs Chrome or Edge on desktop, over https or localhost.',
  );

  @override
  bool get requiresUserSelection => true;

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async {
    if (_serial == null) return _unsupported;
    final ports = await list();
    final granted = device == null
        ? ports.isNotEmpty
        : ports.any((p) => p.id == device.id);
    return granted
        ? const AccessReport(AccessStatus.granted)
        : const AccessReport(
            AccessStatus.denied,
            hint: 'Call requestAccess() from a user gesture to pick a port.',
          );
  }

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async {
    if (_serial == null) return _unsupported;
    if (device != null) {
      final report = await checkAccess(device);
      if (report.status == AccessStatus.granted) return report;
    }
    try {
      final picked = await request(const []);
      return picked == null
          ? const AccessReport(AccessStatus.denied)
          : const AccessReport(AccessStatus.granted);
    } on AccessDenied catch (e) {
      return AccessReport(AccessStatus.denied, hint: e.message);
    }
  }

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<List<DeviceHandle>> list() async {
    final serial = _serial;
    if (serial == null) return const [];
    final ports = (await serial.getPorts().toDart).toDart;
    return [for (final p in ports) _handle(p)];
  }

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async {
    final serial = _serial;
    if (serial == null) throw Unsupported(_unsupported.hint!);
    final options = SerialPortRequestOptions(
      filters: [
        for (final f in filters)
          if (f.vendorId != null)
            f.productId == null
                ? SerialPortFilter(usbVendorId: f.vendorId!)
                : SerialPortFilter(
                    usbVendorId: f.vendorId!,
                    usbProductId: f.productId!,
                  ),
      ].toJS,
    );
    try {
      return _handle(await serial.requestPort(options).toDart);
    } catch (e) {
      final name = _errorName(e);
      if (name == 'NotFoundError') return null; // user cancelled
      if (name == 'SecurityError') {
        throw AccessDenied(
          'The port chooser must be opened from a user gesture such as a tap.',
          cause: e,
        );
      }
      throw ProtocolError('Could not open the port chooser', cause: e);
    }
  }

  @override
  Stream<DeviceEvent> get events {
    final serial = _serial;
    if (serial == null) return const Stream.empty();
    late final StreamController<DeviceEvent> controller;
    final onConnect = ((web.Event e) {
      controller.add(DeviceAttached(_handle(e.target! as SerialPort)));
    }).toJS;
    final onDisconnect = ((web.Event e) {
      controller.add(DeviceDetached(_handle(e.target! as SerialPort)));
    }).toJS;
    controller = StreamController<DeviceEvent>.broadcast(
      onListen: () {
        serial
          ..addEventListener('connect', onConnect)
          ..addEventListener('disconnect', onDisconnect);
      },
      onCancel: () {
        serial
          ..removeEventListener('connect', onConnect)
          ..removeEventListener('disconnect', onDisconnect);
      },
    );
    return controller.stream;
  }

  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    final options = _options(config, device);
    final port = await _find(device);
    try {
      await port.open(options).toDart;
    } catch (e) {
      throw switch (_errorName(e)) {
        'InvalidStateError' => DeviceBusy(
          'The port is already open in this page.',
          device: device,
          cause: e,
        ),
        'NetworkError' => DeviceBusy(
          'The port is in use by another tab or app, or was unplugged.',
          device: device,
          cause: e,
        ),
        _ => ProtocolError('Could not open the port', device: device, cause: e),
      };
    }
    final connection = _WebSerialConnection(port, device);
    if (config.dtr != null || config.rts != null) {
      await connection.setSignals(dtr: config.dtr, rts: config.rts);
    }
    connection.startReading();
    return connection;
  }

  Future<SerialPort> _find(DeviceHandle device) async {
    await list(); // refresh _known with currently granted ports
    for (var i = 0; i < _known.length; i++) {
      if (_id(i) == device.id) return _known[i];
    }
    throw DeviceNotFound(
      'The port is no longer available. Pick it again with request().',
      device: device,
    );
  }

  DeviceHandle _handle(SerialPort port) {
    var index = _known.indexWhere((p) => p.strictEquals(port).toDart);
    if (index < 0) {
      _known.add(port);
      index = _known.length - 1;
    }
    final info = port.getInfo();
    return DeviceHandle(
      id: _id(index),
      name: info.usbVendorId == null ? 'Serial port' : 'USB serial port',
      vendorId: info.usbVendorId,
      productId: info.usbProductId,
    );
  }

  static String _id(int index) => 'web-serial-$index';

  static SerialOptions _options(SerialConfig config, DeviceHandle device) {
    Never unsupported(String what) =>
        throw Unsupported('Web Serial does not support $what.', device: device);
    if (config.dataBits != 7 && config.dataBits != 8) {
      unsupported('${config.dataBits} data bits');
    }
    return SerialOptions(
      baudRate: config.baudRate,
      dataBits: config.dataBits,
      stopBits: switch (config.stopBits) {
        StopBits.one => 1,
        StopBits.two => 2,
        StopBits.onePointFive => unsupported('1.5 stop bits'),
      },
      parity: switch (config.parity) {
        Parity.none => 'none',
        Parity.odd => 'odd',
        Parity.even => 'even',
        Parity.mark ||
        Parity.space => unsupported('${config.parity.name} parity'),
      },
      flowControl: switch (config.flowControl) {
        FlowControl.none => 'none',
        FlowControl.rtsCts => 'hardware',
        FlowControl.dtrDsr || FlowControl.xonXoff => unsupported(
          '${config.flowControl.name} flow control',
        ),
      },
      bufferSize: 64 * 1024,
    );
  }
}

const _domErrorNames = [
  'NotFoundError',
  'SecurityError',
  'InvalidStateError',
  'NetworkError',
  'BreakError',
  'BufferOverrunError',
  'FramingError',
  'ParityError',
];

/// The DOMException name of a rejected Web Serial promise.
///
/// Read from the error's text so it works the same when compiled with
/// dart2js and dart2wasm, which surface JS errors differently.
String? _errorName(Object error) {
  final text = error.toString();
  for (final name in _domErrorNames) {
    if (text.contains(name)) return name;
  }
  return null;
}

final class _WebSerialConnection implements SerialConnection {
  _WebSerialConnection(this._port, this._device);

  final SerialPort _port;
  final DeviceHandle _device;
  final _input = StreamController<Uint8List>();
  web.ReadableStreamDefaultReader? _reader;
  web.WritableStreamDefaultWriter? _writer;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _input.stream;

  Future<void>? _readLoopDone;

  void startReading() => _readLoopDone = _readLoop();

  Future<void> _readLoop() async {
    // A readable stream can end after a recoverable error (for example a
    // parity or buffer overrun error); Web Serial then provides a new one.
    while (!_closed) {
      final readable = _port.readable;
      if (readable == null) break;
      final reader = readable.getReader() as web.ReadableStreamDefaultReader;
      _reader = reader;
      try {
        while (true) {
          final result = await reader.read().toDart;
          if (result.done) break;
          final value = result.value;
          if (value.isA<JSUint8Array>()) {
            _input.add((value! as JSUint8Array).toDart);
          }
        }
      } catch (e) {
        if (_closed) break;
        final name = _errorName(e);
        if (name == 'NetworkError') {
          // The device was unplugged.
          _input.addError(
            Disconnected(
              'The device was disconnected',
              device: _device,
              cause: e,
            ),
          );
          break;
        }
        // Framing, parity or overrun error: the port stays usable.
      } finally {
        reader.releaseLock();
        _reader = null;
      }
    }
    await _input.close();
  }

  @override
  Future<void> write(Uint8List data, Duration timeout) async {
    final writable = _port.writable;
    if (_closed || writable == null) {
      throw Disconnected('Port is closed', device: _device);
    }
    final writer = _writer ??= writable.getWriter();
    try {
      await writer.write(data.toJS).toDart.timeout(timeout);
    } on TimeoutException catch (e) {
      throw OperationTimeout(
        'Write did not complete',
        timeout: timeout,
        device: _device,
        cause: e,
      );
    } catch (e) {
      throw Disconnected('Write failed', device: _device, cause: e);
    }
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    final signals = JSObject();
    if (dtr != null) signals.setProperty('dataTerminalReady'.toJS, dtr.toJS);
    if (rts != null) signals.setProperty('requestToSend'.toJS, rts.toJS);
    try {
      await _port.setSignals(signals as SerialOutputSignals).toDart;
    } catch (e) {
      throw ProtocolError('Could not set signals', device: _device, cause: e);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _reader?.cancel().toDart;
    } catch (_) {
      // Already cancelled or errored.
    }
    // The port can only close once the read loop has released its lock.
    await _readLoopDone;
    final writer = _writer;
    if (writer != null) {
      try {
        await writer.close().toDart;
      } catch (_) {
        // Stream already errored.
      }
      writer.releaseLock();
    }
    try {
      await _port.close().toDart;
    } catch (_) {
      // Already closed, or the device is gone.
    }
  }
}
