import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/app_release.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_error_cause.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_redactor.dart';
import 'package:discourse_native/src/diagnostics/recording_http.dart';
import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:flutter/foundation.dart';

export 'diagnostic_event.dart' show DiagnosticSeverity;

enum DiagnosticsKindFilter { all, requests, errors }

typedef DiagnosticsTimerFactory =
    Timer Function(Duration duration, void Function() callback);

@immutable
final class DiagnosticsPanelState {
  DiagnosticsPanelState({
    this.isOpen = false,
    this.frozen = false,
    this.kindFilter = DiagnosticsKindFilter.all,
    Set<DiagnosticSeverity> severities = const {},
    Set<String> sources = const {},
    this.query = '',
    this.selectedEventId,
  }) : severities = Set.unmodifiable(severities),
       sources = Set.unmodifiable(sources);

  final bool isOpen;
  final bool frozen;
  final DiagnosticsKindFilter kindFilter;

  /// Empty means all severities.
  final Set<DiagnosticSeverity> severities;

  /// Empty means all sources.
  final Set<String> sources;
  final String query;
  final String? selectedEventId;

  DiagnosticsPanelState copyWith({
    bool? isOpen,
    bool? frozen,
    DiagnosticsKindFilter? kindFilter,
    Set<DiagnosticSeverity>? severities,
    Set<String>? sources,
    String? query,
    Object? selectedEventId = _notProvided,
  }) => DiagnosticsPanelState(
    isOpen: isOpen ?? this.isOpen,
    frozen: frozen ?? this.frozen,
    kindFilter: kindFilter ?? this.kindFilter,
    severities: Set.unmodifiable(severities ?? this.severities),
    sources: Set.unmodifiable(sources ?? this.sources),
    query: query ?? this.query,
    selectedEventId: identical(selectedEventId, _notProvided)
        ? this.selectedEventId
        : selectedEventId as String?,
  );

  Map<String, Object?> toJson() => {
    'isOpen': isOpen,
    'frozen': frozen,
    'kindFilter': kindFilter.name,
    'severities': severities.map((severity) => severity.name).toList(),
    'sources': sources.toList(),
    'hasQuery': query.isNotEmpty,
  };
}

const Object _notProvided = Object();
final Object _operationZoneKey = Object();
final Object _correlationZoneKey = Object();
final Object _generationZoneKey = Object();
int _correlationSequence = 0;

/// Nonthrowing, process-wide entry point for operational error reporting.
abstract class DiagnosticsSink {
  static DiagnosticsSink _current = const _NoopDiagnosticsSink();

  static DiagnosticsSink get current => _current;

  /// Installs [sink] and returns a binding which restores the previous sink.
  static DiagnosticsSinkBinding install(DiagnosticsSink sink) {
    final previous = _current;
    _current = sink;
    return DiagnosticsSinkBinding._(sink, previous);
  }

  static String? get currentOperation =>
      Zone.current[_operationZoneKey] as String?;

  static String? get currentCorrelationId =>
      Zone.current[_correlationZoneKey] as String?;

  static String newCorrelationId([String prefix = 'operation']) {
    _correlationSequence += 1;
    return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
        '$_correlationSequence';
  }

  /// Runs [body] in a zone inherited by all asynchronous work it starts.
  static T runOperation<T>(
    String operation,
    T Function() body, {
    String? correlationId,
  }) {
    final inheritedGeneration = Zone.current[_generationZoneKey] as int?;
    final installed = _current;
    final generation =
        inheritedGeneration ??
        (installed is DiagnosticsController ? installed._generation : null);
    final zoneValues = <Object?, Object?>{
      _operationZoneKey: operation,
      _correlationZoneKey:
          correlationId ?? newCorrelationId(_safeIdentifier(operation)),
    };
    if (generation != null) {
      zoneValues[_generationZoneKey] = generation;
    }
    return runZoned(body, zoneValues: zoneValues);
  }

  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  });

  /// Records a sanitized structured log without allowing diagnostics failures
  /// to affect the operation being observed.
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  });
}

