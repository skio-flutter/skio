// Lists COM ports through the SetupAPI (setupapi.dll) and the configuration
// manager (cfgmgr32.dll), with the USB details of each port's device.
//
// Struct layouts and values are from the Windows SDK headers (setupapi.h,
// cfgmgr32.h, devguid.h).
// Internal; names follow the C headers.
// ignore_for_file: camel_case_types, constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'device_id.dart';
import 'kernel32.dart';

const DIGCF_PRESENT = 0x2;
const SPDRP_FRIENDLYNAME = 0xC;
const DICS_FLAG_GLOBAL = 1;
const DIREG_DEV = 1;
const CR_SUCCESS = 0;

/// `GUID`.
final class GUID extends Struct {
  @Uint32()
  external int Data1;
  @Uint16()
  external int Data2;
  @Uint16()
  external int Data3;
  @Array(8)
  external Array<Uint8> Data4;
}

/// `SP_DEVINFO_DATA`.
final class SP_DEVINFO_DATA extends Struct {
  @Uint32()
  external int cbSize;
  external GUID ClassGuid;
  @Uint32()
  external int DevInst;
  @IntPtr()
  external int Reserved;
}

abstract final class SetupApi {
  static final _s = DynamicLibrary.open('setupapi.dll');
  static final _c = DynamicLibrary.open('cfgmgr32.dll');

  static final SetupDiGetClassDevsW = _s
      .lookupFunction<
        IntPtr Function(Pointer<GUID>, Pointer<Utf16>, IntPtr, Uint32),
        int Function(Pointer<GUID>, Pointer<Utf16>, int, int)
      >('SetupDiGetClassDevsW');

  static final SetupDiEnumDeviceInfo = _s
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<SP_DEVINFO_DATA>),
        int Function(int, int, Pointer<SP_DEVINFO_DATA>)
      >('SetupDiEnumDeviceInfo');

  static final SetupDiGetDeviceInstanceIdW = _s
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<SP_DEVINFO_DATA>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<SP_DEVINFO_DATA>,
          Pointer<Utf16>,
          int,
          Pointer<Uint32>,
        )
      >('SetupDiGetDeviceInstanceIdW');

  static final SetupDiGetDeviceRegistryPropertyW = _s
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<SP_DEVINFO_DATA>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<SP_DEVINFO_DATA>,
          int,
          Pointer<Uint32>,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
        )
      >('SetupDiGetDeviceRegistryPropertyW');

  static final SetupDiOpenDevRegKey = _s
      .lookupFunction<
        IntPtr Function(
          IntPtr,
          Pointer<SP_DEVINFO_DATA>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
        ),
        int Function(int, Pointer<SP_DEVINFO_DATA>, int, int, int, int)
      >('SetupDiOpenDevRegKey');

  static final SetupDiDestroyDeviceInfoList = _s
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetupDiDestroyDeviceInfoList',
      );

  static final CM_Get_Parent = _c
      .lookupFunction<
        Uint32 Function(Pointer<Uint32>, Uint32, Uint32),
        int Function(Pointer<Uint32>, int, int)
      >('CM_Get_Parent');

  static final CM_Get_Device_IDW = _c
      .lookupFunction<
        Uint32 Function(Uint32, Pointer<Utf16>, Uint32, Uint32),
        int Function(int, Pointer<Utf16>, int, int)
      >('CM_Get_Device_IDW');
}

/// A COM port as the SetupAPI reports it.
final class WindowsComPort {
  /// Creates a port description.
  const WindowsComPort({
    required this.port,
    required this.instanceId,
    this.friendlyName,
    this.usb,
  });

  /// The port name, for example `COM3`.
  final String port;

  /// The device instance ID, for example `USB\VID_1A86&PID_7523\5&2B5B5E1&0&2`.
  final String instanceId;

  /// What Device Manager shows, for example `USB-SERIAL CH340 (COM3)`.
  final String? friendlyName;

  /// USB details, or `null` when the port isn't on USB.
  final UsbIds? usb;
}

/// The device setup classes COM ports appear under: Ports, and Modem for
/// USB modems and some CDC-ACM boards.
const _classes = [
  (
    0x4D36E978,
    0xE325,
    0x11CE,
    [0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18],
  ),
  (
    0x4D36E96D,
    0xE325,
    0x11CE,
    [0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18],
  ),
];

