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
  static SchedulerBinding? get _schedulerOrNull {
    try {
      return SchedulerBinding.instance;
    } on FlutterError {
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

/// A [ValueListenable] with the same frame-safe notification semantics.
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
