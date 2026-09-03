import 'dart:async';

import 'voice_models.dart';
import 'voice_settings.dart';

/// The site's idle ladder as durations. A zero stage is disabled.
typedef VoiceIdleThresholds = ({
  Duration idle,
  Duration afk,
  Duration disconnect,
});

typedef VoiceIdleThresholdsLookup =
    VoiceIdleThresholds Function(String siteUrl);
typedef VoiceIdleTimerFactory =
    Timer Function(Duration delay, void Function() callback);

Timer _defaultIdleTimer(Duration delay, void Function() callback) =>
    Timer(delay, callback);

/// Site settings express the ladder in minutes; a later stage set at or below
/// an earlier one disables the earlier stage rather than firing out of order.
/// Mirrors the web client's `idleThresholds`.
VoiceIdleThresholds voiceIdleThresholds(VoiceClientConfig config) {
  var idle = Duration(minutes: config.idleThresholdMinutes);
  var afk = Duration(minutes: config.afkAutoMuteThresholdMinutes);
  final disconnect = Duration(minutes: config.afkDisconnectThresholdMinutes);

  if (afk > Duration.zero && idle > Duration.zero && idle >= afk) {
    idle = Duration.zero;
  }
  if (disconnect > Duration.zero && afk > Duration.zero && afk >= disconnect) {
    afk = Duration.zero;
  }
  if (disconnect > Duration.zero &&
      idle > Duration.zero &&
      idle >= disconnect) {
    idle = Duration.zero;
  }
  return (idle: idle, afk: afk, disconnect: disconnect);
}

/// Decides when a participant in a call has gone idle, away, or should be
/// disconnected, from the time since they last did something: interacted
/// with the app, brought it to the foreground, or spoke. Being in the
/// background is not by itself being away — a phone in a pocket during a
/// call is the ordinary case — so the ladder only climbs with elapsed
/// silence, exactly as the web client's `IdleTracker` does with input events.
///
/// Pure Dart: the clock and timers are injectable, so it needs no binding
/// and can be driven deterministically.
final class VoiceIdleTracker {
  VoiceIdleTracker({
    required this.onStateChanged,
    required this.onAutoMute,
    required this.onDisconnect,
    required this._thresholds,
    Duration Function()? clock,
    this._timerFactory = _defaultIdleTimer,
    this.checkInterval = const Duration(seconds: 30),
    this.activityThrottle = const Duration(seconds: 10),
  }) : _clock = clock ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final VoiceIdleThresholds Function() _thresholds;

  /// Called with the new state whenever it changes; [wasAutoMuted] is true on
  /// the return to `active` after an automatic mute, so the caller can tell
  /// the user why their microphone is off.
  final void Function(VoiceIdleState state, {required bool wasAutoMuted})
  onStateChanged;

  /// The away threshold passed: the caller mutes the microphone. The state
  /// change to `afk` arrives through [onStateChanged] first.
  final void Function() onAutoMute;

  /// The disconnect threshold passed: the caller leaves the call. The
  /// tracker has already stopped itself when this is called.
  final void Function() onDisconnect;

  final Duration Function() _clock;
  final VoiceIdleTimerFactory _timerFactory;
  final Duration checkInterval;
  final Duration activityThrottle;

  Duration _lastActivityAt = Duration.zero;
  Duration? _lastActivityNotifiedAt;
  Duration? _lastVoiceActivityAt;
  Timer? _check;
  bool _running = false;
  VoiceIdleState _state = VoiceIdleState.active;

  /// Whether the last mute was this tracker's doing. Cleared by the caller
  /// when the user unmutes themselves, so a deliberate mute followed by a
  /// return to activity does not read as an automatic one.
  bool wasAutoMuted = false;

  VoiceIdleState get state => _state;
  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    _lastActivityAt = _clock();
    _lastActivityNotifiedAt = null;
    _lastVoiceActivityAt = null;
    wasAutoMuted = false;
    _state = VoiceIdleState.active;
    _schedule();
  }

  void stop() {
    _check?.cancel();
    _check = null;
    _running = false;
    wasAutoMuted = false;
    _state = VoiceIdleState.active;
  }

  /// The user did something. Throttled so a burst of interaction produces
  /// one state change, not one per event.
  void recordActivity() {
    if (!_running) return;
    final now = _clock();
    _lastActivityAt = now;
    final notified = _lastActivityNotifiedAt;
    if (notified != null && now - notified < activityThrottle) return;
    _lastActivityNotifiedAt = now;
    _becomeActive();
  }

  /// The user spoke. Same effect as any other activity, throttled separately
  /// because speech is sampled many times a second.
  void recordVoiceActivity() {
    if (!_running) return;
    final now = _clock();
    final last = _lastVoiceActivityAt;
    if (last != null && now - last < activityThrottle) return;
    _lastVoiceActivityAt = now;
    recordActivity();
  }

  void _becomeActive() {
    if (_state == VoiceIdleState.active) return;
    final mutedByTracker = wasAutoMuted;
    _state = VoiceIdleState.active;
    onStateChanged(VoiceIdleState.active, wasAutoMuted: mutedByTracker);
  }

  void _schedule() {
    _check?.cancel();
    if (!_running) return;
    _check = _timerFactory(checkInterval, () {
      _check = null;
      if (!_running) return;
      _evaluate();
      _schedule();
    });
  }

  void _evaluate() {
    final thresholds = _thresholds();
    final elapsed = _clock() - _lastActivityAt;

    if (thresholds.disconnect > Duration.zero &&
        elapsed >= thresholds.disconnect) {
      // The ladder ends here: the caller leaves the call, and a tracker that
      // kept ticking would ask it to leave again on every check.
      stop();
      onDisconnect();
      return;
    }

    if (thresholds.afk > Duration.zero && elapsed >= thresholds.afk) {
      if (_state != VoiceIdleState.afk) {
        _state = VoiceIdleState.afk;
        wasAutoMuted = true;
        onStateChanged(VoiceIdleState.afk, wasAutoMuted: false);
        onAutoMute();
      }
      return;
    }

    if (thresholds.idle > Duration.zero && elapsed >= thresholds.idle) {
      if (_state != VoiceIdleState.idle) {
        _state = VoiceIdleState.idle;
        onStateChanged(VoiceIdleState.idle, wasAutoMuted: false);
      }
      return;
    }

    _becomeActive();
  }
}