/// Returns every present COM port Windows has a driver for, USB or not.
List<WindowsComPort> listComPorts() => using((arena) {
  final ports = <WindowsComPort>[];
  final seen = <String>{};
  final guid = arena<GUID>();
  final info = arena<SP_DEVINFO_DATA>();
  const chars = 512;
  final text = arena<Uint16>(chars).cast<Utf16>();
  final bytes = arena<Uint8>(chars * 2 + 2);
  final size = arena<Uint32>();
  final type = arena<Uint32>();
  final parent = arena<Uint32>();
  final portName = 'PortName'.toNativeUtf16(allocator: arena);

  for (final (d1, d2, d3, d4) in _classes) {
    guid.ref
      ..Data1 = d1
      ..Data2 = d2
      ..Data3 = d3;
    for (var i = 0; i < 8; i++) {
      guid.ref.Data4[i] = d4[i];
    }
    final set = SetupApi.SetupDiGetClassDevsW(guid, nullptr, 0, DIGCF_PRESENT);
    if (set == INVALID_HANDLE_VALUE) continue;
    try {
      for (var index = 0; ; index++) {
        info.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
        if (SetupApi.SetupDiEnumDeviceInfo(set, index, info) == 0) break;

        // The port name lives in the device's registry key.
        final key = SetupApi.SetupDiOpenDevRegKey(
          set,
          info,
          DICS_FLAG_GLOBAL,
          0,
          DIREG_DEV,
          KEY_READ,
        );
        if (key == INVALID_HANDLE_VALUE) continue;
        String? port;
        try {
          size.value = chars * 2;
          if (Win32.RegQueryValueExW(
                    key,
                    portName,
                    nullptr,
                    type,
                    bytes,
                    size,
                  ) ==
                  0 &&
              type.value == REG_SZ) {
            port = _utf16(bytes, size.value);
          }
        } finally {
          Win32.RegCloseKey(key);
        }
        // Parallel ports (LPT1) share the Ports class.
        if (port == null || !port.toUpperCase().startsWith('COM')) continue;
        if (!seen.add(port)) continue;

        if (SetupApi.SetupDiGetDeviceInstanceIdW(
              set,
              info,
              text,
              chars,
              nullptr,
            ) ==
            0) {
          continue;
        }
        final instanceId = text.toDartString();

        String? friendlyName;
        size.value = 0;
        if (SetupApi.SetupDiGetDeviceRegistryPropertyW(
              set,
              info,
              SPDRP_FRIENDLYNAME,
              type,
              bytes,
              chars * 2,
              size,
            ) !=
            0) {
          friendlyName = _utf16(bytes, size.value);
        }

        var usb = parseUsbInstanceId(instanceId);
        // A composite device's interface carries no serial number; the
        // parent USB device does.
        if (usb != null &&
            usb.serialNumber == null &&
            isInterfaceId(instanceId)) {
          if (SetupApi.CM_Get_Parent(parent, info.ref.DevInst, 0) ==
                  CR_SUCCESS &&
              SetupApi.CM_Get_Device_IDW(parent.value, text, chars, 0) ==
                  CR_SUCCESS) {
            final fromParent = parseUsbInstanceId(text.toDartString());
            if (fromParent?.serialNumber case final serial?) {
              usb = (
                vendorId: usb.vendorId,
                productId: usb.productId,
                serialNumber: serial,
              );
            }
          }
        }
        ports.add(
          WindowsComPort(
            port: port,
            instanceId: instanceId,
            friendlyName: friendlyName,
            usb: usb,
          ),
        );
      }
    } finally {
      SetupApi.SetupDiDestroyDeviceInfoList(set);
    }
  }
  return ports;
});

/// Reads a REG_SZ value of [byteLength] bytes, with or without its NUL.
String? _utf16(Pointer<Uint8> bytes, int byteLength) {
  final units = bytes.cast<Uint16>().asTypedList(byteLength ~/ 2);
  final end = units.indexOf(0);
  final value = String.fromCharCodes(end == -1 ? units : units.sublist(0, end))
      .trim();
  return value.isEmpty ? null : value;
}
