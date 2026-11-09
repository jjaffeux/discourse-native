import 'dart:async';

import 'elapsed_time.dart';

/// The wait before what a reader has on screen counts as read.
///
/// A dwell spends only time its surface is active. [sync] banks what is left
/// when the surface goes away and spends the rest when it returns, so callers
/// call it whenever an input of `isActive` changes.
///
/// How a new reading meets a dwell under way is the caller's choice, through
/// [restart] or [startIfIdle], and so is whether leaving the foreground credits
/// at once. Chat and topics answer both differently on purpose.
final class ReadDwell {
  ReadDwell({
    required this._isActive,
    required this._onCredit,
    this._clock = DateTime.now,
    this._timerFactory = Timer.new,
  });

  /// Matches Discourse's `READ_INTERVAL_MS`.
  static const interval = Duration(milliseconds: 500);

  final bool Function() _isActive;
  final void Function() _onCredit;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timerFactory;

  /// What the dwell still has to spend. Null when no dwell is under way.
  Duration? _remaining;

  /// Present only while a timer is spending [_remaining].
  ({Timer timer, DateTime startedAt})? _running;

  /// Starts a full dwell, abandoning any under way.
  void restart() {
    _stopTimer();
    _remaining = interval;
    sync();
  }

  /// Starts a full dwell unless one is under way, which then keeps its time.
  void startIfIdle() {
    if (_remaining == null) restart();
  }

  /// Credits now unless a dwell is under way, which will credit by itself.
  void creditIfIdle() {
    if (_remaining == null) _settle();
  }

  /// Brings the timer in line with `isActive`.
  void sync() {
    final remaining = _remaining;
    if (remaining == null) return;
    final running = _running;
    final active = _isActive();
    if (active && running == null) {
      _running = (
        startedAt: _clock(),
        timer: _timerFactory(remaining, _settle),
      );
    } else if (!active && running != null) {
      _stopTimer();
      final elapsed = elapsedSince(running.startedAt, now: _clock());
      _remaining = elapsed < remaining ? remaining - elapsed : Duration.zero;
    }
  }

  void cancel() {
    _stopTimer();
    _remaining = null;
  }

  /// An inactive reader keeps the credit owed as a full dwell, because time
  /// away says nothing about what will be on screen when they come back.
  void _settle() {
    _stopTimer();
    if (_isActive()) {
      _remaining = null;
      _onCredit();
    } else {
      _remaining = interval;
    }
  }

  void _stopTimer() {
    _running?.timer.cancel();
    _running = null;
  }
}
