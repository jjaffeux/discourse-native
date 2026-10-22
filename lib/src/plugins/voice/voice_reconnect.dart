import 'dart:async';

enum VoiceMediaConnectionState { connected, reconnecting, failed }

typedef VoiceReconnectAttempt = Future<void> Function();
typedef VoiceReconnectTimerFactory =
    Timer Function(Duration delay, void Function() callback);

Timer _defaultReconnectTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// Failed attempts are deliberately absorbed: exhaustion or a terminal refusal
/// publishes a failed state with its cause, not an asynchronous error. Errors
/// from the timer or state callback are still returned to the caller.
final class VoiceReconnectCoordinator {
  VoiceReconnectCoordinator({
    required this.attempt,
    required this.onStateChanged,
    this.shouldRetry,
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

  final VoiceReconnectAttempt attempt;
  final void Function(VoiceMediaConnectionState state) onStateChanged;

  /// Stops the ladder for a terminal refusal. Other errors use every rung.
  final bool Function(Object error)? shouldRetry;
  final VoiceReconnectTimerFactory timerFactory;
  final List<Duration> _schedule;

  VoiceMediaConnectionState _connectionState =
      VoiceMediaConnectionState.connected;
  Future<void>? _active;
  Timer? _backoffTimer;
  Completer<void>? _backoff;
  bool _cancelled = false;
  Object? _failure;

  VoiceMediaConnectionState get connectionState => _connectionState;
  bool get cancelled => _cancelled;

  /// The last attempt's cause, published with the failed state rather than
  /// thrown from [reconnect]. A new ladder or cancellation clears it.
  Object? get failure =>
      !_cancelled && _connectionState == VoiceMediaConnectionState.failed
      ? _failure
      : null;

  Future<void> reconnect() {
    if (_cancelled) return Future<void>.value();
    final active = _active;
    if (active != null) return active;
    final completion = Completer<void>();
    _active = completion.future;
    completion.complete(_runAndClear());
    return completion.future;
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _failure = null;
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
    _failure = null;
    _setConnectionState(VoiceMediaConnectionState.reconnecting);
    for (var index = 0; index < _schedule.length; index++) {
      final delay = _schedule[index];
      if (!await _wait(delay) || _cancelled) return;
      try {
        await attempt();
      } catch (error) {
        if (_cancelled) return;
        _failure = error;
        if (shouldRetry?.call(error) == false) {
          _setConnectionState(VoiceMediaConnectionState.failed);
          return;
        }
        continue;
      }
      if (_cancelled) return;
      _failure = null;
      _setConnectionState(VoiceMediaConnectionState.connected);
      return;
    }
    if (!_cancelled) {
      _setConnectionState(VoiceMediaConnectionState.failed);
    }
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

  void _setConnectionState(VoiceMediaConnectionState state) {
    if (_cancelled || _connectionState == state) return;
    _connectionState = state;
    onStateChanged(state);
  }
}
