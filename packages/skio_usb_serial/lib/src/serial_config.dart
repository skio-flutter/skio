/// Parity checking mode.
enum Parity {
  /// No parity bit.
  none,

  /// Odd parity.
  odd,

  /// Even parity.
  even,

  /// Parity bit always 1. Not supported by Web Serial.
  mark,

  /// Parity bit always 0. Not supported by Web Serial.
  space,
}

/// Number of stop bits.
enum StopBits {
  /// One stop bit.
  one,

  /// One and a half stop bits. Not supported by Web Serial.
  onePointFive,

  /// Two stop bits.
  two,
}

/// Flow control mode.
enum FlowControl {
  /// No flow control.
  none,

  /// Hardware flow control using RTS/CTS.
  rtsCts,

  /// Hardware flow control using DTR/DSR. Not supported by Web Serial.
  dtrDsr,

  /// Software flow control using XON/XOFF. Not supported by Web Serial.
  xonXoff,
}

/// Line settings for opening a serial port. Defaults to 8N1 without flow
/// control.
final class SerialConfig {
  /// Creates a serial configuration.
  const SerialConfig({
    required this.baudRate,
    this.dataBits = 8,
    this.parity = Parity.none,
    this.stopBits = StopBits.one,
    this.flowControl = FlowControl.none,
    this.dtr,
    this.rts,
  });

  /// Bits per second, for example 9600 or 115200.
  final int baudRate;

  /// Data bits per character: 5, 6, 7 or 8.
  final int dataBits;

  /// Parity mode.
  final Parity parity;

  /// Stop bits.
  final StopBits stopBits;

  /// Flow control mode.
  final FlowControl flowControl;

  /// DTR state to set right after opening, or `null` to leave the driver
  /// default.
  ///
  /// Many ESP32 and Arduino boards reset when DTR/RTS toggle on open. Set both
  /// to `false` to avoid that on boards with an auto-reset circuit.
  final bool? dtr;

  /// RTS state to set right after opening, or `null` to leave the driver
  /// default. See [dtr].
  final bool? rts;

  /// Throws [ArgumentError] if a value is out of range.
  void validate() {
    if (baudRate <= 0) {
      throw ArgumentError.value(baudRate, 'baudRate', 'must be positive');
    }
    if (dataBits < 5 || dataBits > 8) {
      throw ArgumentError.value(dataBits, 'dataBits', 'must be 5 to 8');
    }
  }

  /// Returns a copy with the given fields replaced.
  SerialConfig copyWith({
    int? baudRate,
    int? dataBits,
    Parity? parity,
    StopBits? stopBits,
    FlowControl? flowControl,
    bool? dtr,
    bool? rts,
  }) => SerialConfig(
    baudRate: baudRate ?? this.baudRate,
    dataBits: dataBits ?? this.dataBits,
    parity: parity ?? this.parity,
    stopBits: stopBits ?? this.stopBits,
    flowControl: flowControl ?? this.flowControl,
    dtr: dtr ?? this.dtr,
    rts: rts ?? this.rts,
  );

  @override
  bool operator ==(Object other) =>
      other is SerialConfig &&
      other.baudRate == baudRate &&
      other.dataBits == dataBits &&
      other.parity == parity &&
      other.stopBits == stopBits &&
      other.flowControl == flowControl &&
      other.dtr == dtr &&
      other.rts == rts;

  @override
  int get hashCode =>
      Object.hash(baudRate, dataBits, parity, stopBits, flowControl, dtr, rts);

  @override
  String toString() {
    final p = switch (parity) {
      Parity.none => 'N',
      Parity.odd => 'O',
      Parity.even => 'E',
      Parity.mark => 'M',
      Parity.space => 'S',
    };
    final s = switch (stopBits) {
      StopBits.one => '1',
      StopBits.onePointFive => '1.5',
      StopBits.two => '2',
    };
    return 'SerialConfig($baudRate $dataBits$p$s, flow: ${flowControl.name})';
  }
}
