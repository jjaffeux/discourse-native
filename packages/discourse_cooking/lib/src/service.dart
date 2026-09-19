import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'contracts.dart';
import 'generated_bundle.dart';
import 'native_runtime.dart';
import 'wall_clock_deadline.dart';

/// Resource limits apply per service/runtime, never per token or host callback.
final class CookingLimits {
  const CookingLimits({
    this.maxRawCodeUnits = 65536,
    this.maxRequestBytes = 262144,
    this.maxOutputBytes = 1048576,
    this.memoryLimitBytes = 67108864,
    this.maxStackBytes = 1048576,
    this.maxPending = 4,
    this.executionTimeout = const Duration(milliseconds: 250),
    this.startupTimeout = const Duration(seconds: 10),
  });

  final int maxRawCodeUnits;
  final int maxRequestBytes;
  final int maxOutputBytes;
  final int memoryLimitBytes;
  final int maxStackBytes;
  final int maxPending;
  final Duration executionTimeout;
  final Duration startupTimeout;

  void validate() {
    if (maxRawCodeUnits <= 0 ||
        maxRequestBytes <= 0 ||
        maxOutputBytes <= 0 ||
        memoryLimitBytes <= 0 ||
        maxStackBytes <= 0 ||
        maxPending <= 0 ||
        executionTimeout.inMilliseconds <= 0 ||
        startupTimeout.inMilliseconds <= 0 ||
        executionTimeout > const Duration(minutes: 1) ||
        startupTimeout > const Duration(minutes: 1)) {
      throw ArgumentError('Cooking limits must be positive');
    }
  }
}

/// A persistent worker owns all JS evaluation and native resources.
///
/// Call [start] to prewarm, or let the first [cook] start the worker. Each cook
/// carries its complete immutable snapshot. Never share mutable engine context
/// between requests. Call [dispose] when the application service is released.
abstract interface class CookingRuntimePort {
  Future<bool> start();
  Future<CookingResult> cook(CookingRequest request);
  Future<void> dispose();
  bool get isHealthy;
}

final class OfflineCookingService implements CookingRuntimePort {
  OfflineCookingService({this.limits = const CookingLimits()}) {
    limits.validate();
  }

  final CookingLimits limits;
  final _pending = <int, _Pending>{};
  Isolate? _worker;
  ReceivePort? _events;
  SendPort? _commands;
  Future<bool>? _starting;
  Completer<bool>? _ready;
  Completer<void>? _stopped;
  Future<void>? _disposing;
  bool _disposed = false;
  bool _healthy = true;
  @override
  bool get isHealthy => !_disposed && _healthy;
  int _sequence = 0;
  int _admitted = 0;

  /// Measured worker creation plus bundle initialization, excluding package build.
  int startupMicroseconds = 0;

  @override
  Future<bool> start() {
    if (_disposed) return Future.value(false);
    return _starting ??= _spawn();
  }

  Future<bool> _spawn() async {
    final timer = Stopwatch()..start();
    final events = _events = ReceivePort();
    final ready = _ready = Completer<bool>();
    events.listen(_onEvent);
    try {
      _worker = await Isolate.spawn(
        _workerMain,
        (events.sendPort, limits),
        onError: events.sendPort,
        onExit: events.sendPort,
        errorsAreFatal: true,
        debugName: 'discourse-offline-cooking',
      );
      final success = await withWallClockDeadline(
        ready.future,
        limits.startupTimeout,
      );
      startupMicroseconds = timer.elapsedMicroseconds;
      if (!success) _terminate();
      return success;
    } catch (_) {
      _terminate();
      return false;
    }
  }

  @override
  Future<CookingResult> cook(CookingRequest request) async =>
      request.raw.length > limits.maxRawCodeUnits
      ? readableFallback(request.raw, CookingFailure.inputLimit)
      : (await _cook(request)).forRequest(request);

  Future<CookingResult> _cook(CookingRequest request) async {
    if (!request.effectiveConfiguration.profiles.any(
      (p) =>
          cookingFingerprint(p.toJson()) ==
          cookingFingerprint(request.profile.toJson()),
    )) {
      throw ArgumentError('Profile is not installed');
    }
    if (_disposed) {
      return readableFallback(request.raw, CookingFailure.disposed);
    }
    if (_admitted >= limits.maxPending) {
      return readableFallback(request.raw, CookingFailure.busy);
    }
    if (request.raw.length > limits.maxRawCodeUnits ||
        !_withinStructuralBudget(request.toJson(), limits.maxRequestBytes)) {
      return readableFallback(request.raw, CookingFailure.inputLimit);
    }
    final serialized = jsonEncode(request.toJson());
    if (utf8.encode(serialized).length > limits.maxRequestBytes) {
      return readableFallback(request.raw, CookingFailure.inputLimit);
    }
    _admitted++;
    try {
      if (!await start() || _commands == null) {
        return readableFallback(
          request.raw,
          _disposed ? CookingFailure.disposed : CookingFailure.unavailable,
        );
      }
      if (_disposed) {
        return readableFallback(request.raw, CookingFailure.disposed);
      }
      final id = _sequence++;
      final pending = _Pending(request.raw);
      _pending[id] = pending;
      _commands!.send([id, serialized]);
      // The native interrupt enforces actual CPU execution. This outer watchdog
      // covers a crashed worker or broken transport, including bounded queueing.
      pending.watchdog = wallClockTimer(
        limits.executionTimeout * (limits.maxPending + 1) +
            const Duration(seconds: 2),
        () => _terminate(CookingFailure.timeout),
      );
      return await pending.result.future;
    } finally {
      _admitted--;
    }
  }

