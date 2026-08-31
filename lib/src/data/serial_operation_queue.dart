import 'dart:async';

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

/// A write is considered pending as soon as [write] is called, including while
/// it is waiting behind an earlier write. A later [read] for the same identity
/// owner and equal key joins that queue; otherwise the read bypasses it. This
/// keeps abandoned or slow hydration reads from delaying future saves.
/// Keys must retain stable equality and hash codes while work is pending.
final class ReadAfterWriteOperationQueue {
  final SerialOperationQueue _operations = SerialOperationQueue();
  final Map<_SerialOperationKey, int> _pendingWrites = {};

  Future<T> read<T>({
    required Object owner,
    required Object key,
    required Future<T> Function() operation,
  }) {
    final lane = _SerialOperationKey(owner, key);
    if ((_pendingWrites[lane] ?? 0) == 0) return Future.sync(operation);
    return _operations.run(owner: owner, key: key, operation: operation);
  }

  Future<T> write<T>({
    required Object owner,
    required Object key,
    required Future<T> Function() operation,
  }) {
    final lane = _SerialOperationKey(owner, key);
    _pendingWrites.update(lane, (count) => count + 1, ifAbsent: () => 1);
    return _operations
        .run(owner: owner, key: key, operation: operation)
        .whenComplete(() {
          final remaining = _pendingWrites[lane]! - 1;
          if (remaining == 0) {
            _pendingWrites.remove(lane);
          } else {
            _pendingWrites[lane] = remaining;
          }
        });
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
