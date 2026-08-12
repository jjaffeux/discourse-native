import 'dart:async';

/// Serializes asynchronous operations that target the same owner and key.
///
/// Operations for unrelated keys remain independent. A failed operation is
/// delivered to its caller without poisoning the queue for later work.
///
/// Owners are compared by identity; keys must have stable equality and hash
/// codes while their operations are pending. Operations are not reentrant for
/// the same owner and key: awaiting a nested [run] would wait on the operation
/// that initiated it.
final class SerialOperationQueue {
  final Map<_SerialOperationKey, Future<void>> _tails = {};

  Future<T> run<T>({
    required Object owner,
    required Object key,
    required Future<T> Function() operation,
  }) {
    final queueKey = _SerialOperationKey(owner, key);
    final previous = _tails[queueKey] ?? Future<void>.value();
    final result = Completer<T>();
    final current = previous.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _tails[queueKey] = current;
    unawaited(
      current.then<void>((_) {
        if (identical(_tails[queueKey], current)) {
          final _ = _tails.remove(queueKey);
        }
      }),
    );
    return result.future;
  }
}

final class _SerialOperationKey {
  const _SerialOperationKey(this.owner, this.key);

  final Object owner;
  final Object key;

  @override
  bool operator ==(Object other) =>
      other is _SerialOperationKey &&
      identical(owner, other.owner) &&
      key == other.key;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), key);
}