  void _onEvent(Object? event) {
    if (event is SendPort) {
      _commands = event;
      if (!(_ready?.isCompleted ?? true)) _ready!.complete(true);
    } else if (event is Map) {
      final id = event['id'] as int;
      final pending = _pending.remove(id);
      if (pending == null) return;
      pending.watchdog?.cancel();
      final failure = event['failure'] as String?;
      if (failure != null) {
        pending.result.complete(
          readableFallback(pending.raw, CookingFailure.values.byName(failure)),
        );
      } else {
        try {
          pending.result.complete(
            CookingResult.fromJson(
              (event['result']! as Map).cast<String, Object?>(),
            ),
          );
        } catch (_) {
          pending.result.complete(
            readableFallback(pending.raw, CookingFailure.engine),
          );
        }
      }
    } else {
      // Isolate error/exit messages intentionally never expose account text.
      _terminate();
    }
  }

  void _terminate([CookingFailure reason = CookingFailure.unavailable]) {
    _healthy = false;
    _commands = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _events?.close();
    _events = null;
    if (!(_ready?.isCompleted ?? true)) _ready!.complete(false);
    for (final pending in _pending.values) {
      pending.watchdog?.cancel();
      if (!pending.result.isCompleted) {
        pending.result.complete(readableFallback(pending.raw, reason));
      }
    }
    _pending.clear();
    if (!(_stopped?.isCompleted ?? true)) _stopped!.complete();
  }

  /// Cancels callers immediately, then awaits worker-side native disposal.
  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    for (final pending in _pending.values) {
      pending.watchdog?.cancel();
      pending.result.complete(
        readableFallback(pending.raw, CookingFailure.disposed),
      );
    }
    _pending.clear();
    if (_starting != null) await _starting;
    if (_commands == null) {
      _terminate();
      return;
    }
    final stopped = _stopped = Completer<void>();
    _commands!.send(null);
    try {
      await withWallClockDeadline(
        stopped.future,
        limits.executionTimeout * (limits.maxPending + 1) +
            const Duration(seconds: 2),
      );
    } on TimeoutException {
      _terminate();
    }
  }
}

final class _Pending {
  _Pending(this.raw);
  final String raw;
  final result = Completer<CookingResult>();
  Timer? watchdog;
}

bool _withinStructuralBudget(Object? value, int budget) {
  var remaining = budget;
  bool visit(Object? node, int depth) {
    if (depth > 32 || --remaining < 0) return false;
    if (node is String) {
      remaining -= node.length;
    } else if (node is Map<String, Object?>) {
      for (final entry in node.entries) {
        if (!visit(entry.key, depth + 1) || !visit(entry.value, depth + 1)) {
          return false;
        }
      }
    } else if (node is List<Object?>) {
      for (final item in node) {
        if (!visit(item, depth + 1)) return false;
      }
    }
    return remaining >= 0;
  }

  return visit(value, 0);
}

void _workerMain((SendPort, CookingLimits) args) async {
  final (events, limits) = args;
  NativeCookingRuntime? runtime;
  final commands = ReceivePort();
  NativeCookingRuntime createRuntime() {
    final instance = NativeCookingRuntime(
      memoryLimitBytes: limits.memoryLimitBytes,
      maxStackBytes: limits.maxStackBytes,
      maxOutputBytes: limits.maxOutputBytes,
    );
    try {
      instance.evaluate(cookingBundle, timeout: limits.startupTimeout);
      return instance;
    } catch (_) {
      instance.dispose();
      rethrow;
    }
  }

  try {
    runtime = createRuntime();
    events.send(commands.sendPort);
    await for (final message in commands) {
      if (message == null) break;
      final values = message as List;
      final id = values[0] as int;
      final timer = Stopwatch()..start();
      try {
        runtime ??= createRuntime();
        final output = runtime.evaluate(
          'cook(${jsonEncode(values[1])})',
          timeout: limits.executionTimeout,
        );
        final result = (jsonDecode(output) as Map).cast<String, Object?>();
        if (result['failure'] != null) {
          runtime.dispose();
          runtime = null;
          events.send({'id': id, 'failure': CookingFailure.engine.name});
          continue;
        }
        result['elapsedMicroseconds'] = timer.elapsedMicroseconds;
        result['memoryUsageBytes'] = runtime.memoryUsageBytes;
        events.send({'id': id, 'result': result});
      } catch (error) {
        runtime?.dispose();
        runtime = null;
        // Native adapter error categories are stable; no raw engine message is
        // sent to the UI because it may contain private source text.
        events.send({'id': id, 'failure': _classify(error).name});
      }
    }
  } finally {
    commands.close();
    runtime?.dispose();
  }
}

CookingFailure _classify(Object error) => switch (error) {
  NativeCookingException(kind: NativeCookingError.timeout) =>
    CookingFailure.timeout,
  NativeCookingException(kind: NativeCookingError.outputLimit) =>
    CookingFailure.outputLimit,
  _ => CookingFailure.engine,
};
