import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/app_release.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_error_cause.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_redactor.dart';
import 'package:discourse_native/src/diagnostics/recording_http.dart';
import 'package:discourse_native/src/foundation/frame_safe_notifier.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/foundation.dart';

export 'diagnostic_event.dart' show DiagnosticSeverity;

enum DiagnosticsKindFilter { all, requests, errors }

typedef DiagnosticsTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// A retained event and what it costs against the size budget.
typedef _RetainedEvent = ({DiagnosticEvent event, int bytes});

/// The published view of the recorder's history.
///
/// Copying the history is what makes a published snapshot immutable while the
/// recorder keeps mutating its own list, but the history changes several times
/// per request and is read at most once per frame — and not at all while the
/// panel is closed. So the copy is deferred to the read.
///
/// This is not weaker than copying eagerly: every mutation invalidates, so a
/// materialized snapshot is only ever handed out for the state that is current
/// when it is asked for, and it is never the list that goes on changing.
final class _EventHistoryListenable extends FrameSafeNotifier
    implements ValueListenable<List<DiagnosticEvent>> {
  _EventHistoryListenable(this._history);

  final List<DiagnosticEvent> _history;
  List<DiagnosticEvent>? _published;

  @override
  List<DiagnosticEvent> get value => _published ??= List.unmodifiable(_history);

  void invalidate() {
    _published = null;
    notifySafely();
  }
}

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

typedef _DiagnosticsGeneration = ({
  DiagnosticsController controller,
  int generation,
});

/// The app-owned diagnostics authority made available to plugin lifecycles.
///
/// Keeping this key beside the capability avoids making the generic plugin host
/// API depend on diagnostics implementation details. App lifecycles must still
/// declare the port through `addAppLifecycle(..., requires: ...)`; the runtime
/// supplies a consumer-restricted binding before startup.
const pluginDiagnosticsReporterPort =
    PluginHostPortKey<PluginDiagnosticsReporter>(
      owner: PluginId('core'),
      name: 'diagnostics-reporter',
    );

/// Diagnostics operations which plugin code may perform.
///
/// A fixed reporter always writes to the sink it was constructed with, even if
/// the process-wide compatibility sink later changes. Its operation zones also
/// carry that controller's identity and generation, so work begun before a
/// clear cannot reappear afterward and cannot leak into another controller
/// whose numeric generation happens to match. A resolving reporter gives a
/// composition root the same stable capability while it replaces its owned
/// recorder, without consulting the ambient compatibility sink.
final class PluginDiagnosticsReporter {
  PluginDiagnosticsReporter.fixed(DiagnosticsSink sink)
    : _fixedSink = sink,
      _sinkResolver = null,
      _usesAmbientSink = false;

  const PluginDiagnosticsReporter.ambient()
    : _fixedSink = null,
      _sinkResolver = null,
      _usesAmbientSink = true;

  const PluginDiagnosticsReporter.noop()
    : _fixedSink = null,
      _sinkResolver = null,
      _usesAmbientSink = false;

  PluginDiagnosticsReporter.resolving(DiagnosticsSink? Function() sinkResolver)
    : _fixedSink = null,
      _sinkResolver = sinkResolver,
      _usesAmbientSink = false;

  final DiagnosticsSink? _fixedSink;
  final DiagnosticsSink? Function()? _sinkResolver;
  final bool _usesAmbientSink;

  DiagnosticsSink? get _sink =>
      _sinkResolver?.call() ??
      (_usesAmbientSink ? DiagnosticsSink.current : _fixedSink);

  String? get currentOperation => DiagnosticsSink.currentOperation;

  String? get currentCorrelationId => DiagnosticsSink.currentCorrelationId;

  String newCorrelationId([String prefix = 'operation']) =>
      _newDiagnosticCorrelationId(prefix);

  T runOperation<T>(
    String operation,
    T Function() body, {
    String? correlationId,
  }) => _runDiagnosticOperation(
    _sink,
    operation,
    body,
    correlationId: correlationId,
  );

  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) => _sink?.reportError(
    error,
    stackTrace,
    operation: operation,
    source: source,
    severity: severity,
    handled: handled,
    degraded: degraded,
    correlationId: correlationId,
  );

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
  }) => _sink?.recordLog(
    name: name,
    source: source,
    component: component,
    message: message,
    attributes: attributes,
    severity: severity,
    operation: operation,
    correlationId: correlationId,
    handled: handled,
    degraded: degraded,
  );
}

