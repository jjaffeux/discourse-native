part of 'diagnostics_controller.dart';

final class _DiagnosticsWriteGeneration {
  _DiagnosticsWriteGeneration(this.number);

  final int number;
  final Map<String, DiagnosticEvent> pending = {};
  bool drainQueued = false;
  bool persistenceFailed = false;
}

final class _DiagnosticsWriteSession {
  _DiagnosticsWriteSession({
    required this._persistenceFactory,
    required this._clock,
    required this._onHydrated,
    required this._onFailure,
  });

  final Future<DiagnosticsPersistence> Function() _persistenceFactory;
  final DateTime Function() _clock;
  final void Function(DiagnosticsPersistenceState? stored) _onHydrated;
  final void Function(Object error, StackTrace stackTrace) _onFailure;
  final DiagnosticsJournalOperationQueue _operations =
      DiagnosticsJournalOperationQueue();
  final Completer<void> _hydrationCompleted = Completer<void>();
  DiagnosticsPersistence? _persistence;
  _DiagnosticsWriteGeneration _current = _DiagnosticsWriteGeneration(0);
  Future<void>? _hydrationTask;
  Timer? _writeTimer;
  bool _discardHydratedHistory = false;
  bool _durablePersistenceUnavailable = false;

  int get generation => _current.number;

  bool get isHydrated => _hydrationCompleted.isCompleted;

  Future<void> hydrate() => _hydrationTask ??= _performHydration();

  Future<void> _performHydration() async {
    Object? persistenceError;
    StackTrace? persistenceStack;
    var durablePersistenceUnavailable = false;
    DiagnosticsPersistence resolvedPersistence;
    DiagnosticsPersistenceState stored;

    try {
      try {
        resolvedPersistence = await _persistenceFactory();
      } on Object catch (error, stackTrace) {
        resolvedPersistence = MemoryDiagnosticsPersistence();
        durablePersistenceUnavailable = true;
        persistenceError = error;
        persistenceStack = stackTrace;
      }

      try {
        stored = await resolvedPersistence.load(nowUtc: _clock());
      } on Object catch (error, stackTrace) {
        resolvedPersistence = _LoadFailureFallbackPersistence(
          resolvedPersistence,
        );
        stored = const DiagnosticsPersistenceState();
        persistenceError = error;
        persistenceStack = stackTrace;
      }

      _persistence = resolvedPersistence;
      _durablePersistenceUnavailable = durablePersistenceUnavailable;
      _onHydrated(_discardHydratedHistory ? null : stored);
      if (persistenceError != null) {
        _recordFailure(persistenceError, persistenceStack ?? StackTrace.empty);
      }
    } finally {
      if (!_hydrationCompleted.isCompleted) {
        _hydrationCompleted.complete();
      }
    }
  }

  void record(
    DiagnosticEvent event, {
    int? generation,
    bool immediately = false,
  }) {
    final current = _current;
    if (generation != null && generation != current.number) return;
    current.pending[event.id] = event;
    if (immediately) {
      _flushPendingWrites();
      return;
    }
    _writeTimer ??= Timer(
      DiagnosticsController.ordinaryWriteDelay,
      _flushPendingWrites,
    );
  }

  void rebasePending(Map<String, DiagnosticEvent> rebasedById) {
    final pending = _current.pending;
    final rebased = [
      for (final event in pending.values) rebasedById[event.id] ?? event,
    ];
    rebased.sort((left, right) {
      final bySequence = left.sequence.compareTo(right.sequence);
      return bySequence != 0 ? bySequence : left.id.compareTo(right.id);
    });
    pending
      ..clear()
      ..addEntries(rebased.map((event) => MapEntry(event.id, event)));
  }

  void markSeen(int Function() lastSeenSequence) {
    _queue(
      () => _persistence!.writeLastSeenSequence(lastSeenSequence()),
      generation: _current,
    );
  }

  void compact(DateTime nowUtc) {
    _queue(() => _persistence!.compact(nowUtc: nowUtc), generation: _current);
  }

  Future<void> clear(void Function() publishClearedHistory) async {
    _current.pending.clear();
    _current = _DiagnosticsWriteGeneration(_current.number + 1);
    _discardHydratedHistory = true;
    _writeTimer?.cancel();
    _writeTimer = null;
    publishClearedHistory();
    _queue(() => _persistence!.clear(), generation: _current);
    await flush();
    if (_durablePersistenceUnavailable) {
      _recordFailure(
        StateError('Application support storage remains unavailable.'),
        StackTrace.empty,
      );
    }
  }

  Future<void> flush() async {
    final hydration = hydrate();
    _flushPendingWrites();
    await hydration;
    while (true) {
      final pending = _operations.done;
      await pending;
      _flushPendingWrites();
      if (identical(pending, _operations.done)) return;
    }
  }

  Future<void> close() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await flush();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _persistence!.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _flushPendingWrites() {
    _writeTimer?.cancel();
    _writeTimer = null;
    final generation = _current;
    if (generation.pending.isEmpty || generation.drainQueued) return;
    generation.drainQueued = true;
    _queue(
      () => _persistPendingWrites(generation),
      generation: generation,
      onComplete: () {
        generation.drainQueued = false;
        if (_current.pending.isNotEmpty) _flushPendingWrites();
      },
    );
  }

  Future<void> _persistPendingWrites(
    _DiagnosticsWriteGeneration generation,
  ) async {
    while (identical(generation, _current)) {
      final events = generation.pending.values.toList(growable: false);
      if (events.isEmpty) return;
      generation.pending.clear();
      await _persistence!.appendEvents(events, nowUtc: _clock());
    }
  }

  void _queue(
    Future<void> Function() operation, {
    required _DiagnosticsWriteGeneration generation,
    void Function()? onComplete,
  }) {
    unawaited(
      _operations.run(() async {
        try {
          await _hydrationCompleted.future;
          if (!identical(generation, _current)) return;
          await operation();
        } on Object catch (error, stackTrace) {
          if (identical(generation, _current)) {
            _recordFailure(error, stackTrace);
          }
        } finally {
          onComplete?.call();
        }
      }),
    );
  }

  void _recordFailure(Object error, StackTrace stackTrace) {
    if (_current.persistenceFailed) return;
    _current.persistenceFailed = true;
    _onFailure(error, stackTrace);
  }
}

final class _LoadFailureFallbackPersistence implements DiagnosticsPersistence {
  _LoadFailureFallbackPersistence(this._failed);

  final DiagnosticsPersistence _failed;
  final MemoryDiagnosticsPersistence _memory = MemoryDiagnosticsPersistence();
  bool _recovered = false;

  DiagnosticsPersistence get _active => _recovered ? _failed : _memory;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _active.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _active.appendEvents(events, nowUtc: nowUtc);

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _active.writeLastSeenSequence(sequence);

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _active.compact(nowUtc: nowUtc);

  @override
  Future<void> clear() async {
    Object? failure;
    StackTrace? failureStack;
    try {
      await _failed.clear();
      _recovered = true;
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    await _memory.clear();
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  @override
  Future<void> close() async {
    try {
      await _failed.close();
    } on Object {
      return _memory.close();
    }
    await _memory.close();
  }
}
