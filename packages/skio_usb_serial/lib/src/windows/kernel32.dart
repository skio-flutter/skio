// FFI bindings to the Win32 communications API (kernel32) and the registry
// (advapi32). Kept in step with skio_uart's copy.
//
// Struct layouts and values are from the Windows SDK headers (winbase.h,
// minwinbase.h, winerror.h, winnt.h, winreg.h).
// Internal; names follow the C headers.
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// CreateFileW
const GENERIC_READ = 0x80000000;
const GENERIC_WRITE = 0x40000000;
const OPEN_EXISTING = 3;
const FILE_FLAG_OVERLAPPED = 0x40000000;
const INVALID_HANDLE_VALUE = -1;

// Wait results
const WAIT_OBJECT_0 = 0;
const WAIT_TIMEOUT = 0x102;
const INFINITE = 0xFFFFFFFF;
const MAXDWORD = 0xFFFFFFFF;

// Error codes
const ERROR_FILE_NOT_FOUND = 2;
const ERROR_PATH_NOT_FOUND = 3;
const ERROR_ACCESS_DENIED = 5;
const ERROR_SHARING_VIOLATION = 32;
const ERROR_NO_MORE_ITEMS = 259;
const ERROR_INSUFFICIENT_BUFFER = 122;
const ERROR_OPERATION_ABORTED = 995;
const ERROR_IO_PENDING = 997;

// DCB values
const NOPARITY = 0;
const ODDPARITY = 1;
const EVENPARITY = 2;
const MARKPARITY = 3;
const SPACEPARITY = 4;
const ONESTOPBIT = 0;
const ONE5STOPBITS = 1;
const TWOSTOPBITS = 2;
const DTR_CONTROL_DISABLE = 0;
const DTR_CONTROL_ENABLE = 1;
const DTR_CONTROL_HANDSHAKE = 2;
const RTS_CONTROL_DISABLE = 0;
const RTS_CONTROL_ENABLE = 1;
const RTS_CONTROL_HANDSHAKE = 2;

// EscapeCommFunction
const SETRTS = 3;
const CLRRTS = 4;
const SETDTR = 5;
const CLRDTR = 6;

// PurgeComm
const PURGE_TXCLEAR = 0x4;
const PURGE_RXCLEAR = 0x8;

// Registry
const KEY_READ = 0x20019;
const REG_SZ = 1;

/// `DCB`. The bit fields after `BaudRate` are packed into [flags]; see
/// `encodeDcbFlags`.
final class DCB extends Struct {
  @Uint32()
  external int DCBlength;
  @Uint32()
  external int BaudRate;
  @Uint32()
  external int flags;
  @Uint16()
  external int wReserved;
  @Uint16()
  external int XonLim;
  @Uint16()
  external int XoffLim;
  @Uint8()
  external int ByteSize;
  @Uint8()
  external int Parity;
  @Uint8()
  external int StopBits;
  @Uint8()
  external int XonChar;
  @Uint8()
  external int XoffChar;
  @Uint8()
  external int ErrorChar;
  @Uint8()
  external int EofChar;
  @Uint8()
  external int EvtChar;
  @Uint16()
  external int wReserved1;
}

/// `COMMTIMEOUTS`.
final class COMMTIMEOUTS extends Struct {
  @Uint32()
  external int ReadIntervalTimeout;
  @Uint32()
  external int ReadTotalTimeoutMultiplier;
  @Uint32()
  external int ReadTotalTimeoutConstant;
  @Uint32()
  external int WriteTotalTimeoutMultiplier;
  @Uint32()
  external int WriteTotalTimeoutConstant;
}

/// `OVERLAPPED`, with the offset union as its two DWORDs.
final class OVERLAPPED extends Struct {
  @IntPtr()
  external int Internal;
  @IntPtr()
  external int InternalHigh;
  @Uint32()
  external int Offset;
  @Uint32()
  external int OffsetHigh;
  @IntPtr()
  external int hEvent;
}

/// kernel32 and advapi32 functions. Look-ups are lazy and shared per isolate.
///
/// Calls whose failure is checked with [GetLastError] are leaf calls, so the
/// Dart VM runs nothing between them that could overwrite the error. Calls
/// that wait are not, so other isolates keep running.
abstract final class Win32 {
  static final _k = DynamicLibrary.open('kernel32.dll');
  static final _a = DynamicLibrary.open('advapi32.dll');

  static final CreateFileW = _k
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW', isLeaf: true);

  static final CloseHandle = _k
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle',
        isLeaf: true,
      );

  static final GetLastError = _k
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetLastError',
        isLeaf: true,
      );

  static final GetCommState = _k
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<DCB>),
        int Function(int, Pointer<DCB>)
      >('GetCommState', isLeaf: true);

  static final SetCommState = _k
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<DCB>),
        int Function(int, Pointer<DCB>)
      >('SetCommState', isLeaf: true);

  static final SetCommTimeouts = _k
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<COMMTIMEOUTS>),
        int Function(int, Pointer<COMMTIMEOUTS>)
      >('SetCommTimeouts', isLeaf: true);

  static final SetupComm = _k
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Uint32),
        int Function(int, int, int)
      >('SetupComm', isLeaf: true);

  static final ReadFile = _k
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<OVERLAPPED>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<OVERLAPPED>,
        )
      >('ReadFile', isLeaf: true);

  static final WriteFile = _k
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<OVERLAPPED>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<OVERLAPPED>,
        )
      >('WriteFile', isLeaf: true);

  static final GetOverlappedResult = _k
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<OVERLAPPED>, Pointer<Uint32>, Int32),
        int Function(int, Pointer<OVERLAPPED>, Pointer<Uint32>, int)
      >('GetOverlappedResult', isLeaf: true);

  static final CancelIoEx = _k
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<OVERLAPPED>),
        int Function(int, Pointer<OVERLAPPED>)
      >('CancelIoEx', isLeaf: true);

  static final CreateEventW = _k
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, int, Pointer<Utf16>)
      >('CreateEventW', isLeaf: true);

  static final SetEvent = _k
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetEvent',
        isLeaf: true,
      );

  static final ResetEvent = _k
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'ResetEvent',
        isLeaf: true,
      );

  /// Not a leaf call: it may wait.
  static final WaitForSingleObject = _k
      .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject',
      );

  /// Not a leaf call: it may wait.
  static final WaitForMultipleObjects = _k
      .lookupFunction<
        Uint32 Function(Uint32, Pointer<IntPtr>, Int32, Uint32),
        int Function(int, Pointer<IntPtr>, int, int)
      >('WaitForMultipleObjects');

  static final EscapeCommFunction = _k
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'EscapeCommFunction',
        isLeaf: true,
      );

  static final PurgeComm = _k
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'PurgeComm',
        isLeaf: true,
      );

  static final RegQueryValueExW = _a
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint8>,
          Pointer<Uint32>,
        )
      >('RegQueryValueExW');

  static final RegCloseKey = _a
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');
}

/// A Win32 error captured from a failed call, for exception causes.
final class Win32Error {
  /// Captures [GetLastError] for [call]. Create it right after the call.
  Win32Error(this.call) : code = Win32.GetLastError();

  /// The failing function, for example `CreateFileW`.
  final String call;

  /// The Win32 error code.
  final int code;

  @override
  String toString() => '$call failed with Windows error $code';
}
