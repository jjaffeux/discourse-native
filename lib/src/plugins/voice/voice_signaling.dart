import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

typedef VoiceSignalBatchRequest =
    Future<void> Function(Map<String, Object?> payload);

/// Coalesces mesh signaling into the bounded multi-recipient envelope accepted
/// by current Voice servers.
///
/// Requests stay ordered, while events for one recipient are flushed before
/// the server's 25-event limit. Twenty leaves room for a candidate batch that
/// lands at the edge of a scheduled flush.
final class VoiceSignalBatcher {
  VoiceSignalBatcher({
    required this.sendBatch,
    this.batchDelay = const Duration(milliseconds: 200),
    this.flushEventThreshold = 20,
  }) {
    if (flushEventThreshold < 1 || flushEventThreshold > 25) {
      throw RangeError.range(flushEventThreshold, 1, 25);
    }
  }

  final VoiceSignalBatchRequest sendBatch;
  final Duration batchDelay;
  final int flushEventThreshold;
  LinkedHashMap<int, List<Map<String, Object?>>> _pending = LinkedHashMap();
  List<Completer<void>> _pendingWaiters = [];
  Timer? _timer;
  Future<void> _sendTail = Future<void>.value();
  bool _closed = false;

  Future<void> send(int recipientId, Map<String, Object?> event) {
    if (_closed) return Future<void>.value();
    if (recipientId <= 0) {
      return Future<void>.error(
        RangeError.value(recipientId, 'recipientId', 'Must be positive.'),
      );
    }

    final events = _eventsFrom(event);
    if (events.isEmpty) return Future<void>.value();
    final completions = <Future<void>>[];
    var offset = 0;
    while (offset < events.length) {
      var queued = _pending[recipientId]?.length ?? 0;
      if (queued >= flushEventThreshold) {
        _startFlush();
        queued = 0;
      }
      final count = math.min(
        flushEventThreshold - queued,
        events.length - offset,
      );
      final waiter = Completer<void>();
      (_pending[recipientId] ??= []).addAll(
        events.getRange(offset, offset + count),
      );
      _pendingWaiters.add(waiter);
      completions.add(waiter.future);
      offset += count;
      if (_pending[recipientId]!.length >= flushEventThreshold) {
        _startFlush();
      }
    }

    if (_pending.isNotEmpty && _timer == null) {
      _timer = Timer(batchDelay, _startFlush);
    }
    return Future.wait(completions);
  }

  Future<void> flush() {
    _startFlush();
    return _sendTail;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    final waiters = _pendingWaiters;
    _pendingWaiters = [];
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _startFlush() {
    _timer?.cancel();
    _timer = null;
    if (_closed || _pending.isEmpty) return;

    final batches = _pending;
    final waiters = _pendingWaiters;
    _pending = LinkedHashMap();
    _pendingWaiters = [];
    final payload = <String, Object?>{
      'messages': [
        for (final entry in batches.entries)
          {'recipient_id': entry.key, 'events': entry.value},
      ],
    };
    final operation = _sendTail.then((_) => sendBatch(payload));
    _sendTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(
      operation.then<void>(
        (_) {
          for (final waiter in waiters) {
            if (!waiter.isCompleted) waiter.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          for (final waiter in waiters) {
            if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
          }
        },
      ),
    );
  }

  static List<Map<String, Object?>> _eventsFrom(Map<String, Object?> event) {
    final batched = event['events'];
    if (batched is Iterable) {
      return [
        for (final value in batched)
          if (value is Map) Map<String, Object?>.from(value),
      ];
    }
    return [Map<String, Object?>.from(event)];
  }
}
