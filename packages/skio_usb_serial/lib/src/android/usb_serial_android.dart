import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:skio_core/skio_core.dart';

import '../platform/default_platform.dart' as fallback;
import '../platform/usb_serial_platform.dart';
import '../serial_config.dart';
import 'bindings.g.dart' as a;

/// Picks the Android implementation on Android, and the unsupported fallback
/// on other native platforms.
UsbSerialPlatform createDefaultPlatform() => Platform.isAndroid
    ? AndroidUsbSerialPlatform()
    : fallback.createDefaultPlatform();

/// [UsbSerialPlatform] for Android USB host (OTG), calling `UsbManager` and
/// usb-serial-for-android directly through JNI.
final class AndroidUsbSerialPlatform extends UsbSerialPlatform {
  /// Creates the Android platform.
  AndroidUsbSerialPlatform();

  static const _permissionAction = 'dev.skio.usb_serial.USB_PERMISSION';

  /// How often attach/detach is checked while [events] has listeners.
  static const pollInterval = Duration(seconds: 1);

  late final a.Context _context = androidApplicationContext.as(a.Context.type);

  late final a.UsbManager _usb = _context
      .getSystemService$1(a.Context.USB_SERVICE)!
      .as(a.UsbManager.type, releaseOriginal: true);

  @override
  bool get requiresUserSelection => false;

  // ---------------------------------------------------------------- access

  @override
  Future<AccessReport> checkAccess([DeviceHandle? device]) async {
    // USB serial needs no runtime permission, only a per-device grant.
    if (device == null) return const AccessReport(AccessStatus.notRequired);
    final found = _find(device);
    try {
      return _usb.hasPermission$1(found.usbDevice)
          ? const AccessReport(AccessStatus.granted)
          : const AccessReport(
              AccessStatus.denied,
              hint: 'Call requestAccess(device) to show the USB dialog.',
            );
    } finally {
      found.release();
    }
  }

  @override
  Future<AccessReport> requestAccess([DeviceHandle? device]) async {
    if (device == null) return const AccessReport(AccessStatus.notRequired);
    final found = _find(device);
    try {
      if (_usb.hasPermission$1(found.usbDevice)) {
        return const AccessReport(AccessStatus.granted);
      }
      final intent = a.Intent.new$3(_permissionAction.toJString())
        ..setPackage(_context.packageName);
      // The system adds the result as an extra, so the PendingIntent must be
      // mutable from Android 12. It is explicit (setPackage), as Android 14
      // requires for mutable PendingIntents.
      final flags = a.Build$VERSION.SDK_INT >= 31
          ? a.PendingIntent.FLAG_MUTABLE
          : 0;
      final pending = a.PendingIntent.getBroadcast(
        _context,
        0,
        intent,
        flags | a.PendingIntent.FLAG_UPDATE_CURRENT,
      );
      _usb.requestPermission$1(found.usbDevice, pending);
      final granted = await _waitForPermission(found.usbDevice);
      pending?.release();
      intent.release();
      return granted
          ? const AccessReport(AccessStatus.granted)
          : const AccessReport(AccessStatus.denied);
    } finally {
      found.release();
    }
  }

