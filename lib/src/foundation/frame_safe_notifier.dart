import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// A notifier that coalesces changes raised during layout until the frame ends.
abstract class FrameSafeNotifier extends ChangeNotifier {
  bool _disposed = false;
  bool _scheduled = false;

  @protected
  bool get isDisposed => _disposed;

  @protected
  void notifySafely() {
    if (_disposed) return;

    final scheduler = _schedulerOrNull;
    if (scheduler != null &&
        scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_scheduled) return;
      _scheduled = true;
      scheduler.addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  /// The scheduler binding, or null in a pure-Dart context (VM tests, tools,
  /// secondary isolates). With no frames to coalesce against, notifying
  /// synchronously is the frame-safe behavior.
  ///
  /// `SchedulerBinding.instance` reports an absent binding differently per
  /// build mode: `BindingBase.checkInstance` raises its explanatory
  /// [FlutterError] from inside an `assert`, so a release build falls through
  /// to `instance!` and raises [TypeError] instead. Catching [Error] covers
  /// both — catching only the debug one would leave release crashing on the
  /// path this exists to keep working.
  ///
  /// A binding never goes away once built, so a found one is kept. A missing
  /// one is asked for again, because a notifier may be constructed before
  /// `ensureInitialized`, and a stale "none" would notify straight into a
  /// layout pass.
  static SchedulerBinding? _scheduler;

  static SchedulerBinding? get _schedulerOrNull {
    final held = _scheduler;
    if (held != null) return held;
    try {
      return _scheduler = SchedulerBinding.instance;
    } on Error {
      return null;
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class FrameSafeValueNotifier<T> extends FrameSafeNotifier
    implements ValueListenable<T> {
  FrameSafeValueNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  set value(T next) {
    if (isDisposed || _value == next) return;
    _value = next;
    notifySafely();
  }
}