/// Immutable diagnostics history and export operations exposed to plugin UI.
///
/// This is deliberately a wrapper rather than the controller typed as an
/// interface. A plugin therefore cannot cast the value back to
/// [DiagnosticsController] and clear history, mutate panel state, report new
/// events, flush persistence, or close the app-owned recorder.
final class PluginDiagnosticsReadExportHost {
  PluginDiagnosticsReadExportHost(this._controller)
    : _eventsListenable = _PluginDiagnosticsEventsListenable(
        _controller.eventsListenable,
      );

  final DiagnosticsController _controller;
  final ValueListenable<List<DiagnosticEvent>> _eventsListenable;

  ValueListenable<List<DiagnosticEvent>> get eventsListenable =>
      _eventsListenable;

  List<DiagnosticEvent> get events => _controller.events;

  String formatEvent(DiagnosticEvent event) => _controller.formatEvent(event);

  String buildJsonReport([Iterable<DiagnosticEvent>? events]) =>
      _controller.buildJsonReport(events);
}

/// A deliberately shallow forwarding view over the controller's notifier.
///
/// The plugin can subscribe and read, but cannot downcast this object to the
/// controller-owned ChangeNotifier and dispose or otherwise mutate it.
final class _PluginDiagnosticsEventsListenable
    implements ValueListenable<List<DiagnosticEvent>> {
  const _PluginDiagnosticsEventsListenable(this._source);

  final ValueListenable<List<DiagnosticEvent>> _source;

  @override
  List<DiagnosticEvent> get value => _source.value;

  @override
  void addListener(VoidCallback listener) => _source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _source.removeListener(listener);
}

/// Nonthrowing, process-wide entry point for operational error reporting.
abstract class DiagnosticsSink {
  static DiagnosticsSink _current = const _NoopDiagnosticsSink();
  static DiagnosticsSinkBinding? _binding;

  static DiagnosticsSink get current => _current;

  /// Installs [sink] and returns a binding which restores the previous sink.
  static DiagnosticsSinkBinding install(DiagnosticsSink sink) {
    final previous = _current;
    final active = _binding;
    final previousBinding =
        active != null && identical(previous, active._installed)
        ? active
        : null;
    final binding = DiagnosticsSinkBinding._(sink, previous, previousBinding);
    _current = sink;
    _binding = binding;
    return binding;
  }

  static String? get currentOperation =>
      Zone.current[_operationZoneKey] as String?;

  static String? get currentCorrelationId =>
      Zone.current[_correlationZoneKey] as String?;

  static String newCorrelationId([String prefix = 'operation']) =>
      _newDiagnosticCorrelationId(prefix);

  /// Runs [body] in a zone inherited by all asynchronous work it starts.
  static T runOperation<T>(
    String operation,
    T Function() body, {
    String? correlationId,
  }) => _runDiagnosticOperation(
    _current,
    operation,
    body,
    correlationId: correlationId,
  );

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
  DiagnosticsSinkBinding._(
    this._installed,
    this._previous,
    this._previousBinding,
  );

  final DiagnosticsSink _installed;
  final DiagnosticsSink _previous;
  final DiagnosticsSinkBinding? _previousBinding;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (!identical(DiagnosticsSink._binding, this)) return;