final class DiagnosticsSinkBinding {
  DiagnosticsSinkBinding._(this._installed, this._previous);

  final DiagnosticsSink _installed;
  final DiagnosticsSink _previous;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (identical(DiagnosticsSink._current, _installed)) {
      DiagnosticsSink._current = _previous;
    }
  }
}

final class _NoopDiagnosticsSink implements DiagnosticsSink {
  const _NoopDiagnosticsSink();

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {}

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}
}

/// App-owned diagnostics state. It is independent of any connected site.
final class DiagnosticsController
    implements DiagnosticsSink, HttpDiagnosticsRecorder {
  DiagnosticsController._({
    required this._persistence,
    required this._clock,
    required this._timerFactory,
    required this.sessionId,
    required this._durablePersistenceUnavailable,
    required int initialSequence,
    required this._lastSeenSequence,
    required List<DiagnosticEvent> events,
  }) : _sequence = initialSequence,
       _events = events.toList(),
       _eventsNotifier = FrameSafeValueNotifier(List.unmodifiable(events)),
       _panelStateNotifier = FrameSafeValueNotifier(DiagnosticsPanelState()),
       _panelOpenNotifier = FrameSafeValueNotifier(false),
       _unseenErrorCountNotifier = FrameSafeValueNotifier(0) {
    _rebuildEventSizes();
  }

  static const Duration ordinaryWriteDelay = Duration(milliseconds: 150);
  static const int reportFormatVersion = 1;

  final DiagnosticsPersistence _persistence;
  final DateTime Function() _clock;
  final DiagnosticsTimerFactory _timerFactory;
  final List<DiagnosticEvent> _events;
  final FrameSafeValueNotifier<List<DiagnosticEvent>> _eventsNotifier;
  final FrameSafeValueNotifier<DiagnosticsPanelState> _panelStateNotifier;
  final FrameSafeValueNotifier<bool> _panelOpenNotifier;
  final FrameSafeValueNotifier<int> _unseenErrorCountNotifier;
  final Map<String, int> _httpGenerations = {};
  final Map<String, int> _eventBytes = {};
  final List<(DiagnosticEvent, int)> _pendingWrites = [];

  Expando<Object> _reportedErrorEpochs = Expando<Object>(
    'diagnostics reported error epochs',
  );
  Object _errorDedupEpoch = Object();
  bool _errorEpochRotationScheduled = false;
  Future<void> _persistenceTail = Future<void>.value();
  Timer? _writeTimer;
  Timer? _expiryTimer;
  List<DiagnosticEvent>? _frozenEvents;
  int _sequence;
  int _lastSeenSequence;
  int _totalEventBytes = 0;
  int _generation = 0;
  bool _persistenceFailed = false;
  bool _closed = false;
  Future<void>? _closeTask;
  bool _closeSettled = false;
  final bool _durablePersistenceUnavailable;

  final String sessionId;

  static Future<DiagnosticsController> create({
    DiagnosticsPersistence? persistence,
    Future<DiagnosticsPersistence> Function()? persistenceFactory,
    DateTime Function()? clock,
    DiagnosticsTimerFactory? timerFactory,
    String? sessionId,
  }) async {
    final resolvedClock = clock ?? _utcNow;
    DiagnosticsPersistence resolvedPersistence;
    Object? persistenceError;
    StackTrace? persistenceStack;
    var durablePersistenceUnavailable = false;
    if (persistence != null) {
      resolvedPersistence = persistence;
    } else {
      try {
        resolvedPersistence =
            await (persistenceFactory?.call() ??
                FileDiagnosticsPersistence.applicationSupport());
      } on Object catch (error, stackTrace) {
        resolvedPersistence = MemoryDiagnosticsPersistence();
        durablePersistenceUnavailable = true;
        persistenceError = error;
        persistenceStack = stackTrace;
      }
    }

    DiagnosticsPersistenceState stored;
    try {
      stored = await resolvedPersistence.load(nowUtc: resolvedClock());
    } on Object catch (error, stackTrace) {
      // Keep the failed persistence as a clear-only recovery delegate. A
      // confirmed Clear must still get a chance to delete an unreadable JSONL
      // file instead of silently clearing only this fallback memory store.
      resolvedPersistence = _LoadFailureFallbackPersistence(
        resolvedPersistence,
      );
      stored = const DiagnosticsPersistenceState();
      persistenceError = error;
      persistenceStack = stackTrace;
    }

    final maxSequence = stored.events.fold(
      stored.lastSeenSequence,
      (maximum, event) => event.sequence > maximum ? event.sequence : maximum,
    );
    final controller = DiagnosticsController._(
      persistence: resolvedPersistence,
      clock: resolvedClock,
      timerFactory: timerFactory ?? Timer.new,
      sessionId: sessionId ?? _newSessionId(resolvedClock()),
      durablePersistenceUnavailable: durablePersistenceUnavailable,
      initialSequence: maxSequence,
      lastSeenSequence: stored.lastSeenSequence,
      events: stored.events,
    );
    controller._initializePreviousSession();
    controller._recordSessionStart();
    controller._updateUnseenCount();
    if (persistenceError != null) {
      controller._recordPersistenceFailure(
        persistenceError,
        persistenceStack ?? StackTrace.empty,
      );
    }
    await controller.flush();
    controller._queuePersistence(
      () => resolvedPersistence.compact(nowUtc: resolvedClock()),
      generation: controller._generation,
    );
    await controller.flush();
    return controller;
  }

  ValueListenable<List<DiagnosticEvent>> get eventsListenable =>
      _eventsNotifier;

  List<DiagnosticEvent> get events => _eventsNotifier.value;

  ValueListenable<DiagnosticsPanelState> get panelStateListenable =>
      _panelStateNotifier;

  /// Compatibility listenable for entry points that only care open/closed.
  ValueListenable<bool> get panelListenable => _panelOpenNotifier;

  bool get isPanelOpen => _panelStateNotifier.value.isOpen;

  ValueListenable<int> get unseenErrorCountListenable =>
      _unseenErrorCountNotifier;

  ValueListenable<int> get unseenErrorsListenable => _unseenErrorCountNotifier;

  DiagnosticsPanelState get panelState => _panelStateNotifier.value;

  @override
  String? get currentOperationId => DiagnosticsSink.currentOperation;

  List<DiagnosticEvent> get visibleEvents {
    final state = panelState;
    final query = state.query.trim().toLowerCase();
    final sourceEvents = _frozenEvents ?? events;
    return List.unmodifiable(
      sourceEvents.where((event) {
        if (state.kindFilter == DiagnosticsKindFilter.requests &&
            event is! HttpDiagnosticEvent) {
          return false;
        }
        if (state.kindFilter == DiagnosticsKindFilter.errors &&
            !event.isError) {
          return false;
        }
        if (state.severities.isNotEmpty &&
            !state.severities.contains(event.severity)) {
          return false;
        }
        if (state.sources.isNotEmpty && !state.sources.contains(event.source)) {
          return false;
        }
        return query.isEmpty || event.searchText.contains(query);
      }),
    );
  }

  void openPanel() {
    _setPanelState(panelState.copyWith(isOpen: true));
    if (!panelState.frozen) markSeen();
  }

  void closePanel() => _setPanelState(panelState.copyWith(isOpen: false));

  void togglePanel() => isPanelOpen ? closePanel() : openPanel();

  void setFrozen(bool frozen) {
    if (frozen == panelState.frozen) return;
    _frozenEvents = frozen ? List.unmodifiable(events) : null;
    _setPanelState(panelState.copyWith(frozen: frozen));
    if (!frozen && isPanelOpen) markSeen();
  }

  void setKindFilter(DiagnosticsKindFilter filter) =>
      _setPanelState(panelState.copyWith(kindFilter: filter));

  void setSeverities(Set<DiagnosticSeverity> severities) =>
      _setPanelState(panelState.copyWith(severities: severities));

  void setSources(Set<String> sources) =>
      _setPanelState(panelState.copyWith(sources: sources));

  void setQuery(String query) =>
      _setPanelState(panelState.copyWith(query: query));

  void selectEvent(String? eventId) =>
      _setPanelState(panelState.copyWith(selectedEventId: eventId));

  void markSeen() {
    final latestErrorSequence = _events.where((event) => event.isError).fold(
      _lastSeenSequence,
      (latest, event) {
        return event.sequence > latest ? event.sequence : latest;
      },
    );
    if (latestErrorSequence == _lastSeenSequence &&
        _unseenErrorCountNotifier.value == 0) {
      return;
    }
    _lastSeenSequence = latestErrorSequence;
    _unseenErrorCountNotifier.value = 0;
    _queuePersistence(
      () => _persistence.writeLastSeenSequence(latestErrorSequence),
      generation: _generation,
    );
  }

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    if (_closed) return;
    try {
      final operationGeneration = Zone.current[_generationZoneKey] as int?;
      if (operationGeneration != null && operationGeneration != _generation) {
        return;
      }
      final now = _clock().toUtc();
      var diagnosticError = error;
      var diagnosticStackTrace = stackTrace;
      // A small bound makes even a hostile/cyclic custom implementation safe.
      for (var depth = 0; depth < 8; depth += 1) {
        if (diagnosticError is! DiagnosticErrorCause) break;
        final cause = diagnosticError.diagnosticCause;
        if (identical(cause, diagnosticError)) break;
        diagnosticStackTrace =
            diagnosticError.diagnosticCauseStackTrace ?? diagnosticStackTrace;
        diagnosticError = cause;
      }
      if (_wasReportedThisMicrotask(diagnosticError)) return;
      final event = ErrorDiagnosticEvent(
        id: _newEventId('error', now),
        sessionId: sessionId,
        sequence: _nextSequence(),
        timestampUtc: now,
        updatedAtUtc: now,
        severity: severity,
        source: DiagnosticsRedactor.scrub(source),
        operation: DiagnosticsRedactor.scrub(
          operation ?? DiagnosticsSink.currentOperation,
        ).nullIfEmpty,
        correlationId: DiagnosticsRedactor.scrub(
          correlationId ?? DiagnosticsSink.currentCorrelationId,
        ).nullIfEmpty,
        handled: handled,
        degraded: degraded,
        errorType: diagnosticError.runtimeType.toString(),
        message: _safeErrorMessage(diagnosticError),
        stackTrace: diagnosticStackTrace.toString(),
      );
      _record(event, persistImmediately: true);
    } on Object {
      // Diagnostics must never change the behavior of the operation reporting.
    }
  }

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {
    if (_closed) return;
    try {
      final operationGeneration = Zone.current[_generationZoneKey] as int?;
      if (operationGeneration != null && operationGeneration != _generation) {
        return;
      }
      final now = _clock().toUtc();
      final event = DiagnosticLogEvent(
        id: _newEventId('log', now),
        sessionId: sessionId,
        sequence: _nextSequence(),
        timestampUtc: now,
        updatedAtUtc: now,
        severity: severity,
        source: source,
        operation: operation ?? DiagnosticsSink.currentOperation,
        correlationId: correlationId ?? DiagnosticsSink.currentCorrelationId,
        handled: handled,
        degraded: degraded,
        name: name,
        component: component,
        message: message,
        attributes: attributes,
      );
      _record(event, persistImmediately: event.isError);
    } on Object {
      // Logging is observational and must stay independent of producer health.
    }
  }

  @override
  void recordHttp(HttpDiagnosticRecord update) {
    if (_closed) return;
    try {
      final generation = switch (update.phase) {
        HttpDiagnosticPhase.started => _generation,
        _ => _httpGenerations[update.eventId],
      };
      if (generation == null || generation != _generation) return;
      if (update.phase == HttpDiagnosticPhase.started) {
        _httpGenerations[update.eventId] = generation;
      }

      final existing = _eventById(update.eventId);
      final state = switch (update.phase) {
        HttpDiagnosticPhase.started ||
        HttpDiagnosticPhase.responseHeaders => DiagnosticHttpState.pending,
        HttpDiagnosticPhase.completed => DiagnosticHttpState.completed,
        HttpDiagnosticPhase.failed => DiagnosticHttpState.failed,
        HttpDiagnosticPhase.cancelled => DiagnosticHttpState.cancelled,
      };
      final severity = update.isError
          ? DiagnosticSeverity.error
          : DiagnosticSeverity.info;
      final now = update.timestamp.toUtc();
      final redirects = [
        for (final redirect in update.redirects)
          DiagnosticRedirect(
            statusCode: redirect.statusCode,
            method: redirect.method,
            location: redirect.location,
          ),
      ];
      final responseHeaders = {
        for (final entry in update.responseHeaders.entries)
          entry.key: [entry.value],
      };
      final sequence = existing == null || (!existing.isError && update.isError)
          ? _nextSequence()
          : existing.sequence;
      final event = HttpDiagnosticEvent(
        id: update.eventId,
        sessionId: existing?.sessionId ?? sessionId,
        sequence: sequence,
        timestampUtc: existing?.timestampUtc ?? now,
        updatedAtUtc: now,
        severity: severity,
        operation:
            existing?.operation ??
            DiagnosticsRedactor.scrub(update.operationId).nullIfEmpty,
        correlationId:
            existing?.correlationId ?? DiagnosticsSink.currentCorrelationId,
        method: update.method,
        uri: update.uri,
        state: state,
        statusCode: update.statusCode,
        reasonPhrase: update.reasonPhrase,
        redirects: redirects,
        responseHeaders: responseHeaders,
        headerDuration: update.headerDuration,
        totalDuration: update.totalDuration,
        sentBytes: update.sentBytes,
        receivedBytes: update.receivedBytes,
        errorType: update.errorType,
        errorMessage: update.errorMessage,
        stackTrace: update.stackTrace,
      );
      _record(event, generation: generation, persistImmediately: event.isError);
      if (state != DiagnosticHttpState.pending) {
        _httpGenerations.remove(update.eventId);
      }
    } on Object {
      // HTTP must remain entirely independent from diagnostics health.
    }
  }

  String formatEvent(DiagnosticEvent event) =>
      const JsonEncoder.withIndent('  ').convert(event.toJson());

  String buildJsonReport([Iterable<DiagnosticEvent>? events]) {
    final selected = events?.toList() ?? visibleEvents;
    final sessionIds = <String>{
      sessionId,
      for (final event in selected) event.sessionId,
    }.toList();
    return const JsonEncoder.withIndent('  ').convert({
      'version': reportFormatVersion,
      'generatedAtUtc': _clock().toUtc().toIso8601String(),
      'app': {
        'version': AppRelease.version,
        'buildChannel': AppRelease.buildChannel,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'platform': defaultTargetPlatform.name,
      },
      'session': {'currentId': sessionId, 'ids': sessionIds},
      'privacy': {
        'requestBodiesRecorded': false,
        'responseBodiesRecorded': false,
        'requestHeaderValuesRecorded': false,
        'queryValuesRecorded': false,
      },
      'scope': {
        'captured': [
          'in-process Dart HTTP',
          'Flutter framework errors',
          'root-isolate platform errors',
          'reported operational errors',
          'reported structured application logs',
        ],
        'excluded': [
          'external browser and web-auth traffic',
          'native-plugin-internal networking',
          'spawned isolates without the HTTP override',
          'native process crashes',
        ],
      },
      'filter': panelState.toJson(),
      'events': [for (final event in selected) event.toJson()],
    });
  }

  Future<void> clear() async {
    if (_closed) return;
    _generation += 1;
    _writeTimer?.cancel();
    _writeTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _pendingWrites.clear();
    _httpGenerations.clear();
    // Clear starts a new diagnostics generation. If persistence fails again
    // (especially while deleting an unreadable old file), surface a fresh
    // memory-only warning rather than leaving the panel deceptively empty.
    _persistenceFailed = false;
    _resetErrorDeduplication();
    _events.clear();
    _eventBytes.clear();
    _totalEventBytes = 0;
    _frozenEvents = panelState.frozen ? const [] : null;
    _lastSeenSequence = _sequence;
    _eventsNotifier.value = const [];
    _unseenErrorCountNotifier.value = 0;
    selectEvent(null);
    final generation = _generation;
    _queuePersistence(_persistence.clear, generation: generation);
    await flush();
    if (_durablePersistenceUnavailable && !_closed) {
      _recordPersistenceFailure(
        StateError('Application support storage remains unavailable.'),
        StackTrace.empty,
      );
    }
  }

  Future<void> flush() async {
    _flushPendingWrites();
    await _persistenceTail;
  }

  Future<void> close() {
    final active = _closeTask;
    if (active != null && !_closeSettled) return active;
    if (_closed) return Future<void>.value();

    // Publish the shared future before beginning cleanup. A listener notified
    // by the session-end event may itself call close; it must join this close,
    // not start a second one.
    final completion = Completer<void>();
    _closeTask = completion.future;
    unawaited(
      _performClose().then<void>(
        (_) {
          _closeSettled = true;
          completion.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          _closeSettled = true;
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _performClose() async {
    final now = _clock().toUtc();
    _record(
      DiagnosticSessionEvent(
        id: _newEventId('session', now),
        sessionId: sessionId,
        sequence: _nextSequence(),
        timestampUtc: now,
        updatedAtUtc: now,
        state: DiagnosticSessionState.ended,
      ),
    );
    _closed = true;
    _resetErrorDeduplication();
    _expiryTimer?.cancel();
    _expiryTimer = null;

    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> stage(Future<void> Function() cleanup) async {
      try {
        await cleanup();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    void disposeNotifier(ChangeNotifier notifier) {
      try {
        notifier.dispose();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await stage(flush);
    await stage(_persistence.close);
    disposeNotifier(_eventsNotifier);
    disposeNotifier(_panelStateNotifier);
    disposeNotifier(_panelOpenNotifier);
    disposeNotifier(_unseenErrorCountNotifier);

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  void _initializePreviousSession() {
    final now = _clock().toUtc();
    for (var index = 0; index < _events.length; index += 1) {
      final event = _events[index];
      if (event is! HttpDiagnosticEvent ||
          event.state != DiagnosticHttpState.pending ||
          event.sessionId == sessionId) {
        continue;
      }
      final interrupted = event.copyWith(
        sequence: _nextSequence(),
        updatedAtUtc: now,
        severity: DiagnosticSeverity.warning,
        state: DiagnosticHttpState.interrupted,
        totalDuration: now.difference(event.timestampUtc),
      );
      _events[index] = interrupted;
      _schedulePersist(interrupted);
    }
    _events.sort((left, right) => left.sequence.compareTo(right.sequence));
    _rebuildEventSizes();
    _publishEvents(now);
  }

  void _recordSessionStart() {
    final now = _clock().toUtc();
    _record(
      DiagnosticSessionEvent(
        id: _newEventId('session', now),
        sessionId: sessionId,
        sequence: _nextSequence(),
        timestampUtc: now,
        updatedAtUtc: now,
        state: DiagnosticSessionState.started,
      ),
    );
  }

  void _record(
    DiagnosticEvent event, {
    int? generation,
    bool persistImmediately = false,
  }) {
    final eventGeneration = generation ?? _generation;
    if (eventGeneration != _generation || _closed) return;
    _putEvent(event);
    _publishEvents(_clock());
    if (_isShowingLiveEvents && event.isError) {
      markSeen();
    } else {
      _updateUnseenCount();
    }
    _schedulePersist(
      event,
      generation: eventGeneration,
      immediately: persistImmediately,
    );
  }

  void _publishEvents(DateTime nowUtc) {
    final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
    for (var index = _events.length - 1; index >= 0; index -= 1) {
      if (!_events[index].timestampUtc.isAfter(cutoff)) {
        _removeEventAt(index, invalidateHttp: true);
      }
    }
    while (_events.length > diagnosticsRetentionCount ||
        _totalEventBytes > diagnosticsEventBudgetBytes) {
      if (_events.isEmpty) break;
      _removeEventAt(0, invalidateHttp: true);
    }
    _pruneFrozenEvents();
    _eventsNotifier.value = List.unmodifiable(_events);
    final selected = panelState.selectedEventId;
    if (selected != null && !_events.any((event) => event.id == selected)) {
      selectEvent(null);
    }
    _scheduleExpiry(nowUtc);
  }

  void _pruneFrozenEvents() {
    final frozen = _frozenEvents;
    if (frozen == null) return;
    final retainedIds = _events.map((event) => event.id).toSet();
    _frozenEvents = List.unmodifiable(
      frozen.where((event) => retainedIds.contains(event.id)),
    );
  }

  void _scheduleExpiry(DateTime nowUtc) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_closed || _events.isEmpty) return;
    var oldest = _events.first.timestampUtc;
    for (final event in _events.skip(1)) {
      if (event.timestampUtc.isBefore(oldest)) oldest = event.timestampUtc;
    }
    final delay = oldest
        .add(diagnosticsRetentionAge)
        .difference(nowUtc.toUtc());
    _expiryTimer = _timerFactory(
      delay.isNegative ? Duration.zero : delay,
      _expireHistory,
    );
  }

  void _expireHistory() {
    _expiryTimer = null;
    if (_closed) return;
    final before = _events.length;
    final now = _clock().toUtc();
    _publishEvents(now);
    _updateUnseenCount();
    if (_events.length != before) {
      _queuePersistence(
        () => _persistence.compact(nowUtc: now),
        generation: _generation,
      );
    }
  }

  void _updateUnseenCount() {
    _unseenErrorCountNotifier.value = _events
        .where((event) => event.isError && event.sequence > _lastSeenSequence)
        .length;
  }

  bool get _isShowingLiveEvents => isPanelOpen && !panelState.frozen;

  void _setPanelState(DiagnosticsPanelState state) {
    _panelStateNotifier.value = state;
    _panelOpenNotifier.value = state.isOpen;
  }

  HttpDiagnosticEvent? _eventById(String eventId) {
    for (final event in _events.reversed) {
      if (event.id == eventId && event is HttpDiagnosticEvent) return event;
    }
    return null;
  }

  void _putEvent(DiagnosticEvent event) {
    final existingIndex = _events.indexWhere((item) => item.id == event.id);
    if (existingIndex >= 0) {
      _removeEventAt(existingIndex);
    }
    final bytes = diagnosticEventSerializedBytes(event);
    _events.insert(_insertionIndexFor(event.sequence), event);
    _eventBytes[event.id] = bytes;
    _totalEventBytes += bytes;
  }

  int _insertionIndexFor(int sequence) {
    var lower = 0;
    var upper = _events.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_events[middle].sequence <= sequence) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower;
  }

  void _removeEventAt(int index, {bool invalidateHttp = false}) {
    final removed = _events.removeAt(index);
    if (invalidateHttp && removed is HttpDiagnosticEvent) {
      // A hard retention eviction is also the end of this recorder's interest
      // in the transaction. Otherwise an old pending request could finish
      // later and recreate itself after TTL/count/size eviction.
      _httpGenerations.remove(removed.id);
    }
    final bytes = _eventBytes.remove(removed.id);
    if (bytes != null) _totalEventBytes -= bytes;
  }

  void _rebuildEventSizes() {
    _eventBytes.clear();
    _totalEventBytes = 0;
    for (final event in _events) {
      final bytes = diagnosticEventSerializedBytes(event);
      _eventBytes[event.id] = bytes;
      _totalEventBytes += bytes;
    }
  }

  int _nextSequence() => ++_sequence;

  bool _wasReportedThisMicrotask(Object error) {
    try {
      if (identical(_reportedErrorEpochs[error], _errorDedupEpoch)) return true;
      // Expando keys are weak. Diagnostics can mark a FormatException without
      // keeping its source, response body, or credential-bearing object alive.
      _reportedErrorEpochs[error] = _errorDedupEpoch;
    } on Object {
      // Primitive thrown values cannot be Expando keys. Do not retain them
      // strongly merely to suppress an unusual adjacent duplicate.
      return false;
    }
    if (!_errorEpochRotationScheduled) {
      _errorEpochRotationScheduled = true;
      scheduleMicrotask(() {
        _errorDedupEpoch = Object();
        _errorEpochRotationScheduled = false;
      });
    }
    return false;
  }

  void _resetErrorDeduplication() {
    _reportedErrorEpochs = Expando<Object>('diagnostics reported error epochs');
    _errorDedupEpoch = Object();
    _errorEpochRotationScheduled = false;
  }

  String _safeErrorMessage(Object error) {
    if (error is FormatException) {
      final offset = error.offset;
      return DiagnosticsRedactor.scrub(
        offset == null ? error.message : '${error.message} (offset $offset)',
      );
    }
    return DiagnosticsRedactor.safeString(error);
  }

  String _newEventId(String prefix, DateTime now) =>
      '$sessionId-$prefix-${now.microsecondsSinceEpoch}-${_nextIdSuffix()}';

  void _schedulePersist(
    DiagnosticEvent event, {
    int? generation,
    bool immediately = false,
  }) {
    _pendingWrites.add((event, generation ?? _generation));
    if (immediately) {
      _flushPendingWrites();
      return;
    }
    _writeTimer ??= Timer(ordinaryWriteDelay, _flushPendingWrites);
  }

  void _flushPendingWrites() {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (_pendingWrites.isEmpty) return;
    final writes = List<(DiagnosticEvent, int)>.of(_pendingWrites);
    _pendingWrites.clear();
    final batches = <int, List<DiagnosticEvent>>{};
    for (final (event, generation) in writes) {
      (batches[generation] ??= []).add(event);
    }
    for (final MapEntry(key: generation, value: events) in batches.entries) {
      _queuePersistence(
        () => _persistence.appendEvents(events, nowUtc: _clock()),
        generation: generation,
      );
    }
  }

  void _queuePersistence(
    Future<void> Function() operation, {
    required int generation,
  }) {
    _persistenceTail = _persistenceTail.then((_) async {
      if (generation != _generation) return;
      try {
        await operation();
      } on Object catch (error, stackTrace) {
        if (generation == _generation) {
          _recordPersistenceFailure(error, stackTrace);
        }
      }
    });
  }

  void _recordPersistenceFailure(Object error, StackTrace stackTrace) {
    if (_persistenceFailed || _closed) return;
    _persistenceFailed = true;
    final now = _clock().toUtc();
    final warning = ErrorDiagnosticEvent(
      id: _newEventId('persistence', now),
      sessionId: sessionId,
      sequence: _nextSequence(),
      timestampUtc: now,
      updatedAtUtc: now,
      severity: DiagnosticSeverity.warning,
      source: 'diagnostics',
      operation: 'persist diagnostics',
      handled: true,
      degraded: true,
      errorType: error.runtimeType.toString(),
      message:
          'Diagnostics persistence is unavailable; history is memory-only. '
          '${_safeErrorMessage(error)}',
      stackTrace: stackTrace.toString(),
    );
    _putEvent(warning);
    _publishEvents(now);
    if (_isShowingLiveEvents) {
      markSeen();
    } else {
      _updateUnseenCount();
    }
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

DateTime _utcNow() => DateTime.now().toUtc();

int _eventIdSuffix = 0;

int _nextIdSuffix() => ++_eventIdSuffix;

String _newSessionId(DateTime now) =>
    'session-${now.toUtc().microsecondsSinceEpoch}-${_nextIdSuffix()}';

String _safeIdentifier(String input) {
  final safe = input.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
  return safe.replaceAll(RegExp(r'^-+|-+$'), '').nullIfEmpty ?? 'operation';
}

/// Memory-only after a load failure, while retaining the failed backend solely
/// so a later confirmed Clear can retry deleting its on-disk history.
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
      // The original backend is already known to be unavailable.
    }
    await _memory.close();
  }
}
