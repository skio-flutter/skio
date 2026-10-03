// Lists serial ports through IOKit, with the USB details of each port's
// parent device.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// A serial port as IOKit reports it.
final class IOKitSerialPort {
  /// Creates a port description.
  const IOKitSerialPort({
    required this.calloutPath,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.productName,
    this.vendorName,
  });

  /// The `/dev/cu.*` path, which opens without waiting for carrier detect.
  final String calloutPath;

  /// USB vendor ID, or `null` when the port is not on USB.
  final int? vendorId;

  /// USB product ID.
  final int? productId;

  /// USB serial number string.
  final String? serialNumber;

  /// USB product string.
  final String? productName;

  /// USB vendor string.
  final String? vendorName;
}

typedef _CFTypeRef = Pointer<Void>;

const _kCFStringEncodingUTF8 = 0x08000100;
const _kCFNumberSInt64Type = 4;
const _kIORegistryIterateRecursively = 1;
const _kIORegistryIterateParents = 2;

abstract final class _CF {
  static final _lib = DynamicLibrary.open(
    '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
  );

  static final createString = _lib
      .lookupFunction<
        _CFTypeRef Function(_CFTypeRef, Pointer<Utf8>, Uint32),
        _CFTypeRef Function(_CFTypeRef, Pointer<Utf8>, int)
      >('CFStringCreateWithCString');

  static final getCString = _lib
      .lookupFunction<
        Bool Function(_CFTypeRef, Pointer<Utf8>, Long, Uint32),
        bool Function(_CFTypeRef, Pointer<Utf8>, int, int)
      >('CFStringGetCString');

  static final getNumber = _lib
      .lookupFunction<
        Bool Function(_CFTypeRef, Long, Pointer<Void>),
        bool Function(_CFTypeRef, int, Pointer<Void>)
      >('CFNumberGetValue');

  static final getTypeID = _lib
      .lookupFunction<
        UnsignedLong Function(_CFTypeRef),
        int Function(_CFTypeRef)
      >('CFGetTypeID');

  static final stringTypeID = _lib
      .lookupFunction<UnsignedLong Function(), int Function()>(
        'CFStringGetTypeID',
      )();

  static final numberTypeID = _lib
      .lookupFunction<UnsignedLong Function(), int Function()>(
        'CFNumberGetTypeID',
      )();

  static final release = _lib
      .lookupFunction<Void Function(_CFTypeRef), void Function(_CFTypeRef)>(
        'CFRelease',
      );
}

abstract final class _IOKit {
  static final _lib = DynamicLibrary.open(
    '/System/Library/Frameworks/IOKit.framework/IOKit',
  );

  static final serviceMatching = _lib
      .lookupFunction<
        _CFTypeRef Function(Pointer<Utf8>),
        _CFTypeRef Function(Pointer<Utf8>)
      >('IOServiceMatching');

  static final getMatchingServices = _lib
      .lookupFunction<
        Int32 Function(Uint32, _CFTypeRef, Pointer<Uint32>),
        int Function(int, _CFTypeRef, Pointer<Uint32>)
      >('IOServiceGetMatchingServices');

  static final iteratorNext = _lib
      .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
        'IOIteratorNext',
      );

  static final objectRelease = _lib
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IOObjectRelease',
      );

  static final createProperty = _lib
      .lookupFunction<
        _CFTypeRef Function(Uint32, _CFTypeRef, _CFTypeRef, Uint32),
        _CFTypeRef Function(int, _CFTypeRef, _CFTypeRef, int)
      >('IORegistryEntryCreateCFProperty');

  static final searchProperty = _lib
      .lookupFunction<
        _CFTypeRef Function(
          Uint32,
          Pointer<Utf8>,
          _CFTypeRef,
          _CFTypeRef,
          Uint32,
        ),
        _CFTypeRef Function(int, Pointer<Utf8>, _CFTypeRef, _CFTypeRef, int)
      >('IORegistryEntrySearchCFProperty');
}

