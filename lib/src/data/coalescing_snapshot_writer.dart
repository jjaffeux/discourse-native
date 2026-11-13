import 'dart:async';

import 'serial_operation_queue.dart';

/// Writers with the same `owner` and `key` share one pending slot and load
/// barrier. Replacing a dependency therefore coalesces into the same lane: an
/// older not-yet-started value cannot overwrite the replacement's snapshot,
/// and every coalesced save future settles with that replacement write.
///
/// Only the newest value accepted before a write starts reaches
/// `writeSnapshot`; the values it superseded are dropped unexamined. A store
/// may therefore save an unserialized snapshot and serialize it inside
/// `writeSnapshot`, paying only for the snapshots that are written.
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
    _lane.sharedReads.clear();
    final submitter = Zone.current;
    final result = _lane.pending?.result ?? Completer<void>();
    Future<void> write() {
      final completion = Completer<void>();
      unawaited(
        submitter.run(
          () => Future<void>.sync(
            () => _write(value),
          ).then<void>(completion.complete, onError: completion.completeError),
        ),
      );
      return completion.future;
    }

    _lane.pending = (write: write, result: result);
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

  /// Shares overlapping reads of the same result type. Callers using this
  /// method for a lane and type must supply equivalent snapshot readers.
  Future<R> readShared<R>(Future<R> Function() readSnapshot, {Object? scope}) {
    final key = (R, scope);
    if (_lane.sharedReads[key] case final Future<R> active) return active;
    late final Future<R> pending;
    pending = read(readSnapshot).whenComplete(() {
      if (identical(_lane.sharedReads[key], pending)) {
        final _ = _lane.sharedReads.remove(key);
      }
    });
    _lane.sharedReads[key] = pending;
    return pending;
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
      // One synchronous transaction can save several times; waiting out its
      // turn leaves one write, of the state it ended with.
      await Future<void>.value();
      while (true) {
        final pending = _lane.pending;
        if (pending == null) break;
        final (:write, :result) = pending;
        _lane.pending = null;

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
      if (_lane.pending != null) {
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
  final sharedReads = <(Type, Object?), Future<Object?>>{};
  ({Future<void> Function() write, Completer<void> result})? pending;
  bool saving = false;
  Future<void>? latestResult;
}
