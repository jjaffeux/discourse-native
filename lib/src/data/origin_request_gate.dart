import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import '../foundation/retry_wait.dart';
import 'origin_cooldown.dart';

enum OriginRequestCooldownPolicy {
  /// Keep accepted work in priority/FIFO order up to the backlog cap.
  wait,

  /// Reject both retained waiters and newly submitted work until expiry.
  reject,
}

enum OriginRequestPriority { normal, interactive }

/// The gate owns concurrency slots, bounded priority backlogs with FIFO order
/// inside each priority, extend-only server cooldowns, and shutdown. Callers
/// retain protocol concerns: they decide when a response starts a cooldown and
/// translate gate rejections into their domain-specific errors.
final class OriginRequestGate {
  OriginRequestGate({
    this.maxConcurrent,
    required this.maxConcurrentPerOrigin,
    required this.maxQueuedPerOrigin,
    required this.cooldownPolicy,
    this.interactiveSlotsPerOrigin = 0,
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrent == null || maxConcurrent > 0),
       assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       assert(interactiveSlotsPerOrigin >= 0),
       assert(interactiveSlotsPerOrigin < maxConcurrentPerOrigin),
       _newCooldown = cooldownFactory ?? OriginCooldown.new;

  /// The aggregate active-operation limit, or null when origins are
  /// independent.
  final int? maxConcurrent;
  final int maxConcurrentPerOrigin;

  /// Active leases do not count toward this limit.
  final int maxQueuedPerOrigin;

  /// Slots of each origin that normal work may not take, so a page someone is
  /// waiting for never queues behind metadata that holds all of them.
  final int interactiveSlotsPerOrigin;
  final OriginRequestCooldownPolicy cooldownPolicy;
  final OriginCooldown Function() _newCooldown;
  final Map<String, _OriginState> _origins = {};
  final _waiting = <_PendingAdmission, _QueuedAdmission>{};
  int _active = 0;
  int _interactiveOvertakes = 0;
  bool _closed = false;
  bool _draining = false;
  int _waitingRevision = 0;

  bool get isClosed => _closed;

  /// [resolvePriority], when provided, replaces [priority] at each admission
  /// scan. An eligible normal request permits at most three interactive grants
  /// before its contention domain serves normal work again.
  Future<OriginRequestLease> acquire(
    Uri url, {
    OriginRequestPriority priority = OriginRequestPriority.normal,
    OriginRequestPriority Function()? resolvePriority,
    Future<void>? abortTrigger,
  }) {
    final pending = _AcquireAdmission();
    _enqueue(url.origin, pending, resolvePriority ?? () => priority);
    _watchAbort(pending, abortTrigger);
    return pending.result.future;
  }

  /// [operation] starts synchronously when capacity is granted. This keeps the
  /// gate suitable for callers whose delegation timing is observable while
  /// still returning one future for queued and immediately-started work.
  ///
  /// Queued work is granted from whichever lease release or cooldown wake
  /// frees capacity, but always starts in the zone that called [run]: that
  /// zone retains the caller's account and request context.
  Future<T> run<T>(
    Uri url,
    Future<T> Function(OriginRequestContext context) operation, {
    OriginRequestPriority priority = OriginRequestPriority.normal,
    OriginRequestPriority Function()? resolvePriority,
    Future<void>? abortTrigger,
  }) {
    final pending = _RunAdmission<T>(operation);
    _enqueue(url.origin, pending, resolvePriority ?? () => priority);
    _watchAbort(pending, abortTrigger);
    return pending.result.future;
  }

  void _watchAbort(_PendingAdmission pending, Future<void>? abortTrigger) {
    unawaited(
      abortTrigger?.then<void>(
        (_) => _cancelQueued(pending),
        onError: (Object _, StackTrace _) => _cancelQueued(pending),
      ),
    );
  }

  void _cancelQueued(_PendingAdmission pending) => _rejectQueued(
    pending,
    const OriginRequestGateCancelledException(),
    StackTrace.current,
  );

  void _rejectQueued(
    _PendingAdmission pending,
    Object error,
    StackTrace stackTrace,
  ) {
    final entry = _waiting.remove(pending);
    if (entry == null) return;
    _waitingRevision++;
    entry.state.waiting--;
    pending.reject(error, stackTrace);
    _forgetIdle(entry.origin, entry.state);
  }

  /// This is used when one request identifies a related origin which must be
  /// gated too. Extending a closed gate is deliberately inert.
  void extendCooldown(Uri url, Duration delay) {
    assert(!delay.isNegative);
    _extendCooldown(url.origin, delay);
  }

  void _enqueue(
    String origin,
    _PendingAdmission pending,
    OriginRequestPriority Function() resolvePriority,
  ) {
    if (_closed) {
      pending.reject(
        const OriginRequestGateClosedException(),
        StackTrace.current,
      );
      return;
    }

    final state = _origins.putIfAbsent(origin, _createOriginState);
    // Reading an expired cooldown cancels its wake. Wait-policy admissions
    // leave that read to _drain so a full backlog cannot lose its wake.
    if (cooldownPolicy == OriginRequestCooldownPolicy.reject) {
      final remaining = state.cooldown.remaining;
      if (remaining != null) {
        pending.reject(
          OriginRequestGateCooldownException(origin, remaining),
          StackTrace.current,
        );
        return;
      }
    }
    if (state.waiting >= maxQueuedPerOrigin) {
      pending.reject(
        OriginRequestGateOverloadException(origin, maxQueuedPerOrigin),
        StackTrace.current,
      );
      return;
    }

    state.waiting++;
    _waiting[pending] = _QueuedAdmission(
      origin,
      state,
      pending,
      Zone.current.bindCallback(resolvePriority),
    );
    _waitingRevision++;
    _drain();
  }

  _OriginState _createOriginState() => _OriginState(_newCooldown());

  void _drain() {
    if (_closed || _draining) return;
    _draining = true;
    try {
      _drainAvailable();
    } finally {
      _draining = false;
    }
  }

  void _drainAvailable() {
    final aggregateLimit = maxConcurrent;
    drain:
    while (!_closed && (aggregateLimit == null || _active < aggregateLimit)) {
      final revision = _waitingRevision;
      final candidates =
          <String, ({_Candidate? normal, _Candidate? interactive})>{};
      var index = 0;
      for (final queued in _waiting.values) {
        final position = index++;
        final state = queued.state;
        if (!identical(_origins[queued.origin], state) ||
            state.active >= maxConcurrentPerOrigin ||
            state.cooldown.remaining != null) {
          continue;
        }
        final domain = aggregateLimit == null ? queued.origin : '';
        final OriginRequestPriority priority;
        try {
          priority = queued.priority;
        } catch (error, stackTrace) {
          _rejectQueued(queued.pending, error, stackTrace);
          continue drain;
        }
        if (_closed) return;
        if (revision != _waitingRevision) continue drain;
        if (state.cooldown.remaining != null) continue;
        if (priority != OriginRequestPriority.interactive &&
            state.active >=
                maxConcurrentPerOrigin - interactiveSlotsPerOrigin) {
          continue;
        }
        final held = candidates[domain];
        if (priority == OriginRequestPriority.interactive) {
          if (held?.interactive == null) {
            candidates[domain] = (
              normal: held?.normal,
              interactive: (position, queued),
            );
          }
        } else if (held?.normal == null) {
          candidates[domain] = (
            normal: (position, queued),
            interactive: held?.interactive,
          );
        }
      }
      _Candidate? eligible;
      for (final (normal: background, interactive: foreground)
          in candidates.values) {
        final overtakes = aggregateLimit == null
            ? (background ?? foreground!).$2.state.interactiveOvertakes
            : _interactiveOvertakes;
        final candidate =
            background != null && (foreground == null || overtakes >= 3)
            ? background
            : foreground!;
        if (eligible == null || candidate.$1 < eligible.$1) {
          eligible = candidate;
        }
      }
      if (eligible == null) break;

      final queued = eligible.$2;
      _waiting.remove(queued.pending);
      _waitingRevision++;
      final domain = aggregateLimit == null ? queued.origin : '';
      final choice = candidates[domain]!;
      final overtook = choice.normal != null && choice.interactive == eligible;
      if (aggregateLimit == null) {
        queued.state.interactiveOvertakes = overtook
            ? queued.state.interactiveOvertakes + 1
            : 0;
      } else {
        _interactiveOvertakes = overtook ? _interactiveOvertakes + 1 : 0;
      }
      queued.state.waiting--;
      queued.state.active++;
      _active++;
      queued.pending.grant(
        OriginRequestLease._(this, queued.origin, queued.state),
      );
    }
  }

  void _release(String origin, _OriginState state) {
    if (_closed || !identical(_origins[origin], state)) return;
    state.active--;
    _active--;
    assert(state.active >= 0);
    assert(_active >= 0);
    _forgetIdle(origin, state);
    _drain();
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
      onExpired: () {
        _forgetIdle(origin, state);
        _drain();
      },
    );
    if (remaining == null) {
      _forgetIdle(origin, state);
      _drain();
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
    final rejected = _waiting.values
        .where((queued) => identical(queued.state, state))
        .toList();
    for (final queued in rejected.reversed) {
      _waiting.remove(queued.pending);
      _waitingRevision++;
      state.waiting--;
      queued.pending.reject(error, stackTrace);
    }
  }

  void _forgetIdle(String origin, _OriginState state) {
    if (state.active == 0 &&
        state.waiting == 0 &&
        state.cooldown.remaining == null &&
        identical(_origins[origin], state)) {
      _origins.remove(origin);
    }
  }

  /// Already-running operations keep the result they earn. They can neither
  /// re-arm cooldown timers nor admit more work after shutdown.
  void close() {
    if (_closed) return;
    _closed = true;
    const error = OriginRequestGateClosedException();
    final stackTrace = StackTrace.current;
    for (final state in _origins.values) {
      state.cooldown.cancel();
    }
    for (final queued in _waiting.values) {
      queued.pending.reject(error, stackTrace);
    }
    _waiting.clear();
    _waitingRevision++;
    _origins.clear();
    _active = 0;
  }
}

/// Unlike [OriginRequestLease], this context cannot release its slot early.
/// Capturing it beyond the operation is harmless because cooldown extension
/// becomes inert as soon as [OriginRequestGate.run] releases the hidden lease.
final class OriginRequestContext {
  OriginRequestContext._(this._lease);

