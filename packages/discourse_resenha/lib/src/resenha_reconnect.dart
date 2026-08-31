import 'dart:async';

enum ResenhaMediaConnectionState { connected, reconnecting, failed }

typedef ResenhaReconnectAttempt = Future<void> Function();
typedef ResenhaReconnectAttemptStarted =
    void Function(int attemptNumber, Duration delay);
typedef ResenhaReconnectAttemptFailed =
    void Function(int attemptNumber, Object error, StackTrace stackTrace);
typedef ResenhaReconnectExhausted = void Function(int attemptCount);
typedef ResenhaReconnectTimerFactory =
    Timer Function(Duration delay, void Function() callback);

Timer _defaultReconnectTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// Failed attempts are deliberately absorbed: exhausting the schedule is a
/// connection-state transition, not an asynchronous error. Unexpected errors
/// from the timer or state callback are still returned to the caller.
final class ResenhaReconnectCoordinator {
  ResenhaReconnectCoordinator({
    required this.attempt,
    required this.onStateChanged,
    this.onAttemptStarted,
    this.onAttemptFailed,
    this.onExhausted,
    List<Duration> schedule = const [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    this.timerFactory = _defaultReconnectTimer,
  }) : _schedule = List.unmodifiable(schedule) {
    if (_schedule.isEmpty) {
      throw ArgumentError.value(schedule, 'schedule', 'Must not be empty.');
    }
    if (_schedule.any((delay) => delay.isNegative)) {
      throw ArgumentError.value(
        schedule,
        'schedule',
        'Delays must not be negative.',
      );
    }
  }

  final ResenhaReconnectAttempt attempt;
  final void Function(ResenhaMediaConnectionState state) onStateChanged;
  final ResenhaReconnectAttemptStarted? onAttemptStarted;
  final ResenhaReconnectAttemptFailed? onAttemptFailed;
  final ResenhaReconnectExhausted? onExhausted;
  final ResenhaReconnectTimerFactory timerFactory;
  final List<Duration> _schedule;

  ResenhaMediaConnectionState _connectionState =
      ResenhaMediaConnectionState.connected;
  Future<void>? _active;
  Timer? _backoffTimer;
  Completer<void>? _backoff;
  bool _cancelled = false;

  ResenhaMediaConnectionState get connectionState => _connectionState;
  bool get cancelled => _cancelled;

  Future<void> reconnect() {
    if (_cancelled) return Future<void>.value();
    final active = _active;
    if (active != null) return active;
    return _active = _runAndClear();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    final backoff = _backoff;
    _backoff = null;
    if (backoff != null && !backoff.isCompleted) backoff.complete();
  }

  Future<void> _runAndClear() async {
    try {
      await _run();
    } finally {
      _active = null;
    }
  }

  Future<void> _run() async {
    _setConnectionState(ResenhaMediaConnectionState.reconnecting);
    for (var index = 0; index < _schedule.length; index++) {
      final attemptNumber = index + 1;
      final delay = _schedule[index];
      if (!await _wait(delay) || _cancelled) return;
      _notifyAttemptStarted(attemptNumber, delay);
      try {
        await attempt();
      } catch (error, stackTrace) {
        _notifyAttemptFailed(attemptNumber, error, stackTrace);
        continue;
      }
      if (_cancelled) return;
      _setConnectionState(ResenhaMediaConnectionState.connected);
      return;
    }
    if (!_cancelled) {
      _notifyExhausted(_schedule.length);
      _setConnectionState(ResenhaMediaConnectionState.failed);
    }
  }

  void _notifyAttemptStarted(int attemptNumber, Duration delay) {
    try {
      onAttemptStarted?.call(attemptNumber, delay);
    } catch (_) {}
  }

  void _notifyAttemptFailed(
    int attemptNumber,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      onAttemptFailed?.call(attemptNumber, error, stackTrace);
    } catch (_) {}
  }

  void _notifyExhausted(int attemptCount) {
    try {
      onExhausted?.call(attemptCount);
    } catch (_) {}
  }

  Future<bool> _wait(Duration delay) async {
    if (_cancelled) return false;
    if (delay == Duration.zero) return true;

    final backoff = Completer<void>();
    _backoff = backoff;
    final timer = timerFactory(delay, () {
      if (identical(_backoff, backoff)) {
        _backoffTimer = null;
        _backoff = null;
      }
      if (!backoff.isCompleted) backoff.complete();
    });
    if (backoff.isCompleted) {
      timer.cancel();
    } else {
      _backoffTimer = timer;
    }
    await backoff.future;
    if (identical(_backoffTimer, timer)) _backoffTimer = null;
    if (identical(_backoff, backoff)) _backoff = null;
    return !_cancelled;
  }

  void _setConnectionState(ResenhaMediaConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    onStateChanged(state);
  }
}
