import 'dart:async';
import 'dart:convert';

import 'contracts.dart';
import 'service.dart';

/// The application-owned port used by provisional cooking consumers.
abstract interface class CookingServicePort {
  Future<bool> start();
  Future<CookingResult> cook(CookingRequest request);
  void invalidate();
  Future<void> dispose();
}

/// Bounded, coalescing application/session owner of the isolated runtime.
///
/// Requests carry their complete immutable configuration and account identity.
/// Invalidate when the host replaces account/context/configuration state; every
/// previously admitted caller immediately receives a stale fallback. Callers
/// must additionally match result identity against their current draft before
/// displaying an asynchronous result.
final class CookingHostService implements CookingServicePort {
  CookingHostService({
    CookingRuntimePort Function()? runtimeFactory,
    DateTime Function()? clock,
    this.maxCacheEntries = 64,
    this.maxCacheBytes = 2 * 1024 * 1024,
    this.maxPending = 4,
    this.recoveryDelay = const Duration(seconds: 2),
    this.maxRecoveryDelay = const Duration(minutes: 1),
  }) : _runtimeFactory = runtimeFactory ?? OfflineCookingService.new,
       _clock = clock ?? DateTime.now {
    if (maxCacheEntries < 0 ||
        maxCacheBytes < 0 ||
        maxPending <= 0 ||
        recoveryDelay <= Duration.zero ||
        maxRecoveryDelay < recoveryDelay) {
      throw ArgumentError('Invalid cooking host limits');
    }
  }

  final CookingRuntimePort Function() _runtimeFactory;
  final DateTime Function() _clock;
  final int maxCacheEntries;
  final int maxCacheBytes;
  final int maxPending;
  final Duration recoveryDelay;
  final Duration maxRecoveryDelay;
  final _cache = <String, _CachedResult>{};
  final _inflight = <String, _HostPending>{};
  final _jobs = <Future<void>>{};
  CookingRuntimePort? _runtime;
  Future<bool>? _starting;
  Future<void>? _disposing;
  DateTime? _retryAfter;
  var _failures = 0;
  var _epoch = 0;
  var _cacheBytes = 0;
  var _disposed = false;
  var _runtimeFailed = false;

  int get cachedResultCount => _cache.length;
  int get cachedBytes => _cacheBytes;
  int get pendingCount => _jobs.length;

  @override
  Future<bool> start() {
    if (_disposed) return Future.value(false);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<bool> _start() async {
    if (_retryAfter case final retry? when _clock().isBefore(retry)) {
      return false;
    }
    if (_runtime case final runtime?
        when runtime.isHealthy && !_runtimeFailed) {
      try {
        final ready = await runtime.start();
        if (!ready) {
          _runtimeFailed = true;
          _recordFailure();
        }
        return ready && !_disposed;
      } catch (_) {
        _runtimeFailed = true;
        _recordFailure();
        return false;
      }
    }
    final old = _runtime;
    _runtime = null;
    try {
      if (old != null) await old.dispose();
      if (_disposed) return false;
      final runtime = _runtime = _runtimeFactory();
      _runtimeFailed = false;
      final ready = await runtime.start();
      if (!ready) {
        _runtimeFailed = true;
        _recordFailure();
      }
      return ready && !_disposed;
    } catch (_) {
      _runtimeFailed = true;
      _recordFailure();
      return false;
    }
  }

  void _recordFailure() {
    // One failed worker can have several waiting callers. Count it once.
    if (_retryAfter != null && _clock().isBefore(_retryAfter!)) return;
    final multiplier = 1 << (_failures < 10 ? _failures : 10);
    final micros = recoveryDelay.inMicroseconds * multiplier;
    _retryAfter = _clock().add(
      Duration(
        microseconds: micros < maxRecoveryDelay.inMicroseconds
            ? micros
            : maxRecoveryDelay.inMicroseconds,
      ),
    );
    _failures++;
  }

  @override
  Future<CookingResult> cook(CookingRequest request) {
    // Never serialize/hash an unbounded source on the caller isolate, even for
    // a disposed or saturated service. Rejected oversized input has no identity
    // and therefore cannot be mistaken for a usable draft result.
    if (request.raw.length > 65536) {
      return Future.value(
        readableFallback(request.raw, CookingFailure.inputLimit),
      );
    }
    if (_disposed) {
      return Future.value(_fallback(request, CookingFailure.disposed));
    }
    final key = request.fingerprint;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached.result);
    }
    if (_inflight[key] case final pending?) return pending.result.future;
    if (_jobs.length >= maxPending) {
      return Future.value(_fallback(request, CookingFailure.busy));
    }
    final pending = _HostPending(request, _epoch);
    _inflight[key] = pending;
    final job = _cook(key, pending);
    _jobs.add(job);
    unawaited(job.whenComplete(() => _jobs.remove(job)));
    return pending.result.future;
  }

  Future<void> _cook(String key, _HostPending pending) async {
    CookingResult result;
    try {
      if (!await start()) {
        result = _fallback(pending.request, CookingFailure.unavailable);
      } else if (_disposed || pending.epoch != _epoch) {
        return;
      } else {
        final runtime = _runtime!;
        result = (await runtime.cook(
          pending.request,
        )).forRequest(pending.request);
        if (!runtime.isHealthy) {
          _recordFailure();
        } else if (!result.isFallback) {
          _failures = 0;
          _retryAfter = null;
        }
      }
    } catch (_) {
      _runtimeFailed = true;
      _recordFailure();
      result = _fallback(pending.request, CookingFailure.unavailable);
    } finally {
      if (identical(_inflight[key], pending)) _inflight.remove(key);
    }
    if (_disposed || pending.epoch != _epoch || pending.result.isCompleted) {
      return;
    }
    if (!result.isFallback) _remember(key, result);
    pending.result.complete(result);
  }

  void _remember(String key, CookingResult result) {
    final bytes = utf8.encode(jsonEncode(result.toJson())).length + key.length;
    if (maxCacheEntries == 0 || bytes > maxCacheBytes) return;
    while (_cache.isNotEmpty &&
        (_cache.length >= maxCacheEntries ||
            _cacheBytes + bytes > maxCacheBytes)) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.bytes;
    }
    _cache[key] = _CachedResult(result, bytes);
    _cacheBytes += bytes;
  }

  /// Rejects pending results without releasing their occupied runtime slots.
  /// This prevents repeated account changes from growing the worker queue.
  @override
  void invalidate() {
    _epoch++;
    _cache.clear();
    _cacheBytes = 0;
    for (final pending in _inflight.values) {
      if (!pending.result.isCompleted) {
        pending.result.complete(
          _fallback(pending.request, CookingFailure.stale),
        );
      }
    }
    _inflight.clear();
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    for (final pending in _inflight.values) {
      if (!pending.result.isCompleted) {
        pending.result.complete(
          _fallback(pending.request, CookingFailure.disposed),
        );
      }
    }
    invalidate();
    await _starting;
    await _runtime?.dispose();
    _runtime = null;
    await Future.wait(_jobs.toList());
  }
}

CookingResult _fallback(CookingRequest request, CookingFailure failure) =>
    readableFallback(request.raw, failure).forRequest(request);

final class _HostPending {
  _HostPending(this.request, this.epoch);
  final CookingRequest request;
  final int epoch;
  final result = Completer<CookingResult>();
}

final class _CachedResult {
  _CachedResult(this.result, this.bytes);
  final CookingResult result;
  final int bytes;
}
