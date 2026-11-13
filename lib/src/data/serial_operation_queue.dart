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
  final _reads =
      <
        _SerialOperationKey,
        ({Type type, Zone errorZone, Object? scope, Future<Object?> result})
      >{};

  /// Shares consecutive pending reads of the same result type and error zone.
  /// Readers for a given owner, key, scope, and type must be equivalent.
  /// A regular [run] starts a new group.
  Future<T> readShared<T>({
    required Object owner,
    required Object key,
    required Future<T> Function() operation,
    Object? scope,
  }) {
    final queueKey = _SerialOperationKey(owner, key);
    final errorZone = Zone.current.errorZone;
    if (_reads[queueKey]
        case (
          :final type,
          scope: final activeScope,
          errorZone: final activeZone,
          result: final Future<T> active,
        )
        when type == T &&
            identical(activeScope, scope) &&
            identical(activeZone, errorZone)) {
      return active;
    }
    late final Future<T> read;
    read = run(owner: owner, key: key, operation: operation).whenComplete(() {
      if (identical(_reads[queueKey]?.result, read)) {
        final _ = _reads.remove(queueKey);
      }
    });
    _reads[queueKey] = (
      type: T,
      errorZone: errorZone,
      scope: scope,
      result: read,
    );
    return read;
  }

  Future<T> run<T>({
    required Object owner,
    required Object key,
    required Future<T> Function() operation,
  }) {
    final queueKey = _SerialOperationKey(owner, key);
    final _ = _reads.remove(queueKey);
    final previous = _tails[queueKey] ?? Future<void>.value();
    final result = Completer<T>();
    late final Future<void> current;
    current = previous.then<void>((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        if (identical(_tails[queueKey], current)) {
          final _ = _tails.remove(queueKey);
        }
      }
    });
    _tails[queueKey] = current;
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
    return _operations.run(
      owner: owner,
      key: key,
      operation: () async {
        try {
          return await operation();
        } finally {
          final remaining = _pendingWrites[lane]! - 1;
          if (remaining == 0) {
            _pendingWrites.remove(lane);
          } else {
            _pendingWrites[lane] = remaining;
          }
        }
      },
    );
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
