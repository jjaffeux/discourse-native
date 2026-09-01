// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'resenha_diagnostics_models.dart';
import 'resenha_diagnostics_persistence.dart';

export 'package:discourse_native/discourse_plugin_sdk.dart'
    show DiagnosticSeverity;

export 'resenha_diagnostics_models.dart';
export 'resenha_diagnostics_persistence.dart';

final Set<String> _liveResenhaDiagnosticsWriterIds = {};

typedef ResenhaDiagnosticsTimerFactory =
    Timer Function(Duration duration, void Function() callback);

abstract interface class ResenhaDiagnosticsRecorder {
  bool get captureEnabled;

  /// Records a structured event in the ordinary diagnostics timeline and,
  /// while capture is enabled, in the bounded deep-capture history.
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  });

  /// Records verbose vendor or transport detail only during explicit capture.
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  });
}

/// The recorder itself is app-scoped and must not be closed by an individual
/// plugin session. A session can still await its final records reaching that
/// recorder's persistence boundary before its own lifecycle completes.
abstract interface class ResenhaDiagnosticsFlusher {
  Future<void> flushDiagnostics();
}

final class NoopResenhaDiagnosticsRecorder
    implements ResenhaDiagnosticsRecorder {
  const NoopResenhaDiagnosticsRecorder();

  @override
  bool get captureEnabled => false;

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {}

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {}
}

/// Native composition installs bridges at controller creation. They are only
/// active between [ResenhaDiagnosticsController.startCapture] and
/// [ResenhaDiagnosticsController.stopCapture]. A bridge should feed vendor
/// lines to [ResenhaDiagnosticsRecorder.recordRaw].
abstract interface class ResenhaDiagnosticsSdkLogBridge {
  FutureOr<void> install(ResenhaDiagnosticsRecorder recorder);

  FutureOr<void> uninstall();
}

typedef ResenhaDiagnosticsSdkLogInstaller =
    FutureOr<void> Function(ResenhaDiagnosticsRecorder recorder);
typedef ResenhaDiagnosticsSdkLogUninstaller = FutureOr<void> Function();

final class CallbackResenhaDiagnosticsSdkLogBridge
    implements ResenhaDiagnosticsSdkLogBridge {
  const CallbackResenhaDiagnosticsSdkLogBridge({
    required ResenhaDiagnosticsSdkLogInstaller install,
    required ResenhaDiagnosticsSdkLogUninstaller uninstall,
  }) : _install = install,
       _uninstall = uninstall;

  final ResenhaDiagnosticsSdkLogInstaller _install;
  final ResenhaDiagnosticsSdkLogUninstaller _uninstall;

  @override
  FutureOr<void> install(ResenhaDiagnosticsRecorder recorder) =>
      _install(recorder);

  @override
  FutureOr<void> uninstall() => _uninstall();
}

final class ResenhaDiagnosticsController implements ResenhaDiagnosticsRecorder {
  ResenhaDiagnosticsController._({
    required this._reporter,
    required this._persistence,
    required this._clock,
    required this._timerFactory,
    required this._captureIdFactory,
    required this._eventsTailLimit,
    required this._eventsTailBytesLimit,
    required this._pendingWritesBytesLimit,
    required this._writerId,
    required this._sdkLogBridges,
    required this._homeDirectory,
    required this._durableStorageUnavailable,
    required ResenhaDiagnosticsPersistenceState stored,
  }) : _records = ListQueue(),
       _retainedBytes = stored.retainedBytes,
       _oldestRetainedTimestampUtc = stored.oldestTimestampUtc,
       _sequence = 0,
       _state = ResenhaDiagnosticsState(
         retainedBytes: stored.retainedBytes,
         droppedRecords: stored.droppedRecords,
         truncated: stored.truncated,
       ),
       _stateNotifier = ValueNotifier(
         ResenhaDiagnosticsState(
           retainedBytes: stored.retainedBytes,
           droppedRecords: stored.droppedRecords,
           truncated: stored.truncated,
         ),
       ),
       _eventsNotifier = ValueNotifier(const []) {
    for (final record in stored.records.reversed) {
      final bytes = resenhaDiagnosticSerializedBytes(record);
      if (_records.length >= _eventsTailLimit ||
          _eventsTailBytes + bytes > _eventsTailBytesLimit) {
        break;
      }
      _records.addFirst(record);
      _eventsTailBytes += bytes;
    }
    _lastRecordTimestampUtc = stored.records.lastOrNull?.timestampUtc;
    _eventsDirty = true;
    _publishUiNow();
    _scheduleRetentionExpiry();
  }