  /// Polls for the grant instead of registering a BroadcastReceiver (which
  /// would need handwritten Java). The dialog pauses the app; once the app
  /// resumes without a grant, the user said no.
  Future<bool> _waitForPermission(a.UsbDevice usbDevice) async {
    var dialogShown = false;
    DateTime? resumedAt;
    AppLifecycleListener? listener;
    try {
      listener = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.resumed) {
            if (dialogShown) resumedAt = DateTime.now();
          } else {
            dialogShown = true;
          }
        },
      );
    } catch (_) {
      // No widgets binding (for example in a background isolate): fall back
      // to the timeout alone.
    }
    final deadline = DateTime.now().add(const Duration(minutes: 1));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_usb.hasPermission$1(usbDevice)) return true;
        final resumed = resumedAt;
        if (resumed != null &&
            DateTime.now().difference(resumed) >
                const Duration(milliseconds: 800)) {
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return false;
    } finally {
      listener?.dispose();
    }
  }

  @override
  Future<bool> openSettings() async {
    final package = _context.packageName;
    final uri = a.Uri.fromParts('package'.toJString(), package, null);
    final intent =
        a.Intent.new$3(
            'android.settings.APPLICATION_DETAILS_SETTINGS'.toJString(),
          )
          ..setData(uri)
          ..addFlags(a.Intent.FLAG_ACTIVITY_NEW_TASK);
    try {
      _context.startActivity(intent);
      return true;
    } on JThrowable {
      return false;
    } finally {
      intent.release();
      uri?.release();
    }
  }

  // ----------------------------------------------------------- discovery

  @override
  Future<List<DeviceHandle>> list() async {
    final handles = <DeviceHandle>[];
    _forEachPort((driver, usbDevice, port, index, portCount) {
      handles.add(_handle(usbDevice, index, portCount));
      return false;
    });
    return handles;
  }

  @override
  Future<DeviceHandle?> request(List<DeviceFilter> filters) async =>
      throw const Unsupported(
        'Android has no port chooser. Use UsbSerialPort.list() and '
        'requestAccess(device).',
      );

  @override
  Stream<DeviceEvent> get events {
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
        timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  /// Calls [visit] for each port of each attached serial device until it
  /// returns true. Objects passed to [visit] are released afterwards unless
  /// [visit] returns true, in which case the caller owns them.
  void _forEachPort(
    bool Function(
      a.UsbSerialDriver driver,
      a.UsbDevice usbDevice,
      a.UsbSerialPort port,
      int index,
      int portCount,
    )
    visit,
  ) {
    final prober = a.UsbSerialProber.defaultProber!;
    final drivers = prober.findAllDrivers(_usb)!;
    final driverList = drivers.asDart();
    try {
      for (var i = 0; i < driverList.length; i++) {
        final driver = driverList[i]!;
        final usbDevice = driver.getDevice()!;
        final ports = driver.getPorts()!;
        final portList = ports.asDart();
        var kept = false;
        for (var p = 0; p < portList.length; p++) {
          final port = portList[p]!;
          if (visit(driver, usbDevice, port, p, portList.length)) {
            kept = true;
            break;
          }
          port.release();
        }
        ports.release();
        if (kept) return;
        usbDevice.release();
        driver.release();
      }
    } finally {
      drivers.release();
      prober.release();
    }
  }

  DeviceHandle _handle(a.UsbDevice usbDevice, int index, int portCount) {
    final path = usbDevice.deviceName!.toDartString(releaseOriginal: true);
    String? name;
    try {
      name = usbDevice.productName?.toDartString(releaseOriginal: true);
    } on JThrowable {
      // Some devices refuse string descriptors before permission is granted.
    }
    return DeviceHandle(
      // Multi-port adapters (FT2232, CP2105) get one handle per port.
      id: portCount > 1 ? '$path#$index' : path,
      name: portCount > 1
          ? '${name ?? 'USB serial'} (port ${index + 1})'
          : name,
      vendorId: usbDevice.vendorId,
      productId: usbDevice.productId,
    );
  }

  _Found _find(DeviceHandle device) {
    _Found? found;
    _forEachPort((driver, usbDevice, port, index, portCount) {
      if (_handle(usbDevice, index, portCount).id != device.id) return false;
      found = _Found(driver, usbDevice, port);
      return true;
    });
    return found ??
        (throw DeviceNotFound(
          'The device is no longer attached.',
          device: device,
        ));
  }

  // ---------------------------------------------------------------- open

  @override
  Future<SerialConnection> open(
    DeviceHandle device,
    SerialConfig config,
  ) async {
    final found = _find(device);
    if (!_usb.hasPermission$1(found.usbDevice)) {
      found.release();
      throw AccessDenied(
        'No USB permission for this device. Call requestAccess(device) first.',
        device: device,
      );
    }
    final connection = _usb.openDevice(found.usbDevice);
    if (connection == null) {
      found.release();
      throw DeviceBusy('Could not open the USB device.', device: device);
    }
    final port = found.port;
    try {
      port.open(connection);
    } on JThrowable catch (e) {
      connection
        ..close()
        ..release();
      found.release();
      throw DeviceBusy(
        'The port could not be opened. Another app may be using it.',
        device: device,
        cause: e.message,
      );
    }
    try {
      port.setParameters(
        config.baudRate,
        config.dataBits,
        switch (config.stopBits) {
          StopBits.one => a.UsbSerialPort.STOPBITS_1,
          StopBits.onePointFive => a.UsbSerialPort.STOPBITS_1_5,
          StopBits.two => a.UsbSerialPort.STOPBITS_2,
        },
        switch (config.parity) {
          Parity.none => a.UsbSerialPort.PARITY_NONE,
          Parity.odd => a.UsbSerialPort.PARITY_ODD,
          Parity.even => a.UsbSerialPort.PARITY_EVEN,
          Parity.mark => a.UsbSerialPort.PARITY_MARK,
          Parity.space => a.UsbSerialPort.PARITY_SPACE,
        },
      );
      if (config.flowControl != FlowControl.none) {
        final mode = switch (config.flowControl) {
          FlowControl.none => a.UsbSerialPort$FlowControl.NONE,
          FlowControl.rtsCts => a.UsbSerialPort$FlowControl.RTS_CTS,
          FlowControl.dtrDsr => a.UsbSerialPort$FlowControl.DTR_DSR,
          FlowControl.xonXoff => a.UsbSerialPort$FlowControl.XON_XOFF_INLINE,
        };
        try {
          port.setFlowControl(mode);
        } finally {
          mode.release();
        }
      }
      if (config.dtr case final dtr?) port.setDTR(dtr);
      if (config.rts case final rts?) port.setRTS(rts);
    } on JThrowable catch (e) {
      try {
        port.close();
      } on JThrowable {
        // Closing after a failed setup can fail too; nothing more to do.
      }
      found.release();
      throw Unsupported(
        'This adapter does not support $config.',
        device: device,
        cause: e.message,
      );
    }
    // The port keeps its own Java reference to the connection.
    connection.release();
    found.releaseAllButPort();
    return _AndroidSerialConnection(port, device)..start();
  }
}

