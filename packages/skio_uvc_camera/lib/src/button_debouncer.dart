import 'dart:async';

/// Turns raw hardware-button events into single presses.
///
/// Many UVC cameras report both press (state 1) and release (state 0), and
/// some bounce, reporting several presses per click. Only presses are passed
/// on, and presses within [window] of the previous one are dropped.
final class ButtonDebouncer {
  /// Creates a debouncer.
  ButtonDebouncer({
    this.window = const Duration(milliseconds: 700),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Minimum time between two reported presses.
  final Duration window;

  final DateTime Function() _clock;
  DateTime? _last;

  /// Returns whether a raw event with [state] counts as a new press.
  bool accept(int state) {
    if (state != 1) return false;
    final now = _clock();
    final last = _last;
    if (last != null && now.difference(last) < window) return false;
    _last = now;
    return true;
  }

  /// Applies [accept] to a stream of raw button states.
  Stream<void> bind(Stream<int> states) => states.where(accept).map((_) {});
}