  static const int defaultEventsTailLimit = 2000;
  static const int defaultEventsTailBytesLimit = 10 * 1024 * 1024;
  static const int defaultPendingWritesBytesLimit = 10 * 1024 * 1024;
  static const int pendingControlReserveBytes = 1024 * 1024;
  static const int maximumRetainedEventIdCandidates = 5000;
  static const int reportFormatVersion = 1;
  static const Duration ordinaryWriteDelay = Duration(milliseconds: 150);
  static const Duration ordinaryUiPublishDelay = Duration(milliseconds: 100);
  static const Duration retentionRetryDelay = Duration(minutes: 1);

  final PluginDiagnosticsReporter _reporter;
  final ResenhaDiagnosticsPersistence _persistence;
  final DateTime Function() _clock;
  final ResenhaDiagnosticsTimerFactory _timerFactory;
  final String Function() _captureIdFactory;
  final int _eventsTailLimit;
  final int _eventsTailBytesLimit;
  final int _pendingWritesBytesLimit;
  final String _writerId;
  final List<ResenhaDiagnosticsSdkLogBridge> _sdkLogBridges;
  final String? _homeDirectory;
  final bool _durableStorageUnavailable;
  ResenhaDiagnosticsState _state;
  final ValueNotifier<ResenhaDiagnosticsState> _stateNotifier;
  final ValueNotifier<List<ResenhaDiagnosticRecord>> _eventsNotifier;
  final ValueNotifier<bool> _captureEnabledNotifier = ValueNotifier(false);
  final ListQueue<ResenhaDiagnosticRecord> _records;
  final ListQueue<ResenhaDiagnosticRecord> _pendingWrites = ListQueue();
  final List<ResenhaDiagnosticsSdkLogBridge> _installedSdkLogBridges = [];

  Future<void> _persistenceTail = Future<void>.value();
  Future<void> _lifecycleTail = Future<void>.value();
  Timer? _writeTimer;
  Timer? _eventsPublishTimer;
  Timer? _retentionExpiryTimer;
  bool _eventsDirty = false;
  bool _stateDirty = false;
  bool _closed = false;
  int _sequence;
  int _retainedBytes;
  int _eventsTailBytes = 0;
  int _pendingWritesBytes = 0;
  DateTime? _oldestRetainedTimestampUtc;
  bool _writeWorkerActive = false;
  DateTime? _lastRecordTimestampUtc;

