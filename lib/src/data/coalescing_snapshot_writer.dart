import 'dart:async';

import 'serial_operation_queue.dart';

/// Writers with the same [owner] and [key] share one pending slot and load
/// barrier. Replacing a dependency therefore coalesces into the same lane: an
/// older not-yet-started value cannot overwrite the replacement's snapshot,
/// and every coalesced save future settles with that replacement write.
final class CoalescingSnapshotWriter<T> {
  CoalescingSnapshotWriter({
    required Object owner,
    required Object key,
    required Future<void> Function(T value) writeSnapshot,
  }) : _owner = owner,
       _key = key,
       _write = writeSnapshot,
       _lane = _laneFor(owner, key);

  static final SerialOperationQueue _operations = SerialOperationQueue();
  static final Expando<Map<Object, _SnapshotLane>> _lanes =
      Expando<Map<Object, _SnapshotLane>>('coalescing snapshot lanes');

  final Object _owner;
  final Object _key;
  final Future<void> Function(T value) _write;
  final _SnapshotLane _lane;

  /// Calls coalesced into the same pending slot deliberately receive the same
  /// future: they are all waiting for the same newest accepted value. Once a
  /// write has been extracted from that slot, later saves form the next slot;
  /// the extracted save settles only after its own physical write.
  Future<void> save(T value) {
    _lane.pendingWrite = () => _write(value);
    final result = _lane.pendingResult ??= Completer<void>();
    _lane.latestResult = result.future;
    if (!_lane.saving) {
      _lane.saving = true;
      unawaited(_drain());
    }
    return result.future;
  }

  /// A save failure belongs to its save caller. Readers still continue to the
  /// last durable snapshot, preserving the usual persistence-boundary policy.
  /// The shared queue also prevents a later physical write from overlapping
  /// the read even when another writer accepts it while this call is waiting.
  Future<R> read<R>(Future<R> Function() readSnapshot) async {
    await _waitForLatest();
    return _operations.run<R>(
      owner: _owner,
      key: _key,
      operation: readSnapshot,
    );
  }

  Future<void> _waitForLatest() async {
    final latest = _lane.latestResult;
    if (latest == null) return;
    try {
      await latest;
    } catch (_) {}
  }

  Future<void> _drain() async {
    try {
      while (_lane.pendingWrite != null) {
        final write = _lane.pendingWrite!;
        final result = _lane.pendingResult!;
        _lane.pendingWrite = null;
        _lane.pendingResult = null;

        try {
          await _operations.run<void>(
            owner: _owner,
            key: _key,
            operation: write,
          );
          result.complete();
        } catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
        _clearLatest(result.future);
      }
    } finally {
      _lane.saving = false;
      if (_lane.pendingWrite != null) {
        _lane.saving = true;
        unawaited(_drain());
      }
    }
  }

  void _clearLatest(Future<void> result) {
    if (identical(_lane.latestResult, result)) {
      _lane.latestResult = null;
    }
  }

  static _SnapshotLane _laneFor(Object owner, Object key) {
    final lanes = _lanes[owner] ??= <Object, _SnapshotLane>{};
    return lanes.putIfAbsent(key, _SnapshotLane.new);
  }
}

final class _SnapshotLane {
  Future<void> Function()? pendingWrite;
  Completer<void>? pendingResult;
  bool saving = false;
  Future<void>? latestResult;
}