/// Returns every serial port IOKit knows about, USB or not.
List<IOKitSerialPort> listSerialPorts() => using((arena) {
  // The matching dictionary is consumed by IOServiceGetMatchingServices.
  final matching = _IOKit.serviceMatching(
    'IOSerialBSDClient'.toNativeUtf8(allocator: arena),
  );
  if (matching == nullptr) return const [];
  final iterator = arena<Uint32>();
  // 0 is kIOMainPortDefault.
  if (_IOKit.getMatchingServices(0, matching, iterator) != 0) return const [];

  final keys = _Keys(arena);
  final ports = <IOKitSerialPort>[];
  try {
    for (
      var service = _IOKit.iteratorNext(iterator.value);
      service != 0;
      service = _IOKit.iteratorNext(iterator.value)
    ) {
      try {
        final path = _string(
          _IOKit.createProperty(service, keys.callout, nullptr, 0),
        );
        if (path == null) continue;
        ports.add(
          IOKitSerialPort(
            calloutPath: path,
            vendorId: _int(keys.search(service, 'idVendor')),
            productId: _int(keys.search(service, 'idProduct')),
            serialNumber: keys.searchString(service, [
              'USB Serial Number',
              'kUSBSerialNumberString',
            ]),
            productName: keys.searchString(service, [
              'USB Product Name',
              'kUSBProductString',
            ]),
            vendorName: keys.searchString(service, [
              'USB Vendor Name',
              'kUSBVendorString',
            ]),
          ),
        );
      } finally {
        _IOKit.objectRelease(service);
      }
    }
  } finally {
    _IOKit.objectRelease(iterator.value);
    keys.release();
  }
  return ports;
});

/// CFString keys, created once per listing.
final class _Keys {
  _Keys(this._arena) : callout = _cfString('IOCalloutDevice', _arena);

  final Arena _arena;
  final _CFTypeRef callout;
  final _cache = <String, _CFTypeRef>{};
  late final _plane = 'IOService'.toNativeUtf8(allocator: _arena);

  /// Looks [key] up on [service] and then on its parents, which finds the
  /// USB device a serial port belongs to.
  _CFTypeRef search(int service, String key) => _IOKit.searchProperty(
    service,
    _plane,
    _cache.putIfAbsent(key, () => _cfString(key, _arena)),
    nullptr,
    _kIORegistryIterateRecursively | _kIORegistryIterateParents,
  );

  /// The first of [keys] that [search] finds as a string. Key names differ
  /// between the older and newer macOS USB stacks.
  String? searchString(int service, List<String> keys) {
    for (final key in keys) {
      if (_string(search(service, key)) case final value?) return value;
    }
    return null;
  }

  void release() {
    _CF.release(callout);
    _cache.values.forEach(_CF.release);
  }
}

_CFTypeRef _cfString(String value, Arena arena) => _CF.createString(
  nullptr,
  value.toNativeUtf8(allocator: arena),
  _kCFStringEncodingUTF8,
);

/// Converts and releases a CFString. Returns `null` for anything else.
String? _string(_CFTypeRef ref) {
  if (ref == nullptr) return null;
  try {
    if (_CF.getTypeID(ref) != _CF.stringTypeID) return null;
    return using((arena) {
      const size = 1024;
      final buffer = arena<Uint8>(size).cast<Utf8>();
      if (!_CF.getCString(ref, buffer, size, _kCFStringEncodingUTF8)) {
        return null;
      }
      final value = buffer.toDartString().trim();
      return value.isEmpty ? null : value;
    });
  } finally {
    _CF.release(ref);
  }
}

/// Converts and releases a CFNumber. Returns `null` for anything else.
int? _int(_CFTypeRef ref) {
  if (ref == nullptr) return null;
  try {
    if (_CF.getTypeID(ref) != _CF.numberTypeID) return null;
    return using((arena) {
      final value = arena<Int64>();
      return _CF.getNumber(ref, _kCFNumberSInt64Type, value.cast())
          ? value.value
          : null;
    });
  } finally {
    _CF.release(ref);
  }
}
