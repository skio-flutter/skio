// Typed bindings for the Web Serial API, which package:web does not cover.
// https://wicg.github.io/serial/
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `navigator.serial`, or `null` when the browser has no Web Serial.
Serial? get navigatorSerial {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has('serial')) return null;
  return navigator.getProperty<Serial>('serial'.toJS);
}

/// `navigator.serial`.
extension type Serial._(JSObject _) implements web.EventTarget {
  /// Ports the user granted to this origin before.
  external JSPromise<JSArray<SerialPort>> getPorts();

  /// Shows the port chooser. Needs a user gesture.
  external JSPromise<SerialPort> requestPort([
    SerialPortRequestOptions options,
  ]);
}

/// Options for `requestPort`.
extension type SerialPortRequestOptions._(JSObject _) implements JSObject {
  /// Creates chooser options.
  external factory SerialPortRequestOptions({
    JSArray<SerialPortFilter> filters,
  });
}

/// A chooser filter. Omitted fields match anything.
extension type SerialPortFilter._(JSObject _) implements JSObject {
  /// Creates a filter.
  external factory SerialPortFilter({int usbVendorId, int usbProductId});
}

/// A serial port the page has been granted.
extension type SerialPort._(JSObject _) implements web.EventTarget {
  /// Opens the port.
  external JSPromise<JSAny?> open(SerialOptions options);

  /// Closes the port. Streams must be unlocked first.
  external JSPromise<JSAny?> close();

  /// Sets modem control lines.
  external JSPromise<JSAny?> setSignals(SerialOutputSignals signals);

  /// USB identification of the port.
  external SerialPortInfo getInfo();

  /// Incoming bytes while open.
  external web.ReadableStream? get readable;

  /// Outgoing bytes while open.
  external web.WritableStream? get writable;
}

/// Identification of a port.
extension type SerialPortInfo._(JSObject _) implements JSObject {
  /// USB vendor ID, if the port is a USB device.
  external int? get usbVendorId;

  /// USB product ID, if the port is a USB device.
  external int? get usbProductId;
}

/// Line settings for `open`.
extension type SerialOptions._(JSObject _) implements JSObject {
  /// Creates open options.
  external factory SerialOptions({
    required int baudRate,
    int dataBits,
    int stopBits,
    String parity,
    int bufferSize,
    String flowControl,
  });
}

/// Modem control lines for `setSignals`. Omitted fields stay unchanged.
extension type SerialOutputSignals._(JSObject _) implements JSObject {
  /// Creates a signals object.
  external factory SerialOutputSignals({
    bool dataTerminalReady,
    bool requestToSend,
  });
}
