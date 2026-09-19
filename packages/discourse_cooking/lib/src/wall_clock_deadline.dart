import 'dart:async';

/// Native workers progress in wall time, independently of the caller's UI zone.
/// In particular, a widget's simulated timers must neither expire native work
/// prematurely nor retain ownership of asynchronous worker shutdown.
Timer wallClockTimer(Duration duration, void Function() callback) =>
    Zone.root.createTimer(duration, Zone.current.bindCallbackGuarded(callback));

/// Keeps completion/error delivery in the caller's zone while the deadline
/// itself belongs to the real clock. Late completion remains observed, and
/// every settled operation cancels its deadline.
Future<T> withWallClockDeadline<T>(
  Future<T> operation,
  Duration duration, {
  Timer Function(Duration, void Function()) createTimer = wallClockTimer,
}) {
  final result = Completer<T>();
  final timer = createTimer(duration, () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('Worker deadline exceeded', duration),
      );
    }
  });
  operation.then(
    (value) {
      timer.cancel();
      if (!result.isCompleted) result.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future;
}
