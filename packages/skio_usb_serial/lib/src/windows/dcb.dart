import 'package:skio_core/skio_core.dart';

/// The `DCB` fields a [SerialConfig] sets, as plain values so they can be
/// tested on any system.
typedef DcbFields = ({int flags, int byteSize, int parity, int stopBits});

// Bit positions in DCB's packed bit fields (winbase.h).
const _fBinary = 1 << 0;
const _fParity = 1 << 1;
const _fOutxCtsFlow = 1 << 2;
const _fOutxDsrFlow = 1 << 3;
const _fDtrControlShift = 4;
const _fOutX = 1 << 8;
const _fInX = 1 << 9;
const _fRtsControlShift = 12;
const _controlMask = 0x3;

/// Builds the DCB fields for [config].
///
/// [previousFlags] is the port's current bit field. When [SerialConfig.dtr]
/// or [SerialConfig.rts] is `null` and no handshake uses the line, the line
/// keeps its current state, as `null` promises. Every other bit is replaced.
DcbFields encodeDcb(SerialConfig config, int previousFlags) {
  final flow = config.flowControl;

  int line(bool? on, int shift, {required bool handshake}) {
    if (handshake) return 2; // *_CONTROL_HANDSHAKE
    if (on != null) return on ? 1 : 0; // ENABLE / DISABLE
    final current = (previousFlags >> shift) & _controlMask;
    // Keep on/off, but drop a handshake or toggle mode left by another app.
    return current <= 1 ? current : 1;
  }

  var flags = _fBinary;
  if (config.parity != Parity.none) flags |= _fParity;
  if (flow == FlowControl.rtsCts) flags |= _fOutxCtsFlow;
  if (flow == FlowControl.dtrDsr) flags |= _fOutxDsrFlow;
  if (flow == FlowControl.xonXoff) flags |= _fOutX | _fInX;
  flags |=
      line(
        config.dtr,
        _fDtrControlShift,
        handshake: flow == FlowControl.dtrDsr,
      ) <<
      _fDtrControlShift;
  flags |=
      line(
        config.rts,
        _fRtsControlShift,
        handshake: flow == FlowControl.rtsCts,
      ) <<
      _fRtsControlShift;

  return (
    flags: flags,
    byteSize: config.dataBits,
    parity: switch (config.parity) {
      Parity.none => 0,
      Parity.odd => 1,
      Parity.even => 2,
      Parity.mark => 3,
      Parity.space => 4,
    },
    stopBits: switch (config.stopBits) {
      StopBits.one => 0,
      StopBits.onePointFive => 1,
      StopBits.two => 2,
    },
  );
}

/// Turns `COM3`, `com3` or `\\.\COM3` into `COM3`. Other device names, such
/// as com0com's `CNCA0`, are kept as they are. Returns `null` for anything
/// that isn't a device name.
String? normalizeComPort(String path) {
  var name = path.trim();
  if (name.startsWith(r'\\.\')) name = name.substring(4);
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(name)) return null;
  return RegExp(r'^com\d+$', caseSensitive: false).hasMatch(name)
      ? name.toUpperCase()
      : name;
}