  static Future<ResenhaDiagnosticsController> create({
    PluginDiagnosticsReporter reporter = const PluginDiagnosticsReporter.noop(),
    ResenhaDiagnosticsPersistence? persistence,
    Future<ResenhaDiagnosticsPersistence> Function()? persistenceFactory,
    DateTime Function()? clock,
    ResenhaDiagnosticsTimerFactory? timerFactory,
    String Function()? captureIdFactory,
    int eventsTailLimit = defaultEventsTailLimit,
    int eventsTailBytesLimit = defaultEventsTailBytesLimit,
    int pendingWritesBytesLimit = defaultPendingWritesBytesLimit,
    String Function()? writerIdFactory,
    Iterable<ResenhaDiagnosticsSdkLogBridge> sdkLogBridges = const [],
    String? homeDirectory,
  }) async {
    if (eventsTailLimit <= 0) {
      throw ArgumentError.value(
        eventsTailLimit,
        'eventsTailLimit',
        'Must be greater than zero.',
      );
    }
    if (eventsTailBytesLimit <= 0) {
      throw ArgumentError.value(
        eventsTailBytesLimit,
        'eventsTailBytesLimit',
        'Must be greater than zero.',
      );
    }
    if (pendingWritesBytesLimit <= 0) {
      throw ArgumentError.value(
        pendingWritesBytesLimit,
        'pendingWritesBytesLimit',
        'Must be greater than zero.',
      );
    }
    final resolvedClock = clock ?? _utcNow;
    final writerId = ResenhaDiagnosticsRedactor.scrub(
      (writerIdFactory ?? _newWriterId)(),
      homeDirectory: homeDirectory,
      maximumLength: 256,
    );
    ResenhaDiagnosticsPersistence resolvedPersistence;
    Object? persistenceError;
    String? persistenceErrorOperation;
    var durableStorageUnavailable = false;
    try {
      resolvedPersistence =
          persistence ??
          await (persistenceFactory?.call() ??
              FileResenhaDiagnosticsPersistence.applicationSupport());
    } on Object catch (error) {
      resolvedPersistence = MemoryResenhaDiagnosticsPersistence();
      durableStorageUnavailable = true;
      persistenceError = error;
      persistenceErrorOperation = 'resenha.deep_capture.create';
    }

    ResenhaDiagnosticsPersistenceState stored;
    try {
      stored = await resolvedPersistence.load(nowUtc: resolvedClock());
    } on Object catch (error) {
      stored = const ResenhaDiagnosticsPersistenceState();
      persistenceError = error;
      persistenceErrorOperation = 'resenha.deep_capture.load';
    }
    final controller = ResenhaDiagnosticsController._(
      reporter: reporter,
      persistence: resolvedPersistence,
      clock: resolvedClock,
      timerFactory: timerFactory ?? Timer.new,
      captureIdFactory: captureIdFactory ?? _newCaptureId,
      eventsTailLimit: eventsTailLimit,
      eventsTailBytesLimit: eventsTailBytesLimit,
      pendingWritesBytesLimit: pendingWritesBytesLimit,
      writerId: writerId,
      sdkLogBridges: List.unmodifiable(sdkLogBridges),
      homeDirectory: homeDirectory,
      durableStorageUnavailable: durableStorageUnavailable,
      stored: stored,
    );
    _liveResenhaDiagnosticsWriterIds.add(writerId);
    if (persistenceError != null) {
      controller._reportPersistenceError(
        persistenceError,
        operation: persistenceErrorOperation ?? 'resenha.deep_capture.create',
      );
    }
    final outstandingCaptures = stored.activeCaptures.isNotEmpty
        ? stored.activeCaptures.values
        : [
            if (stored.activeCaptureId case final captureId?)
              ResenhaDiagnosticsActiveCapture(
                writerId: 'legacy',
                captureId: captureId,
                startedAtUtc:
                    stored.activeCaptureStartedAtUtc ?? resolvedClock(),
              ),
          ];
    for (final outstanding in outstandingCaptures) {
      if (_isResenhaDiagnosticsWriterAlive(outstanding.writerId)) continue;
      controller._recordCaptured(
        event: 'capture.interrupted',
        component: 'capture',
        severity: DiagnosticSeverity.warning,
        correlationId: null,
        message: 'The previous capture ended without a stop marker.',
        data: {
          'startedAtUtc': outstanding.startedAtUtc.toUtc().toIso8601String(),
        },
        captureId: outstanding.captureId,
      );
    }
    await controller.flush();
    return controller;
  }

  ValueListenable<ResenhaDiagnosticsState> get stateListenable =>
      _stateNotifier;

  ValueListenable<List<ResenhaDiagnosticRecord>> get eventsListenable =>
      _eventsNotifier;

  ValueListenable<bool> get captureEnabledListenable => _captureEnabledNotifier;

  ResenhaDiagnosticsState get state => _state;

  List<ResenhaDiagnosticRecord> get events => _eventsNotifier.value;

  List<ResenhaDiagnosticRecord> get eventsTail => events;

  @override
  bool get captureEnabled => !_closed && _captureEnabledNotifier.value;

  Future<void> startCapture() => _serializeLifecycle(_startCapture);

  Future<void> _startCapture() async {
    if (_closed || state.enabled) return;
    final startedAtUtc = _clock().toUtc();
    final captureId = ResenhaDiagnosticsRedactor.scrub(
      _captureIdFactory(),
      homeDirectory: _homeDirectory,
      maximumLength: 256,
    );
    _setState(
      state.copyWith(
        enabled: true,
        captureId: captureId,
        startedAtUtc: startedAtUtc,
      ),
      publishImmediately: true,
    );
    _captureEnabledNotifier.value = true;
    _recordCaptured(
      event: 'capture.started',
      component: 'capture',
      severity: DiagnosticSeverity.info,
      correlationId: null,
      message: null,
      data: {'formatVersion': resenhaDiagnosticsFormatVersion},
      captureId: captureId,
      timestampUtc: startedAtUtc,
    );
    try {
      for (final bridge in _sdkLogBridges) {
        try {
          await bridge.install(this);
          _installedSdkLogBridges.add(bridge);
        } on Object catch (error, stackTrace) {
          _recordBridgeFailure('install', error, stackTrace);
          try {
            await bridge.uninstall();
          } on Object catch (unwindError, unwindStackTrace) {
            _recordBridgeFailure(
              'install_unwind',
              unwindError,
              unwindStackTrace,
            );
          }
        }
      }
      await flush();
    } on Object {
      await _stopCapture();
      rethrow;
    }
  }