    // Sink identity cannot establish ownership: the same sink may be installed
    // twice. The binding token does, and lets a newer binding skip any older
    // bindings that were closed out of order while it was still active.
    var previous = _previous;
    var binding = _previousBinding;
    while (binding != null && binding._closed) {
      previous = binding._previous;
      binding = binding._previousBinding;
    }
    DiagnosticsSink._binding = binding;
    DiagnosticsSink._current = binding?._installed ?? previous;
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

String _newDiagnosticCorrelationId(String prefix) {
  _correlationSequence += 1;
  return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
      '$_correlationSequence';
}

T _runDiagnosticOperation<T>(
  DiagnosticsSink? sink,
  String operation,
  T Function() body, {
  String? correlationId,
}) {
  final inherited = Zone.current[_generationZoneKey] as _DiagnosticsGeneration?;
  final generation = switch (sink) {
    final DiagnosticsController controller
        when identical(inherited?.controller, controller) =>
      inherited,
    final DiagnosticsController controller => (
      controller: controller,
      generation: controller._generation,
    ),
    _ => null,
  };
  final zoneValues = <Object?, Object?>{
    _operationZoneKey: operation,
    _correlationZoneKey:
        correlationId ??
        _newDiagnosticCorrelationId(_safeIdentifier(operation)),
  };
  if (generation != null) zoneValues[_generationZoneKey] = generation;
  return runZoned(body, zoneValues: zoneValues);
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
       _panelStateNotifier = FrameSafeValueNotifier(DiagnosticsPanelState()),
       _panelOpenNotifier = FrameSafeValueNotifier(false),
       _unseenErrorCountNotifier = FrameSafeValueNotifier(0) {
    _reindexEvents();
  }

  static const Duration ordinaryWriteDelay = Duration(milliseconds: 150);
  static const int reportFormatVersion = 1;

  final DiagnosticsPersistence _persistence;
  final DateTime Function() _clock;
  final DiagnosticsTimerFactory _timerFactory;
  final List<DiagnosticEvent> _events;
  late final _EventHistoryListenable _eventsNotifier = _EventHistoryListenable(
    _events,
  );
  final FrameSafeValueNotifier<DiagnosticsPanelState> _panelStateNotifier;
  final FrameSafeValueNotifier<bool> _panelOpenNotifier;
  final FrameSafeValueNotifier<int> _unseenErrorCountNotifier;
  final Map<String, int> _httpGenerations = {};

  /// The retained events by id, mirroring [_events] exactly.
  ///
  /// [_events] is ordered — by sequence, so the panel reads a stable timeline —
  /// and this is the index onto it. Every hot path here is keyed by id and
  /// runs per HTTP phase, three times a request: without the index each of
  /// them walks the whole retained history, which is thousands of events on a
  /// session that has been up for a while.
  final Map<String, _RetainedEvent> _byId = {};

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
  int _unseenErrorCount = 0;

  /// The oldest [DiagnosticEvent.timestampUtc] held, or null when that is not
  /// currently known. Age retention is the only reader, and it asks on every
  /// recorded event; recomputing it is a full scan, so it is kept rather than
  /// derived. An update reuses the timestamp of the event it replaces, so only
  /// eviction can invalidate it.
  DateTime? _oldestTimestamp;
  bool _oldestTimestampKnown = true;

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
    // Ascending by sequence, so the newest error is the last one in the list.
    var latestErrorSequence = _lastSeenSequence;
    for (var index = _events.length - 1; index >= 0; index -= 1) {
      final event = _events[index];
      if (event.sequence <= latestErrorSequence) break;
      if (event.isError) {
        latestErrorSequence = event.sequence;
        break;
      }
    }
    if (latestErrorSequence == _lastSeenSequence && _unseenErrorCount == 0) {
      return;
    }
    _lastSeenSequence = latestErrorSequence;
    _unseenErrorCount = 0;
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
      final operationGeneration =
          Zone.current[_generationZoneKey] as _DiagnosticsGeneration?;
      if (operationGeneration != null &&
          (!identical(operationGeneration.controller, this) ||
              operationGeneration.generation != _generation)) {
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
      final operationGeneration =
          Zone.current[_generationZoneKey] as _DiagnosticsGeneration?;
      if (operationGeneration != null &&
          (!identical(operationGeneration.controller, this) ||
              operationGeneration.generation != _generation)) {
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
    _byId.clear();
    _totalEventBytes = 0;
    _unseenErrorCount = 0;
    _oldestTimestamp = null;
    _oldestTimestampKnown = true;
    _frozenEvents = panelState.frozen ? const [] : null;
    _lastSeenSequence = _sequence;
    _eventsNotifier.invalidate();
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
    _reindexEvents();
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
    // Every recorded event asks whether anything has aged out. Almost always
    // nothing has, and the oldest timestamp answers that without walking the
    // history; only once it is past the cutoff is a sweep worth the walk.
    final oldest = _oldestEventTimestamp();
    if (oldest != null && !oldest.isAfter(cutoff)) {
      for (var index = _events.length - 1; index >= 0; index -= 1) {
        if (!_events[index].timestampUtc.isAfter(cutoff)) {
          _removeEventAt(index, invalidateHttp: true);
        }
      }
    }
    while (_events.length > diagnosticsRetentionCount ||
        _totalEventBytes > diagnosticsEventBudgetBytes) {
      if (_events.isEmpty) break;
      _removeEventAt(0, invalidateHttp: true);
    }
    _pruneFrozenEvents();
    _eventsNotifier.invalidate();
    final selected = panelState.selectedEventId;
    if (selected != null && !_byId.containsKey(selected)) {
      selectEvent(null);
    }
    _scheduleExpiry(nowUtc);
  }

  void _pruneFrozenEvents() {
    final frozen = _frozenEvents;
    if (frozen == null) return;
    _frozenEvents = List.unmodifiable(
      frozen.where((event) => _byId.containsKey(event.id)),
    );
  }

  void _scheduleExpiry(DateTime nowUtc) {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_closed || _events.isEmpty) return;
    final oldest = _oldestEventTimestamp();
    if (oldest == null) return;
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
    _unseenErrorCountNotifier.value = _unseenErrorCount;
  }

  void _recountUnseenErrors() {
    var unseen = 0;
    // Ascending by sequence, so everything unseen is a suffix: walk back from
    // the newest and stop at the first event the reader has already seen.
    for (var index = _events.length - 1; index >= 0; index -= 1) {
      final event = _events[index];
      if (event.sequence <= _lastSeenSequence) break;
      if (event.isError) unseen += 1;
    }
    _unseenErrorCount = unseen;
  }

  bool get _isShowingLiveEvents => isPanelOpen && !panelState.frozen;

  void _setPanelState(DiagnosticsPanelState state) {
    _panelStateNotifier.value = state;
    _panelOpenNotifier.value = state.isOpen;
  }

  HttpDiagnosticEvent? _eventById(String eventId) {
    final event = _byId[eventId]?.event;
    return event is HttpDiagnosticEvent ? event : null;
  }

  void _putEvent(DiagnosticEvent event) {
    final existing = _byId[event.id];
    if (existing != null) {
      final index = _indexOf(existing.event);
      // The index and the list are written together, so the row is always
      // there. Diagnostics still must not be the thing that throws: recording
      // an event is on the path of whatever it is observing.
      if (index >= 0) {
        _removeEventAt(index);
      } else {
        _forget(existing.event);
      }
    }
    final bytes = diagnosticEventSerializedBytes(event);
    _events.insert(_insertionIndexFor(event.sequence), event);
    _byId[event.id] = (event: event, bytes: bytes);
    _totalEventBytes += bytes;
    if (event.isError && event.sequence > _lastSeenSequence) {
      _unseenErrorCount += 1;
    }
    final oldest = _oldestTimestamp;
    if (oldest == null || event.timestampUtc.isBefore(oldest)) {
      _oldestTimestamp = event.timestampUtc;
    }
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

  /// Where [event] sits in [_events], which is ascending by sequence.
  ///
  /// Sequences are all but unique — only an update reuses one, and it replaces
  /// the event it took it from — so the equal-sequence walk is bounded in
  /// practice, and the scan is a guard for a history that somehow is not
  /// ordered rather than an expected cost.
  int _indexOf(DiagnosticEvent event) {
    var lower = 0;
    var upper = _events.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_events[middle].sequence < event.sequence) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    for (
      var index = lower;
      index < _events.length && _events[index].sequence == event.sequence;
      index += 1
    ) {
      if (_events[index].id == event.id) return index;
    }
    return _events.indexWhere((item) => item.id == event.id);
  }

  void _removeEventAt(int index, {bool invalidateHttp = false}) {
    final removed = _events.removeAt(index);
    if (invalidateHttp && removed is HttpDiagnosticEvent) {
      // A hard retention eviction is also the end of this recorder's interest
      // in the transaction. Otherwise an old pending request could finish
      // later and recreate itself after TTL/count/size eviction.
      _httpGenerations.remove(removed.id);
    }
    _forget(removed);
  }

  /// Drops everything [_events] is indexed by for one event.
  void _forget(DiagnosticEvent removed) {
    final retained = _byId.remove(removed.id);
    if (retained != null) _totalEventBytes -= retained.bytes;
    if (removed.isError && removed.sequence > _lastSeenSequence) {
      _unseenErrorCount -= 1;
    }
    if (_oldestTimestamp == removed.timestampUtc) _oldestTimestampKnown = false;
  }

  /// The oldest retained timestamp, recomputed only when an eviction dropped
  /// the event that held it.
  DateTime? _oldestEventTimestamp() {
    if (_oldestTimestampKnown) return _oldestTimestamp;
    DateTime? oldest;
    for (final event in _events) {
      if (oldest == null || event.timestampUtc.isBefore(oldest)) {
        oldest = event.timestampUtc;
      }
    }
    _oldestTimestamp = oldest;
    _oldestTimestampKnown = true;
    return oldest;
  }

  /// Rebuilds everything derived from [_events], for the paths that rewrite it
  /// in place rather than through [_putEvent] and [_removeEventAt].
  void _reindexEvents() {
    _byId.clear();
    _totalEventBytes = 0;
    DateTime? oldest;
    for (final event in _events) {
      final bytes = diagnosticEventSerializedBytes(event);
      _byId[event.id] = (event: event, bytes: bytes);
      _totalEventBytes += bytes;
      if (oldest == null || event.timestampUtc.isBefore(oldest)) {
        oldest = event.timestampUtc;
      }
    }
    _oldestTimestamp = oldest;
    _oldestTimestampKnown = true;
    _recountUnseenErrors();
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
