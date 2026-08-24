import 'dart:async';
import 'dart:collection';

import 'origin_cooldown.dart';

/// What happens to work for an origin while its server cooldown is active.
enum OriginRequestCooldownPolicy {
  /// Keep accepted work in FIFO order and admit new work up to the backlog cap.
  wait,

  /// Reject both retained waiters and newly submitted work until expiry.
  reject,
}

/// A per-origin admission gate for request-like work.
///
/// The gate owns concurrency slots, bounded FIFO backlogs, extend-only server
/// cooldowns, and shutdown. Callers retain protocol concerns: they decide when
/// a response starts a cooldown and translate gate rejections into their
/// domain-specific errors.
final class OriginRequestGate {
  OriginRequestGate({
    required this.maxConcurrentPerOrigin,
    required this.maxQueuedPerOrigin,
    required this.cooldownPolicy,
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       _newCooldown = cooldownFactory ?? OriginCooldown.new;

  final int maxConcurrentPerOrigin;

  /// Maximum retained work behind the active slots for one origin.
  ///
  /// Active leases do not count toward this limit.
  final int maxQueuedPerOrigin;
  final OriginRequestCooldownPolicy cooldownPolicy;
  final OriginCooldown Function() _newCooldown;
  final Map<String, _OriginState> _origins = {};
  bool _closed = false;

  bool get isClosed => _closed;

  /// Acquires one slot which remains active until its lease is released.
  Future<OriginRequestLease> acquire(Uri url) {
    final pending = _AcquireAdmission();
    _enqueue(url.origin, pending);
    return pending.result.future;
  }

  /// Runs [operation] in one slot and releases that slot on every outcome.
  ///
  /// [operation] starts synchronously when capacity is granted. This keeps the
  /// gate suitable for callers whose delegation timing is observable while
  /// still returning one future for queued and immediately-started work.
  Future<T> run<T>(
    Uri url,
    Future<T> Function(OriginRequestContext context) operation,
  ) {
    final pending = _RunAdmission<T>(operation);
    _enqueue(url.origin, pending);
    return pending.result.future;
  }

  /// Extends the cooldown for [url]'s origin without acquiring a slot.
  ///
  /// This is used when one request identifies a related origin which must be
  /// gated too. Extending a closed gate is deliberately inert.
  void extendCooldown(Uri url, Duration delay) {
    assert(!delay.isNegative);
    _extendCooldown(url.origin, delay);
  }

  void _enqueue(String origin, _PendingAdmission pending) {
    if (_closed) {
      pending.reject(
        const OriginRequestGateClosedException(),
        StackTrace.current,
      );
      return;
    }

    final state = _origins.putIfAbsent(origin, _createOriginState);
    final remaining = state.cooldown.remaining;
    if (remaining != null &&
        cooldownPolicy == OriginRequestCooldownPolicy.reject) {
      pending.reject(
        OriginRequestGateCooldownException(origin, remaining),
        StackTrace.current,
      );
      return;
    }
    if (state.waiting.length >= maxQueuedPerOrigin) {
      pending.reject(
        OriginRequestGateOverloadException(origin, maxQueuedPerOrigin),
        StackTrace.current,
      );
      return;
    }

    state.waiting.add(pending);
    _drain(origin, state);
  }

  _OriginState _createOriginState() => _OriginState(_newCooldown());

  void _drain(String origin, _OriginState state) {
    if (_closed || !identical(_origins[origin], state)) return;

    final remaining = state.cooldown.remaining;
    if (remaining != null) {
      if (cooldownPolicy == OriginRequestCooldownPolicy.reject) {
        _rejectWaitingForCooldown(origin, state, remaining);
      }
      return;
    }

    while (state.active < maxConcurrentPerOrigin && state.waiting.isNotEmpty) {
      final pending = state.waiting.removeFirst();
      state.active++;
      pending.grant(OriginRequestLease._(this, origin, state));
    }
    _forgetIdle(origin, state);
  }

  void _release(String origin, _OriginState state) {
    if (_closed || !identical(_origins[origin], state)) return;
    state.active--;
    assert(state.active >= 0);
    _drain(origin, state);
  }

  void _extendLeaseCooldown(String origin, _OriginState state, Duration delay) {
    if (_closed || !identical(_origins[origin], state)) return;
    _extendCooldown(origin, delay);
  }

  void _extendCooldown(String origin, Duration delay) {
    if (_closed) return;
    final state = _origins.putIfAbsent(origin, _createOriginState);
    final remaining = state.cooldown.extend(
      delay,
      onExpired: () => _drain(origin, state),
    );
    if (remaining == null) {
      _drain(origin, state);
      return;
    }
    if (cooldownPolicy == OriginRequestCooldownPolicy.reject) {
      _rejectWaitingForCooldown(origin, state, remaining);
    }
  }

  void _rejectWaitingForCooldown(
    String origin,
    _OriginState state,
    Duration remaining,
  ) {
    final error = OriginRequestGateCooldownException(origin, remaining);
    final stackTrace = StackTrace.current;
    while (state.waiting.isNotEmpty) {
      state.waiting.removeFirst().reject(error, stackTrace);
    }
  }

  void _forgetIdle(String origin, _OriginState state) {
    if (state.active == 0 &&
        state.waiting.isEmpty &&
        state.cooldown.remaining == null &&
        identical(_origins[origin], state)) {
      _origins.remove(origin);
    }
  }

  /// Rejects waiting work and makes active leases inert.
  ///
  /// Already-running operations keep the result they earn. They can neither
  /// re-arm cooldown timers nor admit more work after shutdown.
  void close() {
    if (_closed) return;
    _closed = true;
    const error = OriginRequestGateClosedException();
    final stackTrace = StackTrace.current;
    for (final state in _origins.values) {
      state.cooldown.cancel();
      while (state.waiting.isNotEmpty) {
        state.waiting.removeFirst().reject(error, stackTrace);
      }
    }
    _origins.clear();
  }
}

/// Cooldown controls available to work whose lease lifetime the gate owns.
///
/// Unlike [OriginRequestLease], this context cannot release its slot early.
/// Capturing it beyond the operation is harmless because cooldown extension
/// becomes inert as soon as [OriginRequestGate.run] releases the hidden lease.
final class OriginRequestContext {
  OriginRequestContext._(this._lease);

  final OriginRequestLease _lease;

  String get origin => _lease.origin;

  void extendCooldown(Duration delay) => _lease.extendCooldown(delay);
}

/// A held origin slot.
final class OriginRequestLease {
  OriginRequestLease._(this._owner, this.origin, this._state);

  final OriginRequestGate _owner;
  final String origin;
  final _OriginState _state;
  bool _released = false;

  /// Extends this origin's cooldown without shortening an existing deadline.
  ///
  /// A released lease and a lease which outlives [OriginRequestGate.close] are
  /// inert.
  void extendCooldown(Duration delay) {
    assert(!delay.isNegative);
    if (_released) return;
    _owner._extendLeaseCooldown(origin, _state, delay);
  }

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(origin, _state);
  }
}

sealed class OriginRequestGateException implements Exception {
  const OriginRequestGateException();
}

/// Work rejected because [OriginRequestGate.close] has already run.
final class OriginRequestGateClosedException
    extends OriginRequestGateException {
  const OriginRequestGateClosedException();

  @override
  String toString() => 'Origin request gate is closed.';
}

/// Work rejected because an origin's bounded backlog is already full.
final class OriginRequestGateOverloadException
    extends OriginRequestGateException {
  const OriginRequestGateOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Request backlog for $origin already contains $maxQueued operations.';
}

/// Work rejected by a gate configured not to retain cooldown waiters.
final class OriginRequestGateCooldownException
    extends OriginRequestGateException {
  const OriginRequestGateCooldownException(this.origin, this.retryAfter);

  final String origin;
  final Duration retryAfter;

  @override
  String toString() =>
      'Requests to $origin are paused for ${retryAfter.inSeconds}s.';
}

final class _OriginState {
  _OriginState(this.cooldown);

  final OriginCooldown cooldown;
  final Queue<_PendingAdmission> waiting = Queue();
  int active = 0;
}

sealed class _PendingAdmission {
  void grant(OriginRequestLease lease);

  void reject(Object error, StackTrace stackTrace);
}

final class _AcquireAdmission implements _PendingAdmission {
  final Completer<OriginRequestLease> result = Completer();

  @override
  void grant(OriginRequestLease lease) => result.complete(lease);

  @override
  void reject(Object error, StackTrace stackTrace) =>
      result.completeError(error, stackTrace);
}

final class _RunAdmission<T> implements _PendingAdmission {
  _RunAdmission(this.operation);

  final Future<T> Function(OriginRequestContext context) operation;
  final Completer<T> result = Completer();

  @override
  void grant(OriginRequestLease lease) => unawaited(_run(lease));

  Future<void> _run(OriginRequestLease lease) async {
    try {
      result.complete(await operation(OriginRequestContext._(lease)));
    } catch (error, stackTrace) {
      result.completeError(error, stackTrace);
    } finally {
      lease.release();
    }
  }

  @override
  void reject(Object error, StackTrace stackTrace) =>
      result.completeError(error, stackTrace);
}