  Future<void> stopCapture() => _serializeLifecycle(_stopCapture);

  Future<void> _stopCapture() async {
    if (_closed || (!state.enabled && _installedSdkLogBridges.isEmpty)) return;
    final captureId = state.captureId;
    final installed = _installedSdkLogBridges.reversed.toList();
    _installedSdkLogBridges.clear();
    for (final bridge in installed) {
      try {
        await bridge.uninstall();
      } on Object catch (error, stackTrace) {
        _recordBridgeFailure('uninstall', error, stackTrace);
      }
    }
    if (captureId != null) {
      _recordCaptured(
        event: 'capture.stopped',
        component: 'capture',
        severity: DiagnosticSeverity.info,
        correlationId: null,
        message: null,
        data: const {},
        captureId: captureId,
      );
    }
    _setState(
      state.copyWith(enabled: false, captureId: null, startedAtUtc: null),
      publishImmediately: true,
    );
    _captureEnabledNotifier.value = false;
    await flush();
  }

  @override
  void record(
    String event, {
    String component = 'runtime',
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? correlationId,
    Map<String, Object?> data = const {},
  }) {
    if (_closed) return;
    final safeEvent = ResenhaDiagnosticsRedactor.scrub(
      event,
      homeDirectory: _homeDirectory,
      maximumLength: 1024,
    );
    final safeComponent = ResenhaDiagnosticsRedactor.scrub(
      component,
      homeDirectory: _homeDirectory,
      maximumLength: 1024,
    );
    final safeCorrelationId = correlationId == null
        ? null
        : ResenhaDiagnosticsRedactor.scrub(
            correlationId,
            homeDirectory: _homeDirectory,
            maximumLength: 4096,
          );
    final safeData = ResenhaDiagnosticsRedactor.data(
      data,
      homeDirectory: _homeDirectory,
    );
    final eventId = _reporter.newCorrelationId('resenha-event');
    final attributedData = <String, Object?>{
      ...safeData,
      resenhaDiagnosticsEventIdField: eventId,
    };
    try {
      _reporter.recordLog(
        name: safeEvent,
        source: 'resenha',
        component: safeComponent,
        attributes: attributedData,
        severity: severity,
        correlationId: safeCorrelationId,
      );
    } on Object {
      // Reporting failures must not prevent deep capture.
    }
    if (!state.enabled) return;
    _recordCaptured(
      event: safeEvent,
      component: safeComponent,
      severity: severity,
      correlationId: safeCorrelationId,
      message: null,
      data: attributedData,
      captureId: state.captureId!,
    );
  }

  @override
  void recordRaw(
    String event, {
    String component = 'sdk',
    DiagnosticSeverity severity = DiagnosticSeverity.debug,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
  }) {
    if (_closed || !state.enabled) return;
    final rawData = Map<String, Object?>.of(data)
      ..remove(resenhaDiagnosticsEventIdField);
    _recordCaptured(
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: message,
      data: rawData,
      captureId: state.captureId!,
    );
  }

  Future<void> clear() => _serializeLifecycle(_clear);

  Future<void> _clear() async {
    if (_closed) return;
    if (_durableStorageUnavailable) {
      final error = StateError(
        'Durable Resenha diagnostics storage is unavailable; deletion cannot '
        'be confirmed.',
      );
      _reportPersistenceError(error, operation: 'resenha.deep_capture.clear');
      throw error;
    }
    _retentionExpiryTimer?.cancel();
    _retentionExpiryTimer = null;
    await flush();
    try {
      await _persistence.clear();
    } on Object catch (error, stackTrace) {
      _reportPersistenceError(error, operation: 'resenha.deep_capture.clear');
      _scheduleRetentionExpiry();
      Error.throwWithStackTrace(error, stackTrace);
    }
    _records.clear();
    _pendingWrites.clear();
    _eventsTailBytes = 0;
    _pendingWritesBytes = 0;
    _retainedBytes = 0;
    _oldestRetainedTimestampUtc = null;
    _setState(
      state.copyWith(retainedBytes: 0, droppedRecords: 0, truncated: false),
      publishImmediately: true,
    );
    _eventsDirty = true;
    _publishUiNow();
    if (state.enabled) {
      _recordCaptured(
        event: 'capture.started',
        component: 'capture',
        severity: DiagnosticSeverity.info,
        correlationId: null,
        message: null,
        data: const {'resumedAfterClear': true},
        captureId: state.captureId!,
      );
      await flush();
    }
  }

