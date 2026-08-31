import 'dart:async';

final class ManualScheduler {
  Duration _elapsed = Duration.zero;
  int _nextSequence = 0;
  final List<_ManualTimer> _timers = [];

  Duration now() => _elapsed;

  Timer createTimer(Duration delay, void Function() callback) {
    final effectiveDelay = delay.isNegative ? Duration.zero : delay;
    final timer = _ManualTimer(
      callback,
      deadline: _elapsed + effectiveDelay,
      sequence: _nextSequence++,
    );
    _timers.add(timer);
    return timer;
  }

  int get activeTimerCount => _timers.where((timer) => timer.isActive).length;

  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    final target = _elapsed + duration;
    while (true) {
      _ManualTimer? next;
      for (final timer in _timers) {
        if (!timer.isActive || timer.deadline > target) continue;
        if (next == null ||
            timer.deadline < next.deadline ||
            (timer.deadline == next.deadline &&
                timer.sequence < next.sequence)) {
          next = timer;
        }
      }
      if (next == null) break;

      _elapsed = next.deadline;
      next.fire();
    }
    _elapsed = target;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(
    this._callback, {
    required this.deadline,
    required this.sequence,
  });

  final Duration deadline;
  final int sequence;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}
