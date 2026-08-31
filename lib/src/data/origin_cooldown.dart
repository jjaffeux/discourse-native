import 'dart:async';

typedef OriginCooldownTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Uses monotonic deadlines so wall-clock changes cannot release or prolong
/// origin backpressure.
final class OriginCooldown {
  OriginCooldown({
    Duration Function()? clock,
    OriginCooldownTimerFactory? timerFactory,
  }) : _clock = clock ?? _createMonotonicClock(),
       _timerFactory = timerFactory ?? _createTimer;

  final Duration Function() _clock;
  final OriginCooldownTimerFactory _timerFactory;
  Duration? _until;
  Timer? _wake;

  Duration? get remaining {
    final until = _until;
    if (until == null) return null;
    final delay = until - _clock();
    if (delay > Duration.zero) return delay;
    cancel();
    return null;
  }

  /// Returns null when [delay] is zero and no longer cooldown is already held.
  Duration? extend(Duration delay, {required void Function() onExpired}) {
    assert(!delay.isNegative);
    final now = _clock();
    final proposedUntil = now + delay;
    final heldUntil = _until;
    if (heldUntil != null && heldUntil > now && proposedUntil <= heldUntil) {
      return heldUntil - now;
    }

    _wake?.cancel();
    _wake = null;
    if (delay <= Duration.zero) {
      _until = null;
      return null;
    }

    _until = proposedUntil;
    void wake() {
      _wake = null;
      final stillBlocked = remaining;
      if (stillBlocked != null) {
        _wake = _timerFactory(stillBlocked, wake);
        return;
      }
      onExpired();
    }

    _wake = _timerFactory(delay, wake);
    return delay;
  }

  void cancel() {
    _until = null;
    _wake?.cancel();
    _wake = null;
  }
}

Duration Function() _createMonotonicClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

Timer _createTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);