final class _Found {
  _Found(this.driver, this.usbDevice, this.port);

  final a.UsbSerialDriver driver;
  final a.UsbDevice usbDevice;
  final a.UsbSerialPort port;

  void releaseAllButPort() {
    usbDevice.release();
    driver.release();
  }

  void release() {
    port.release();
    releaseAllButPort();
  }
}

final class _AndroidSerialConnection implements SerialConnection {
  _AndroidSerialConnection(this._port, this._device);

  final a.UsbSerialPort _port;
  final DeviceHandle _device;
  final _input = StreamController<Uint8List>();
  a.SerialInputOutputManager? _io;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _input.stream;

  void start() {
    // Both callbacks are async so the library's I/O thread never waits for
    // Dart.
    final listener = a.SerialInputOutputManager$Listener.implement(
      a.$SerialInputOutputManager$Listener(
        onNewData: _onNewData,
        onNewData$async: true,
        onRunError: _onRunError,
        onRunError$async: true,
      ),
    );
    _io = a.SerialInputOutputManager.new$1(_port, listener)
      // A non-zero read timeout avoids the per-read status check that some
      // phones time out on, which the library reports as a disconnect.
      ..readTimeout = 1000
      ..writeBufferSize = _writeBufferSize
      ..start();
  }

  void _onNewData(JByteArray? bytes) {
    if (bytes == null) return;
    try {
      final length = bytes.length;
      if (length > 0 && !_closed) {
        final signed = bytes.getRange(0, length);
        _input.add(
          Uint8List.fromList(
            signed.buffer.asUint8List(signed.offsetInBytes, signed.length),
          ),
        );
      }
    } finally {
      bytes.release();
    }
  }

  void _onRunError(a.Exception? error) {
    final message = error?.toString() ?? '';
    error?.release();
    if (_closed) return;
    // The library stops its I/O threads after any error, so the port is
    // unusable either way; the error type tells the app why.
    _input.addError(
      message.contains('SerialTimeoutException')
          ? OperationTimeout(
              'The device did not accept data in time',
              timeout: Duration.zero,
              device: _device,
              cause: message,
            )
          : Disconnected(
              'The device was disconnected or stopped responding.',
              device: _device,
              cause: message,
            ),
    );
    unawaited(close());
  }

  /// Size of the library's write buffer. Its default is 4 KB.
  static const _writeBufferSize = 64 * 1024;

  /// Largest piece handed to the library at once; must fit the buffer.
  static const _chunkSize = 16 * 1024;

  /// Writes by queueing data to the library's write thread, so the UI thread
  /// never blocks on USB. The library's buffer is fixed-size and throws when
  /// full, so data is queued in chunks and retried until [timeout] passes.
  /// Errors on the write thread itself arrive through [_onRunError].
  @override
  Future<void> write(Uint8List data, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    var offset = 0;
    while (offset < data.length) {
      final io = _io;
      if (_closed || io == null) {
        throw Disconnected('Port is closed', device: _device);
      }
      final end = offset + _chunkSize < data.length
          ? offset + _chunkSize
          : data.length;
      final chunk = JByteArray.of(Uint8List.sublistView(data, offset, end));
      try {
        io
          ..writeTimeout = timeout.inMilliseconds
          ..writeAsync(chunk);
        offset = end;
      } on JThrowable catch (e) {
        if (!e.message.contains('BufferOverflowException')) {
          throw Disconnected('Write failed', device: _device, cause: e.message);
        }
        // Buffer full: the device is slower than the app. Wait for room.
        if (DateTime.now().isAfter(deadline)) {
          throw OperationTimeout(
            'The device did not accept data in time',
            timeout: timeout,
            device: _device,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      } finally {
        chunk.release();
      }
    }
  }

  @override
  Future<void> setSignals({bool? dtr, bool? rts}) async {
    if (_closed) throw Disconnected('Port is closed', device: _device);
    try {
      if (dtr != null) _port.setDTR(dtr);
      if (rts != null) _port.setRTS(rts);
    } on JThrowable catch (e) {
      throw ProtocolError(
        'Could not set signals',
        device: _device,
        cause: e.message,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _io?.stop();
    } on JThrowable {
      // Already stopped.
    }
    try {
      if (_port.isOpen()) _port.close();
    } on JThrowable {
      // Already closed, or the device is gone.
    }
    _io?.release();
    _io = null;
    _port.release();
    unawaited(_input.close());
  }
}