  Future<void> flush() async {
    await _drainPendingWrites();
    await _persistenceTail;
    try {
      await _persistence.flush();
    } on Object catch (error, stackTrace) {
      _markPersistenceFailure(error, stackTrace, 'flush');
    }
    _publishUiNow();
  }

  /// Builds clipboard- and file-friendly JSONL: one header followed by one
  /// independently parseable chronological record per line.
  Future<String> buildJsonReport() async {
    final generatedAtUtc = await _prepareJsonReport();
    return _persistence.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state.toJson(),
    );
  }

  /// Writes the deep JSONL report incrementally when the durable store supports
  /// it. This is intended for file export; [output] remains caller-owned.
  Future<void> writeJsonReportTo(StringSink output) async {
    final generatedAtUtc = await _prepareJsonReport();
    final persistence = _persistence;
    if (persistence is StreamingResenhaDiagnosticsPersistence) {
      final streaming = persistence as StreamingResenhaDiagnosticsPersistence;
      await streaming.writeJsonReportTo(
        output,
        generatedAtUtc: generatedAtUtc,
        reportFormatVersion: reportFormatVersion,
        state: state.toJson(),
      );
      return;
    }
    output.write(
      await persistence.buildJsonReport(
        generatedAtUtc: generatedAtUtc,
        reportFormatVersion: reportFormatVersion,
        state: state.toJson(),
      ),
    );
  }

  /// Selects retained event identifiers and streams the exact same deep-report
  /// snapshot to the sink returned by [outputForRetainedEventIds].
  ///
  /// Durable persistence keeps selection and streaming inside one file lock.
  /// A persistence without snapshot streaming falls back to one materialized
  /// report and derives identifiers from that immutable report string.
  Future<void> writeJsonReportSnapshotTo({
    required Iterable<String> candidateEventIds,
    required ResenhaDiagnosticsReportSinkFactory outputForRetainedEventIds,
  }) async {
    final candidates = _validatedRetainedEventIdCandidates(candidateEventIds);
    final generatedAtUtc = await _prepareJsonReport();
    final persistence = _persistence;
    final stateSnapshot = state.toJson();
    if (persistence is SnapshotStreamingResenhaDiagnosticsPersistence) {
      final streaming =
          persistence as SnapshotStreamingResenhaDiagnosticsPersistence;
      await streaming.writeJsonReportSnapshotTo(
        candidateEventIds: candidates,
        outputForRetainedEventIds: outputForRetainedEventIds,
        generatedAtUtc: generatedAtUtc,
        reportFormatVersion: reportFormatVersion,
        state: stateSnapshot,
      );
      return;
    }

    final report = await persistence.buildJsonReport(
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: stateSnapshot,
    );
    final retainedEventIds = resenhaDiagnosticsEventIdsInJsonReport(
      report,
      candidates: candidates,
    );
    final output = outputForRetainedEventIds(
      Set<String>.unmodifiable(retainedEventIds),
    );
    output.write(report);
  }

  Future<Set<String>> findRetainedEventIds(
    Iterable<String> candidateIds,
  ) async {
    final candidates = _validatedRetainedEventIdCandidates(candidateIds);
    if (candidates.isEmpty) return const {};
    await flush();
    final nowUtc = _clock().toUtc();
    final persisted = await _persistence.compact(nowUtc: nowUtc);
    _adoptPersistenceState(persisted);
    _publishUiNow();
    final persistence = _persistence;
    if (persistence is! RetainedResenhaDiagnosticsEventIdsPersistence) {
      throw UnsupportedError(
        '${persistence.runtimeType} cannot scan retained event identifiers.',
      );
    }
    return (persistence as RetainedResenhaDiagnosticsEventIdsPersistence)
        .findRetainedEventIds(candidates, nowUtc: nowUtc);
  }

  Set<String> _validatedRetainedEventIdCandidates(
    Iterable<String> candidateIds,
  ) {
    final candidates = <String>{};
    for (final candidate in candidateIds) {
      candidates.add(candidate);
      if (candidates.length > maximumRetainedEventIdCandidates) {
        throw ArgumentError.value(
          candidateIds,
          'candidateIds',
          'At most $maximumRetainedEventIdCandidates unique IDs are allowed.',
        );
      }
    }
    return candidates;
  }

  Future<DateTime> _prepareJsonReport() async {
    await flush();
    final generatedAtUtc = _clock().toUtc();
    final persisted = await _persistence.compact(nowUtc: generatedAtUtc);
    _adoptPersistenceState(persisted);
    _publishUiNow();
    return generatedAtUtc;
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    return _serializeLifecycle(_close);
  }

  Future<void> _close() async {
    if (_closed) return;
    if (state.enabled || _installedSdkLogBridges.isNotEmpty) {
      await _stopCapture();
    }
    _retentionExpiryTimer?.cancel();
    _retentionExpiryTimer = null;
    _closed = true;
    await flush();
    try {
      await _persistence.close();
    } on Object catch (error) {
      _reportPersistenceError(error, operation: 'resenha.deep_capture.close');
    }
    _eventsNotifier.dispose();
    _stateNotifier.dispose();
    _captureEnabledNotifier.dispose();
    _writeTimer?.cancel();
    _eventsPublishTimer?.cancel();
    _liveResenhaDiagnosticsWriterIds.remove(_writerId);
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final current = _lifecycleTail.then<void>((_) => operation());
    _lifecycleTail = current.then<void>(
      (_) {},
      // A caller receives its lifecycle error; later cleanup still runs.
      onError: (Object _, StackTrace _) {},
    );
    return current;
  }

  void _recordCaptured({
    required String event,
    required String component,
    required DiagnosticSeverity severity,
    required String? correlationId,
    required String? message,
    required Map<String, Object?> data,
    required String captureId,
    DateTime? timestampUtc,
  }) {
    if (_closed) return;
    var recordTimestampUtc = (timestampUtc ?? _clock()).toUtc();
    final lastTimestampUtc = _lastRecordTimestampUtc;
    if (lastTimestampUtc != null &&
        recordTimestampUtc.isBefore(lastTimestampUtc)) {
      recordTimestampUtc = lastTimestampUtc;
    }
    _lastRecordTimestampUtc = recordTimestampUtc;
    final record = fitResenhaDiagnosticRecord(
      ResenhaDiagnosticRecord(
        writerId: _writerId,
        sequence: ++_sequence,
        timestampUtc: recordTimestampUtc,
        captureId: captureId,
        event: event,
        component: component,
        severity: severity,
        correlationId: correlationId,
        message: message,
        data: data,
        homeDirectory: _homeDirectory,
      ),
    );
    final recordBytes = resenhaDiagnosticSerializedBytes(record);
    final controlRecord = _isCaptureControlRecord(record);
    var evicted = 0;
    if (controlRecord) {
      final controlLimit =
          _pendingWritesBytesLimit + pendingControlReserveBytes;
      while (_pendingWritesBytes + recordBytes > controlLimit) {
        final disposable = _pendingWrites
            .where((pending) => !_isCaptureControlRecord(pending))
            .firstOrNull;
        if (disposable == null) break;
        _pendingWrites.remove(disposable);
        final disposableBytes = resenhaDiagnosticSerializedBytes(disposable);
        _pendingWritesBytes -= disposableBytes;
        _retainedBytes -= disposableBytes;
        if (_records.remove(disposable)) {
          _eventsTailBytes -= disposableBytes;
        }
        evicted += 1;
      }
    }
    final pendingLimit = controlRecord
        ? _pendingWritesBytesLimit + pendingControlReserveBytes
        : _pendingWritesBytesLimit;
    if (_pendingWritesBytes + recordBytes > pendingLimit) {
      _setState(
        state.copyWith(
          droppedRecords: state.droppedRecords + evicted + 1,
          truncated: true,
        ),
      );
      return;
    }
    _records.addLast(record);
    _eventsTailBytes += recordBytes;
    while (_records.length > _eventsTailLimit ||
        _eventsTailBytes > _eventsTailBytesLimit) {
      _eventsTailBytes -= resenhaDiagnosticSerializedBytes(
        _records.removeFirst(),
      );
    }
    _retainedBytes += recordBytes;
    _setState(
      state.copyWith(
        retainedBytes: _retainedBytes,
        droppedRecords: state.droppedRecords + evicted,
        truncated: state.truncated || record.truncated || evicted > 0,
      ),
    );
    _scheduleEventsPublish();
    _pendingWrites.add(record);
    _pendingWritesBytes += recordBytes;
    _scheduleWrite();
  }

  void _scheduleEventsPublish() {
    _eventsDirty = true;
    _scheduleUiPublish();
  }

  void _setState(
    ResenhaDiagnosticsState next, {
    bool publishImmediately = false,
  }) {
    _state = next;
    _stateDirty = true;
    if (publishImmediately) {
      _publishUiNow();
    } else {
      _scheduleUiPublish();
    }
  }

  void _scheduleUiPublish() {
    if (_eventsPublishTimer != null) return;
    _eventsPublishTimer = Timer(ordinaryUiPublishDelay, _publishUiNow);
  }

  void _scheduleRetentionExpiry({Duration? retryDelay}) {
    _retentionExpiryTimer?.cancel();
    _retentionExpiryTimer = null;
    final oldest = _oldestRetainedTimestampUtc;
    if (_closed || oldest == null || _retainedBytes <= 0) return;
    final nowUtc = _clock().toUtc();
    final untilExpiry = oldest
        .add(resenhaDiagnosticsRetentionAge)
        .difference(nowUtc);
    final delay =
        retryDelay ?? (untilExpiry.isNegative ? Duration.zero : untilExpiry);
    _retentionExpiryTimer = _timerFactory(delay, _expireRetainedHistory);
  }

  void _expireRetainedHistory() {
    _retentionExpiryTimer = null;
    if (_closed) return;
    unawaited(_serializeLifecycle(_compactExpiredHistory));
  }

  Future<void> _compactExpiredHistory() async {
    if (_closed) return;
    try {
      await flush();
      final persisted = await _persistence.compact(nowUtc: _clock().toUtc());
      _adoptPersistenceState(persisted);
      _publishUiNow();
    } on Object catch (error, stackTrace) {
      _markPersistenceFailure(
        error,
        stackTrace,
        'retention',
        droppedRecords: 0,
      );
      _scheduleRetentionExpiry(retryDelay: retentionRetryDelay);
      _publishUiNow();
    }
  }

  void _publishUiNow() {
    _eventsPublishTimer?.cancel();
    _eventsPublishTimer = null;
    if (_stateDirty) {
      _stateDirty = false;
      _stateNotifier.value = _state;
    }
    if (_eventsDirty) {
      _eventsDirty = false;
      _eventsNotifier.value = List.unmodifiable(_records);
    }
  }

  void _scheduleWrite() {
    if (_writeTimer != null) return;
    _writeTimer = Timer(ordinaryWriteDelay, () {
      _writeTimer = null;
      unawaited(_drainPendingWrites());
    });
  }

  Future<void> _drainPendingWrites() {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (_writeWorkerActive || _pendingWrites.isEmpty) return _persistenceTail;
    _writeWorkerActive = true;
    _persistenceTail = _runWriteWorker();
    return _persistenceTail;
  }

  Future<void> _runWriteWorker() async {
    try {
      while (_pendingWrites.isNotEmpty) {
        final batch = List<ResenhaDiagnosticRecord>.of(_pendingWrites);
        _pendingWrites.clear();
        _pendingWritesBytes = 0;
        try {
          final persisted = await _persistence.append(batch, nowUtc: _clock());
          _adoptPersistenceState(persisted);
        } on Object catch (error, stackTrace) {
          _dropFailedBatch(batch);
          _markPersistenceFailure(
            error,
            stackTrace,
            'append',
            droppedRecords: batch.length,
          );
        }
      }
    } finally {
      _writeWorkerActive = false;
    }
  }

  void _dropFailedBatch(List<ResenhaDiagnosticRecord> batch) {
    for (final record in batch) {
      final bytes = resenhaDiagnosticSerializedBytes(record);
      _retainedBytes = max(0, _retainedBytes - bytes);
      if (_records.remove(record)) _eventsTailBytes -= bytes;
    }
    _scheduleEventsPublish();
  }

  void _adoptPersistenceState(ResenhaDiagnosticsPersistenceState persisted) {
    final persistedLastIdentity = persisted.records.lastOrNull?.identity;
    if (_pendingWrites.isEmpty &&
        (persistedLastIdentity == null ||
            persistedLastIdentity == _records.lastOrNull?.identity)) {
      _records.clear();
      _eventsTailBytes = 0;
      for (final record in persisted.records.reversed) {
        final bytes = resenhaDiagnosticSerializedBytes(record);
        if (_records.length >= _eventsTailLimit ||
            _eventsTailBytes + bytes > _eventsTailBytesLimit) {
          break;
        }
        _records.addFirst(record);
        _eventsTailBytes += bytes;
      }
      _lastRecordTimestampUtc = persisted.records.lastOrNull?.timestampUtc;
      _scheduleEventsPublish();
    }
    _oldestRetainedTimestampUtc = persisted.oldestTimestampUtc;
    _retainedBytes = persisted.retainedBytes + _pendingWritesBytes;
    _setState(
      state.copyWith(
        retainedBytes: _retainedBytes,
        droppedRecords: max(state.droppedRecords, persisted.droppedRecords),
        truncated: state.truncated || persisted.truncated,
      ),
    );
    _scheduleRetentionExpiry();
  }

  void _markPersistenceFailure(
    Object error,
    StackTrace _,
    String phase, {
    int droppedRecords = 1,
  }) {
    if (!_closed) {
      _setState(
        state.copyWith(
          retainedBytes: _retainedBytes,
          droppedRecords: state.droppedRecords + droppedRecords,
          truncated: true,
        ),
      );
    }
    _reportPersistenceError(error, operation: 'resenha.deep_capture.$phase');
  }

  void _reportPersistenceError(Object error, {required String operation}) {
    try {
      _reporter.reportError(
        _SafeResenhaDiagnosticsFailure(
          operation: operation,
          originalType: '${error.runtimeType}',
        ),
        StackTrace.empty,
        operation: operation,
        source: 'resenha',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
    } on Object {
      // Reporting failure must not replace the persistence failure.
    }
  }

  void _recordBridgeFailure(String phase, Object error, StackTrace stackTrace) {
    _recordCaptured(
      event: 'sdk_log_bridge.$phase.failed',
      component: 'sdk',
      severity: DiagnosticSeverity.warning,
      correlationId: null,
      message: '$error',
      data: {'stackTrace': '$stackTrace'},
      captureId: state.captureId!,
    );
    _reportPersistenceError(
      error,
      operation: 'resenha.deep_capture.sdk_bridge.$phase',
    );
  }
}