  final OriginRequestLease _lease;

  void extendCooldown(Duration delay) => _lease.extendCooldown(delay);
}

final class OriginRequestLease {
  OriginRequestLease._(this._owner, this.origin, this._state);

  final OriginRequestGate _owner;
  final String origin;
  final _OriginState _state;
  bool _released = false;

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

final class OriginRequestGateCancelledException
    extends OriginRequestGateException {
  const OriginRequestGateCancelledException();
}

final class OriginRequestGateClosedException
    extends OriginRequestGateException {
  const OriginRequestGateClosedException();

  @override
  String toString() => appL10n.originRequestGateIsClosed;
}

final class OriginRequestGateOverloadException
    extends OriginRequestGateException {
  const OriginRequestGateOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() => appL10n.requestBacklogForAlreadyContainsOperations(
    (origin).toString(),
    (maxQueued).toString(),
  );
}

final class OriginRequestGateCooldownException
    extends OriginRequestGateException {
  const OriginRequestGateCooldownException(this.origin, this.retryAfter);

  final String origin;
  final Duration retryAfter;

  @override
  String toString() => appL10n.requestsToArePausedForS(
    (origin).toString(),
    waitSeconds(retryAfter).toString(),
  );
}

final class _OriginState {
  _OriginState(this.cooldown);

  final OriginCooldown cooldown;
  int waiting = 0;
  int active = 0;
  int interactiveOvertakes = 0;
}

typedef _Candidate = (int, _QueuedAdmission);

final class _QueuedAdmission {
  const _QueuedAdmission(
    this.origin,
    this.state,
    this.pending,
    this.resolvePriority,
  );

  final String origin;
  final _OriginState state;
  final _PendingAdmission pending;
  final OriginRequestPriority Function() resolvePriority;
  OriginRequestPriority get priority => resolvePriority();
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
  final Zone _submitter = Zone.current;

  @override
  void grant(OriginRequestLease lease) =>
      unawaited(_submitter.run(() => _run(lease)));

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