final class _SafeResenhaDiagnosticsFailure implements Exception {
  const _SafeResenhaDiagnosticsFailure({
    required this.operation,
    required this.originalType,
  });

  final String operation;
  final String originalType;

  @override
  String toString() =>
      'Resenha diagnostics failure ($operation; $originalType)';
}

DateTime _utcNow() => DateTime.now().toUtc();

String _newCaptureId() {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  try {
    final random = Random.secure();
    final high = random.nextInt(0x100000000);
    final low = random.nextInt(0x100000000);
    return 'resenha-$now-${high.toRadixString(16).padLeft(8, '0')}'
        '${low.toRadixString(16).padLeft(8, '0')}';
  } on Object {
    return 'resenha-$now';
  }
}

String _newWriterId() =>
    _newCaptureId().replaceFirst('resenha-', 'writer-$pid-');

bool _isResenhaDiagnosticsWriterAlive(String writerId) {
  if (_liveResenhaDiagnosticsWriterIds.contains(writerId)) return true;
  if (!Platform.isLinux) return false;
  final match = RegExp(r'^writer-([0-9]+)-').firstMatch(writerId);
  final writerPid = int.tryParse(match?.group(1) ?? '');
  if (writerPid == null || writerPid <= 0) return false;
  try {
    return Directory('/proc/$writerPid').existsSync();
  } on FileSystemException {
    return false;
  }
}

bool _isCaptureControlRecord(ResenhaDiagnosticRecord record) =>
    switch (record.event) {
      'capture.started' || 'capture.stopped' || 'capture.interrupted' => true,
      _ => false,
    };
