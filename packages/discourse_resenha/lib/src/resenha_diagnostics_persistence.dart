import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:discourse_native/src/data/app_release.dart';
import 'package:discourse_native/src/foundation/private_file_permissions.dart';
import 'resenha_diagnostics_models.dart';
import 'package:path_provider/path_provider.dart';

const Duration resenhaDiagnosticsRetentionAge = Duration(days: 7);
const int resenhaDiagnosticsSegmentCount = 5;
const int resenhaDiagnosticsSegmentBytes = 10 * 1024 * 1024;
const int resenhaDiagnosticsRetentionBytes =
    resenhaDiagnosticsSegmentCount * resenhaDiagnosticsSegmentBytes;
const int resenhaDiagnosticsDecodedTailBytes = 10 * 1024 * 1024;
const int _resenhaDiagnosticsActiveCaptureLimit = 4;
const int _resenhaReportSnapshotFlushBytes = 256 * 1024;
const int _resenhaReportSnapshotReadBytes = 64 * 1024;
const Duration _resenhaReportSnapshotStaleAge = Duration(days: 1);

final Random _resenhaReportSnapshotRandom = Random.secure();

final class ResenhaDiagnosticsPersistenceState {
  const ResenhaDiagnosticsPersistenceState({
    this.records = const [],
    this.retainedBytes = 0,
    this.droppedRecords = 0,
    this.truncated = false,
    this.oldestTimestampUtc,
    this.activeCaptureId,
    this.activeCaptureStartedAtUtc,
    this.activeCaptures = const {},
  });

  final List<ResenhaDiagnosticRecord> records;
  final int retainedBytes;
  final int droppedRecords;
  final bool truncated;
  final DateTime? oldestTimestampUtc;
  final String? activeCaptureId;
  final DateTime? activeCaptureStartedAtUtc;
  final Map<String, ResenhaDiagnosticsActiveCapture> activeCaptures;
}

final class ResenhaDiagnosticsActiveCapture {
  const ResenhaDiagnosticsActiveCapture({
    required this.writerId,
    required this.captureId,
    required this.startedAtUtc,
  });

  final String writerId;
  final String captureId;
  final DateTime startedAtUtc;

  Map<String, Object?> toJson() => {
    'writerId': writerId,
    'captureId': captureId,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
  };
}

abstract interface class ResenhaDiagnosticsPersistence {
  Future<ResenhaDiagnosticsPersistenceState> load({required DateTime nowUtc});

  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  });

  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  });

  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  });

  Future<void> clear();

  Future<void> flush();

  Future<void> close();
}

/// Optional artifact seam for writing retained JSONL without first creating a
/// potentially 50 MiB Dart string. The caller owns and closes [output].
abstract interface class StreamingResenhaDiagnosticsPersistence {
  Future<void> writeJsonReportTo(
    StringSink output, {
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  });
}

typedef ResenhaDiagnosticsReportSinkFactory =
    StringSink Function(Set<String> retainedEventIds);

/// Reads event identifiers only from the canonical deep-event data field.
///
/// Report payloads may contain the same key at arbitrary nested positions.
/// Parsing the JSONL structure here keeps materialized and streaming
/// de-duplication exact instead of treating those unrelated values as event
/// identities.
Set<String> resenhaDiagnosticsEventIdsInJsonReport(
  String report, {
  Set<String>? candidates,
}) {
  if (candidates?.isEmpty ?? false) return const {};
  final eventIds = <String>{};
  var offset = 0;
  while (offset < report.length) {
    final newline = report.indexOf('\n', offset);
    final end = newline < 0 ? report.length : newline;
    final line = report.substring(offset, end);
    offset = newline < 0 ? report.length : newline + 1;
    if (line.isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map ||
          decoded['record'] != 'event' ||
          decoded['origin'] == 'ordinary') {
        continue;
      }
      final event = decoded['event'];
      if (event is! Map) continue;
      final data = event['data'];
      if (data is! Map) continue;
      final eventId = data[resenhaDiagnosticsEventIdField];
      if (eventId is String &&
          (candidates == null || candidates.contains(eventId))) {
        eventIds.add(eventId);
        if (eventIds.length == candidates?.length) break;
      }
    } on FormatException {
      // Durable persistence excludes malformed lines. Custom persistence may
      // still provide one, and a bad line must not affect later valid records.
    }
  }
  return eventIds;
}

/// Optional artifact seam for de-duplicating and streaming one retained
/// snapshot without materializing the report.
///
/// Implementations must select [candidateEventIds], call
/// [outputForRetainedEventIds] exactly once with an unmodifiable set, and write
/// that same retained snapshot to the returned caller-owned sink. The factory
/// is deliberately synchronous, and persistence must not invoke it or write to
/// its sink while holding a shared storage lock.
abstract interface class SnapshotStreamingResenhaDiagnosticsPersistence {
  Future<void> writeJsonReportSnapshotTo({
    required Set<String> candidateEventIds,
    required ResenhaDiagnosticsReportSinkFactory outputForRetainedEventIds,
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  });
}

/// Optional exact de-duplication seam for report exporters.
///
/// Implementations scan retained history without materializing it and return
/// only identifiers which are present in [candidateIds].
abstract interface class RetainedResenhaDiagnosticsEventIdsPersistence {
  Future<Set<String>> findRetainedEventIds(
    Set<String> candidateIds, {
    required DateTime nowUtc,
  });
}

/// Deterministic persistence for tests and non-durable embedders.
final class MemoryResenhaDiagnosticsPersistence
    implements
        ResenhaDiagnosticsPersistence,
        SnapshotStreamingResenhaDiagnosticsPersistence,
        RetainedResenhaDiagnosticsEventIdsPersistence {
  final _ResenhaDiagnosticsStore _store = _ResenhaDiagnosticsStore();

  @override
  Future<ResenhaDiagnosticsPersistenceState> load({
    required DateTime nowUtc,
  }) async {
    _store.retain(nowUtc);
    return _store.snapshot;
  }

  @override
  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  }) async {
    for (final record in records) {
      _store.add(fitResenhaDiagnosticRecord(record));
    }
    _store.retain(nowUtc);
    return _store.snapshot;
  }

  @override
  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  }) async {
    _store.retain(nowUtc);
    return _store.snapshot;
  }

  @override
  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    _store.retain(generatedAtUtc);
    return _buildJsonReport(
      _store.records,
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
      segmentCount: resenhaDiagnosticsSegmentCount,
      segmentBytes: resenhaDiagnosticsSegmentBytes,
    );
  }

  @override
  Future<void> writeJsonReportSnapshotTo({
    required Set<String> candidateEventIds,
    required ResenhaDiagnosticsReportSinkFactory outputForRetainedEventIds,
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    _store.retain(generatedAtUtc);
    final records = List<ResenhaDiagnosticRecord>.unmodifiable(_store.records);
    final retainedEventIds = <String>{
      for (final record in records)
        if (record.data[resenhaDiagnosticsEventIdField] case final String id
            when candidateEventIds.contains(id))
          id,
    };
    final output = outputForRetainedEventIds(
      Set<String>.unmodifiable(retainedEventIds),
    );
    _writeJsonReportRecordsTo(
      output,
      records,
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
      segmentCount: resenhaDiagnosticsSegmentCount,
      segmentBytes: resenhaDiagnosticsSegmentBytes,
    );
  }

  @override
  Future<void> clear() async => _store.reset();

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<Set<String>> findRetainedEventIds(
    Set<String> candidateIds, {
    required DateTime nowUtc,
  }) async {
    if (candidateIds.isEmpty) return const {};
    _store.retain(nowUtc);
    return {
      for (final record in _store.records)
        if (record.data[resenhaDiagnosticsEventIdField] case final String id
            when candidateIds.contains(id))
          id,
    };
  }
}

typedef ResenhaCompactionFaultInjector =
    FutureOr<void> Function(String phase, int index);

final Map<String, _ResenhaFileOperationCoordinator>
_resenhaFileOperationCoordinators = {};

/// Owner-private, bounded JSONL in the platform application-support directory.
///
/// Only a count- and byte-bounded tail is decoded. Older records stay as JSONL
/// and are streamed during compaction/report generation, avoiding a decoded
/// object graph proportional to the 50 MiB retention limit.
final class FileResenhaDiagnosticsPersistence
    implements
        ResenhaDiagnosticsPersistence,
        StreamingResenhaDiagnosticsPersistence,
        SnapshotStreamingResenhaDiagnosticsPersistence,
        RetainedResenhaDiagnosticsEventIdsPersistence {
  FileResenhaDiagnosticsPersistence(
    this.file, {
    this.homeDirectory,
    int segmentCount = resenhaDiagnosticsSegmentCount,
    int segmentBytes = resenhaDiagnosticsSegmentBytes,
    int decodedTailLimit = 2000,
    int decodedTailBytes = resenhaDiagnosticsDecodedTailBytes,
    this._compactionFaultInjector,
  }) : _segmentCount = segmentCount,
       _segmentBytes = segmentBytes,
       _decodedTailLimit = decodedTailLimit,
       _decodedTailBytes = decodedTailBytes {
    if (segmentCount <= 0) {
      throw ArgumentError.value(segmentCount, 'segmentCount');
    }
    if (segmentBytes <= _metadataLineBytes + 512) {
      throw ArgumentError.value(segmentBytes, 'segmentBytes');
    }
    if (decodedTailLimit <= 0 || decodedTailBytes <= 0) {
      throw ArgumentError('Decoded tail limits must be greater than zero.');
    }
  }

  static const String directoryName = 'resenha-diagnostics';
  static const String fileName = 'resenha-diagnostics-v1.jsonl';
  static const int _metadataLineBytes = 1024;

  final File file;
  final String? homeDirectory;
  final int _segmentCount;
  final int _segmentBytes;
  final int _decodedTailLimit;
  final int _decodedTailBytes;
  final ResenhaCompactionFaultInjector? _compactionFaultInjector;
  Future<void> _tail = Future<void>.value();
  ResenhaDiagnosticsPersistenceState _state =
      const ResenhaDiagnosticsPersistenceState();
  bool _loaded = false;
  String _fingerprint = '';
  DateTime? _oldestTimestampUtc;
  DateTime? _latestTimestampUtc;

  int get _retentionBytes => _segmentCount * _segmentBytes;

  int get _eventBudget =>
      max(1, _retentionBytes - (_segmentCount * _metadataLineBytes));

  File get _lockFile => File('${file.path}.lock');
  File get _preparedFile => File('${file.path}.compact.prepared');
  File get _committedFile => File('${file.path}.compact.committed');

  File segmentFile(int index) {
    if (index < 0 || index >= _segmentCount) {
      throw RangeError.range(index, 0, _segmentCount - 1, 'index');
    }
    return index == 0 ? file : File('${file.path}.$index');
  }

  static Future<FileResenhaDiagnosticsPersistence> applicationSupport() async {
    final support = await getApplicationSupportDirectory();
    return FileResenhaDiagnosticsPersistence(
      File('${support.path}/$directoryName/$fileName'),
    );
  }

  @override
  Future<ResenhaDiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _serialize(() => _loadNow(nowUtc));

  @override
  Future<ResenhaDiagnosticsPersistenceState> append(
    List<ResenhaDiagnosticRecord> records, {
    required DateTime nowUtc,
  }) => _serialize(() async {
    await _ensureLoaded(nowUtc);
    if (records.isEmpty) return _state;
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    final maximumRecordBytes = min(
      resenhaDiagnosticsMaximumRecordBytes,
      _segmentBytes - _metadataLineBytes,
    );
    final fitted = <ResenhaDiagnosticRecord>[];
    var expiredRecords = 0;
    var timestampHighWater = _latestTimestampUtc;
    for (final original in records) {
      if (!original.timestampUtc.isAfter(cutoff)) {
        expiredRecords += 1;
        continue;
      }
      var record = original;
      if (timestampHighWater case final highWater?
          when record.timestampUtc.isBefore(highWater)) {
        record = record.copyWith(timestampUtc: highWater);
      }
      record = fitResenhaDiagnosticRecord(
        record,
        maximumBytes: maximumRecordBytes,
      );
      fitted.add(record);
      if (timestampHighWater == null ||
          record.timestampUtc.isAfter(timestampHighWater)) {
        timestampHighWater = record.timestampUtc;
      }
    }
    if (fitted.isEmpty) {
      await _compactNow(nowUtc, additionalDroppedRecords: expiredRecords);
      return _state;
    }
    final encodedBytes = fitted.fold<int>(
      0,
      (total, record) => total + resenhaDiagnosticSerializedBytes(record),
    );
    final hasExpiredPrefix =
        _oldestTimestampUtc != null && !_oldestTimestampUtc!.isAfter(cutoff);
    final currentLength = await file.exists()
        ? await file.length()
        : _metadataLineBytes;
    final needsRotation =
        currentLength > _metadataLineBytes &&
        currentLength + encodedBytes > _segmentBytes;
    if (expiredRecords > 0 ||
        hasExpiredPrefix ||
        needsRotation ||
        _state.retainedBytes + encodedBytes > _eventBudget) {
      await _compactNow(
        nowUtc,
        additionalRecords: fitted,
        additionalDroppedRecords: expiredRecords,
      );
      return _state;
    }

    await _ensureCurrentSegment();
    final output = StringBuffer();
    for (final record in fitted) {
      output.writeln(jsonEncode(resenhaDiagnosticLine(record)));
    }
    await file.writeAsString(
      output.toString(),
      mode: FileMode.append,
      flush: true,
    );
    _adoptAppended(fitted, encodedBytes);
    _fingerprint = await _diskFingerprint();
    return _state;
  });

  @override
  Future<ResenhaDiagnosticsPersistenceState> compact({
    required DateTime nowUtc,
  }) => _serialize(() async {
    await _ensureLoaded(nowUtc);
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    final oldest = _oldestTimestampUtc;
    if (_compactionFaultInjector != null ||
        (oldest != null && !oldest.isAfter(cutoff))) {
      await _compactNow(nowUtc);
    }
    return _state;
  });

  @override
  Future<String> buildJsonReport({
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) => _serialize(() async {
    final output = StringBuffer();
    await _writeJsonReportTo(
      output,
      generatedAtUtc: generatedAtUtc,
      reportFormatVersion: reportFormatVersion,
      state: state,
    );
    return output.toString();
  });

  @override
  Future<void> writeJsonReportTo(
    StringSink output, {
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) => writeJsonReportSnapshotTo(
    candidateEventIds: const {},
    outputForRetainedEventIds: (_) => output,
    generatedAtUtc: generatedAtUtc,
    reportFormatVersion: reportFormatVersion,
    state: state,
  );

  @override
  Future<void> writeJsonReportSnapshotTo({
    required Set<String> candidateEventIds,
    required ResenhaDiagnosticsReportSinkFactory outputForRetainedEventIds,
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    final candidates = Set<String>.unmodifiable(candidateEventIds);
    final reportState = Map<String, Object?>.unmodifiable(state);
    final snapshot = await _serialize(
      () => _createReportSnapshot(
        candidateEventIds: candidates,
        generatedAtUtc: generatedAtUtc,
        reportFormatVersion: reportFormatVersion,
        state: reportState,
      ),
    );

    Object? operationError;
    StackTrace? operationStackTrace;
    try {
      final output = outputForRetainedEventIds(snapshot.retainedEventIds);
      await _streamReportSnapshot(snapshot.input, output);
    } on Object catch (error, stackTrace) {
      operationError = error;
      operationStackTrace = stackTrace;
    }

    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await snapshot.input.close();
    } on Object catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
    }
    try {
      await _deleteIfPresent(snapshot.file);
    } on Object catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }
    if (operationError != null) {
      Error.throwWithStackTrace(operationError, operationStackTrace!);
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  Future<_ResenhaReportSnapshot> _createReportSnapshot({
    required Set<String> candidateEventIds,
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
  }) async {
    final cutoff = await _prepareReportSnapshot(generatedAtUtc);
    await _deleteStaleReportSnapshots();
    final snapshotFile = await _createPrivateReportSnapshotFile();
    final retainedEventIds = <String>{};
    IOSink? sink;
    Object? writeError;
    StackTrace? writeStackTrace;
    try {
      sink = snapshotFile.openWrite();
      final header = jsonEncode(
        _reportHeader(
          generatedAtUtc: generatedAtUtc,
          reportFormatVersion: reportFormatVersion,
          state: state,
          segmentCount: _segmentCount,
          segmentBytes: _segmentBytes,
        ),
      );
      sink.writeln(header);
      var unflushedBytes = utf8.encode(header).length + 1;
      await for (final decoded in _retainedReportRecords(cutoff)) {
        final eventId = decoded.record.data[resenhaDiagnosticsEventIdField];
        if (eventId is String && candidateEventIds.contains(eventId)) {
          retainedEventIds.add(eventId);
        }
        sink.writeln(decoded.line);
        unflushedBytes += decoded.bytes;
        if (unflushedBytes >= _resenhaReportSnapshotFlushBytes) {
          await sink.flush();
          unflushedBytes = 0;
        }
      }
      await sink.flush();
    } on Object catch (error, stackTrace) {
      writeError = error;
      writeStackTrace = stackTrace;
    }
    if (sink != null) {
      try {
        await sink.close();
      } on Object catch (error, stackTrace) {
        writeError ??= error;
        writeStackTrace ??= stackTrace;
      }
    }
    if (writeError != null) {
      try {
        await _deleteIfPresent(snapshotFile);
      } on Object {
        // Preserve the report-write failure. The orphan is owner-only and the
        // strict scavenger retries deletion during a later locked operation.
      }
      Error.throwWithStackTrace(writeError, writeStackTrace!);
    }

    RandomAccessFile? input;
    try {
      restrictPrivateFile(snapshotFile);
      input = await snapshotFile.open(mode: FileMode.read);
      if (_canUnlinkOpenReportSnapshot) {
        try {
          await snapshotFile.delete();
        } on FileSystemException {
          // Some filesystems reject unlinking an open descriptor. The normal
          // post-stream cleanup and strict stale scavenger remain available.
        }
      }
      return _ResenhaReportSnapshot(
        file: snapshotFile,
        input: input,
        retainedEventIds: Set<String>.unmodifiable(retainedEventIds),
      );
    } on Object catch (error, stackTrace) {
      if (input != null) {
        try {
          await input.close();
        } on Object {
          // Deleting the private artifact is the important cleanup below.
        }
      }
      try {
        await _deleteIfPresent(snapshotFile);
      } on Object {
        // Preserve the open/restriction failure; stale cleanup retries later.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _streamReportSnapshot(
    RandomAccessFile input,
    StringSink output,
  ) async {
    final decodedOutput = StringConversionSink.fromStringSink(output);
    final decoder = utf8.decoder.startChunkedConversion(decodedOutput);
    while (true) {
      final bytes = await input.read(_resenhaReportSnapshotReadBytes);
      if (bytes.isEmpty) break;
      decoder.add(bytes);
    }
    decoder.close();
  }

  Future<void> _writeJsonReportTo(
    StringSink output, {
    required DateTime generatedAtUtc,
    required int reportFormatVersion,
    required Map<String, Object?> state,
    DateTime? preparedCutoff,
  }) async {
    final cutoff =
        preparedCutoff ?? await _prepareReportSnapshot(generatedAtUtc);
    output.writeln(
      jsonEncode(
        _reportHeader(
          generatedAtUtc: generatedAtUtc,
          reportFormatVersion: reportFormatVersion,
          state: state,
          segmentCount: _segmentCount,
          segmentBytes: _segmentBytes,
        ),
      ),
    );
    await for (final decoded in _retainedReportRecords(cutoff)) {
      output.writeln(decoded.line);
    }
  }

  @override
  Future<Set<String>> findRetainedEventIds(
    Set<String> candidateIds, {
    required DateTime nowUtc,
  }) => _serialize(() async {
    if (candidateIds.isEmpty) return const <String>{};
    final cutoff = await _prepareReportSnapshot(nowUtc);
    return _findRetainedEventIdsInSnapshot(candidateIds, cutoff: cutoff);
  });

  Future<DateTime> _prepareReportSnapshot(DateTime nowUtc) async {
    await _ensureLoaded(nowUtc);
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    if (_oldestTimestampUtc case final oldest? when !oldest.isAfter(cutoff)) {
      await _compactNow(nowUtc);
    }
    return cutoff;
  }

  Future<Set<String>> _findRetainedEventIdsInSnapshot(
    Set<String> candidateIds, {
    required DateTime cutoff,
  }) async {
    if (candidateIds.isEmpty) return const <String>{};
    final matches = <String>{};
    await for (final decoded in _retainedReportRecords(cutoff)) {
      final eventId = decoded.record.data[resenhaDiagnosticsEventIdField];
      if (eventId is String && candidateIds.contains(eventId)) {
        matches.add(eventId);
        if (matches.length == candidateIds.length) return matches;
      }
    }
    return matches;
  }

  Stream<_DecodedRecordLine> _retainedReportRecords(DateTime cutoff) async* {
    final highWater = <String, int>{};
    DateTime? timestampHighWater;
    for (var index = _segmentCount - 1; index >= 0; index -= 1) {
      final segment = segmentFile(index);
      if (!await segment.exists()) continue;
      await for (final line in _boundedJsonLines(segment)) {
        if (line == null) continue;
        var decoded = _decodeRecordLine(line);
        if (decoded == null ||
            !_acceptIdentity(decoded.record, highWater) ||
            !decoded.record.timestampUtc.isAfter(cutoff)) {
          continue;
        }
        decoded = _clampTimestamp(decoded, timestampHighWater);
        timestampHighWater = decoded.record.timestampUtc;
        yield decoded;
      }
    }
  }

  @override
  Future<void> clear() => _serialize(() async {
    _state = const ResenhaDiagnosticsPersistenceState();
    _oldestTimestampUtc = null;
    _latestTimestampUtc = null;
    _loaded = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (var index = 0; index < _segmentCount; index += 1) {
      final segment = segmentFile(index);
      for (final target in [
        segment,
        File('${segment.path}.tmp'),
        File('${segment.path}.backup'),
      ]) {
        try {
          await _deleteIfPresent(target);
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
    }
    await _deleteIfPresent(_preparedFile);
    await _deleteIfPresent(_committedFile);
    await _deleteGroupTemps();
    await _deleteStaleReportSnapshots();
    _fingerprint = await _diskFingerprint();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  });

  @override
  Future<void> flush() async => _tail;

  @override
  Future<void> close() async => _tail;

  Future<ResenhaDiagnosticsPersistenceState> _loadNow(DateTime nowUtc) async {
    _loaded = true;
    await ensurePrivateDirectory(file.parent);
    await _deleteStaleReportSnapshots();
    await _recoverInterruptedReplacement();
    var scan = await _scan(nowUtc);
    if (scan.needsCompaction) {
      await _compactFromScan(nowUtc, scan);
      scan = await _scan(nowUtc);
    }
    _adoptScan(scan);
    _fingerprint = await _diskFingerprint();
    return _state;
  }

  Future<void> _ensureLoaded(DateTime nowUtc) async {
    if (!_loaded || await _diskFingerprint() != _fingerprint) {
      await _loadNow(nowUtc);
    }
  }

  void _adoptScan(_FileScan scan) {
    _state = scan.state;
    _oldestTimestampUtc = scan.oldestTimestampUtc;
    _latestTimestampUtc = scan.latestTimestampUtc;
  }

  _DecodedRecordLine? _decodeRecordLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map ||
          decoded['version'] != resenhaDiagnosticsFormatVersion ||
          decoded['record'] != 'event' ||
          (decoded['origin'] != null && decoded['origin'] != 'deep')) {
        return null;
      }
      final parsed = ResenhaDiagnosticRecord.fromJson(
        decoded['event'],
        homeDirectory: homeDirectory,
      );
      if (parsed == null) return null;
      return _encodeRecordLine(parsed);
    } on Object {
      return null;
    }
  }

  _DecodedRecordLine _encodeRecordLine(ResenhaDiagnosticRecord input) {
    final record = fitResenhaDiagnosticRecord(
      input,
      maximumBytes: min(
        resenhaDiagnosticsMaximumRecordBytes,
        _segmentBytes - _metadataLineBytes,
      ),
    );
    final canonical = jsonEncode(resenhaDiagnosticLine(record));
    return _DecodedRecordLine(
      record: record,
      line: canonical,
      bytes: utf8.encode(canonical).length + 1,
    );
  }

  _DecodedRecordLine _clampTimestamp(
    _DecodedRecordLine decoded,
    DateTime? highWater,
  ) {
    if (highWater == null || !decoded.record.timestampUtc.isBefore(highWater)) {
      return decoded;
    }
    return _encodeRecordLine(decoded.record.copyWith(timestampUtc: highWater));
  }

  void _adoptAppended(List<ResenhaDiagnosticRecord> records, int encodedBytes) {
    final tail = ListQueue<ResenhaDiagnosticRecord>.from(_state.records);
    var tailBytes = tail.fold<int>(
      0,
      (total, record) => total + resenhaDiagnosticSerializedBytes(record),
    );
    var activeCaptureId = _state.activeCaptureId;
    var activeCaptureStartedAtUtc = _state.activeCaptureStartedAtUtc;
    final activeCaptures = Map<String, ResenhaDiagnosticsActiveCapture>.of(
      _state.activeCaptures,
    );
    var truncated = _state.truncated;
    for (final record in records) {
      final bytes = resenhaDiagnosticSerializedBytes(record);
      tail.addLast(record);
      tailBytes += bytes;
      while (tail.length > _decodedTailLimit || tailBytes > _decodedTailBytes) {
        tailBytes -= resenhaDiagnosticSerializedBytes(tail.removeFirst());
      }
      truncated |= record.truncated;
      switch (record.event) {
        case 'capture.started':
          _rememberActiveCapture(
            activeCaptures,
            ResenhaDiagnosticsActiveCapture(
              writerId: record.writerId,
              captureId: record.captureId,
              startedAtUtc: record.timestampUtc,
            ),
          );
        case 'capture.stopped':
          if (activeCaptures[record.writerId]?.captureId == record.captureId) {
            activeCaptures.remove(record.writerId);
          }
        case 'capture.interrupted':
          activeCaptures.removeWhere(
            (_, capture) => capture.captureId == record.captureId,
          );
      }
      final latestCapture = activeCaptures.values.lastOrNull;
      activeCaptureId = latestCapture?.captureId;
      activeCaptureStartedAtUtc = latestCapture?.startedAtUtc;
      if (_oldestTimestampUtc == null ||
          record.timestampUtc.isBefore(_oldestTimestampUtc!)) {
        _oldestTimestampUtc = record.timestampUtc;
      }
      if (_latestTimestampUtc == null ||
          record.timestampUtc.isAfter(_latestTimestampUtc!)) {
        _latestTimestampUtc = record.timestampUtc;
      }
    }
    _state = ResenhaDiagnosticsPersistenceState(
      records: List.unmodifiable(tail),
      retainedBytes: _state.retainedBytes + encodedBytes,
      droppedRecords: _state.droppedRecords,
      truncated: truncated,
      oldestTimestampUtc: _oldestTimestampUtc,
      activeCaptureId: activeCaptureId,
      activeCaptureStartedAtUtc: activeCaptureStartedAtUtc,
      activeCaptures: Map.unmodifiable(activeCaptures),
    );
  }

  Future<_FileScan> _scan(DateTime nowUtc) async {
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    final tail = ListQueue<_DecodedTailRecord>();
    var tailBytes = 0;
    var retainedBytes = 0;
    var droppedRecords = 0;
    var scanDropped = 0;
    var truncated = false;
    String? activeCaptureId;
    DateTime? activeCaptureStartedAtUtc;
    var activeCaptures = <String, ResenhaDiagnosticsActiveCapture>{};
    DateTime? oldestTimestampUtc;
    DateTime? latestTimestampUtc;
    var needsCompaction = false;
    var physicalBytes = 0;
    final highWater = <String, int>{};

    for (var index = _segmentCount - 1; index >= 0; index -= 1) {
      final segment = segmentFile(index);
      if (!await segment.exists()) continue;
      restrictPrivateFile(segment);
      final segmentLength = await segment.length();
      physicalBytes += segmentLength;
      if (segmentLength > _segmentBytes) needsCompaction = true;
      await for (final line in _boundedJsonLines(segment)) {
        if (line == null) {
          scanDropped += 1;
          needsCompaction = true;
          continue;
        }
        if (line.trim().isEmpty) continue;
        if (_looksLikeStateLine(line)) {
          final metadata = _decodeStateLine(line);
          if (metadata == null) {
            scanDropped += 1;
            needsCompaction = true;
          } else {
            droppedRecords = metadata.droppedRecords;
            truncated |= metadata.truncated;
            activeCaptureId = metadata.activeCaptureId;
            activeCaptureStartedAtUtc = metadata.activeCaptureStartedAtUtc;
            activeCaptures = Map.of(metadata.activeCaptures);
          }
          continue;
        }
        var decoded = _decodeRecordLine(line);
        if (decoded == null || !_acceptIdentity(decoded.record, highWater)) {
          scanDropped += 1;
          needsCompaction = true;
          continue;
        }
        if (!decoded.record.timestampUtc.isAfter(cutoff)) {
          scanDropped += 1;
          needsCompaction = true;
          continue;
        }
        decoded = _clampTimestamp(decoded, latestTimestampUtc);
        if (decoded.line != line) needsCompaction = true;
        final record = decoded.record;
        final bytes = decoded.bytes;
        retainedBytes += bytes;
        if (oldestTimestampUtc == null ||
            record.timestampUtc.isBefore(oldestTimestampUtc)) {
          oldestTimestampUtc = record.timestampUtc;
        }
        if (latestTimestampUtc == null ||
            record.timestampUtc.isAfter(latestTimestampUtc)) {
          latestTimestampUtc = record.timestampUtc;
        }
        truncated |= record.truncated;
        switch (record.event) {
          case 'capture.started':
            _rememberActiveCapture(
              activeCaptures,
              ResenhaDiagnosticsActiveCapture(
                writerId: record.writerId,
                captureId: record.captureId,
                startedAtUtc: record.timestampUtc,
              ),
            );
          case 'capture.stopped':
            if (activeCaptures[record.writerId]?.captureId ==
                record.captureId) {
              activeCaptures.remove(record.writerId);
            }
          case 'capture.interrupted':
            activeCaptures.removeWhere(
              (_, capture) => capture.captureId == record.captureId,
            );
        }
        final latestCapture = activeCaptures.values.lastOrNull;
        activeCaptureId = latestCapture?.captureId;
        activeCaptureStartedAtUtc = latestCapture?.startedAtUtc;
        tail.addLast(_DecodedTailRecord(record, bytes));
        tailBytes += bytes;
        while (tail.length > _decodedTailLimit ||
            tailBytes > _decodedTailBytes) {
          tailBytes -= tail.removeFirst().bytes;
        }
      }
    }
    if (physicalBytes > _retentionBytes || retainedBytes > _eventBudget) {
      needsCompaction = true;
    }

    droppedRecords += scanDropped;
    truncated |= scanDropped > 0;
    return _FileScan(
      state: ResenhaDiagnosticsPersistenceState(
        records: List.unmodifiable(tail.map((entry) => entry.record)),
        retainedBytes: max(0, retainedBytes),
        droppedRecords: droppedRecords,
        truncated: truncated,
        oldestTimestampUtc: oldestTimestampUtc,
        activeCaptureId: activeCaptureId,
        activeCaptureStartedAtUtc: activeCaptureStartedAtUtc,
        activeCaptures: Map.unmodifiable(activeCaptures),
      ),
      oldestTimestampUtc: oldestTimestampUtc,
      latestTimestampUtc: latestTimestampUtc,
      validBytes: max(0, retainedBytes),
      needsCompaction: needsCompaction,
    );
  }

  Future<void> _compactNow(
    DateTime nowUtc, {
    List<ResenhaDiagnosticRecord> additionalRecords = const [],
    int additionalDroppedRecords = 0,
  }) async {
    final scan = await _scan(nowUtc);
    await _compactFromScan(
      nowUtc,
      scan,
      additionalRecords: additionalRecords,
      additionalDroppedRecords: additionalDroppedRecords,
    );
    final compacted = await _scan(nowUtc);
    _adoptScan(compacted);
    _fingerprint = await _diskFingerprint();
  }

  Future<void> _compactFromScan(
    DateTime nowUtc,
    _FileScan scan, {
    List<ResenhaDiagnosticRecord> additionalRecords = const [],
    int additionalDroppedRecords = 0,
  }) async {
    await ensurePrivateDirectory(file.parent);
    await _deleteGroupTemps();
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    var additionalTimestampHighWater = scan.latestTimestampUtc;
    var rejectedAdditionalRecords = additionalDroppedRecords;
    final canonicalAdditionalRecords = <_DecodedRecordLine>[];
    for (final record in additionalRecords) {
      if (!record.timestampUtc.isAfter(cutoff)) {
        rejectedAdditionalRecords += 1;
        continue;
      }
      final decoded = _clampTimestamp(
        _encodeRecordLine(record),
        additionalTimestampHighWater,
      );
      canonicalAdditionalRecords.add(decoded);
      additionalTimestampHighWater = decoded.record.timestampUtc;
    }
    final extraBytes = canonicalAdditionalRecords.fold<int>(
      0,
      (total, decoded) => total + decoded.bytes,
    );
    var remainingBytes = scan.validBytes + extraBytes;
    var droppedRecords = scan.state.droppedRecords + rejectedAdditionalRecords;
    var truncated =
        scan.state.truncated ||
        rejectedAdditionalRecords > 0 ||
        canonicalAdditionalRecords.any((decoded) => decoded.record.truncated);
    var activeCaptureId = scan.state.activeCaptureId;
    var activeCaptureStartedAtUtc = scan.state.activeCaptureStartedAtUtc;
    final activeCaptures = Map<String, ResenhaDiagnosticsActiveCapture>.of(
      scan.state.activeCaptures,
    );
    for (final decoded in canonicalAdditionalRecords) {
      final record = decoded.record;
      switch (record.event) {
        case 'capture.started':
          _rememberActiveCapture(
            activeCaptures,
            ResenhaDiagnosticsActiveCapture(
              writerId: record.writerId,
              captureId: record.captureId,
              startedAtUtc: record.timestampUtc,
            ),
          );
        case 'capture.stopped':
          if (activeCaptures[record.writerId]?.captureId == record.captureId) {
            activeCaptures.remove(record.writerId);
          }
        case 'capture.interrupted':
          activeCaptures.removeWhere(
            (_, capture) => capture.captureId == record.captureId,
          );
      }
    }
    final latestCapture = activeCaptures.values.lastOrNull;
    activeCaptureId = latestCapture?.captureId;
    activeCaptureStartedAtUtc = latestCapture?.startedAtUtc;

    final groups = <_TemporaryGroup>[];
    // ignore: close_sinks, closed by closeCurrent before every exit
    IOSink? sink;
    _TemporaryGroup? current;

    Future<void> closeCurrent() async {
      final open = sink;
      if (open == null) return;
      await open.flush();
      await open.close();
      sink = null;
      current = null;
    }

    Future<void> writeLine(String line, int bytes) async {
      if (remainingBytes > _eventBudget) {
        remainingBytes -= bytes;
        droppedRecords += 1;
        truncated = true;
        return;
      }
      if (current != null &&
          current!.recordCount > 0 &&
          current!.bytes + bytes > _segmentBytes) {
        await closeCurrent();
      }
      if (current == null) {
        final group = _TemporaryGroup(
          File('${file.path}.group.${groups.length}.tmp'),
        );
        await ensurePrivateFile(group.file);
        sink = group.file.openWrite();
        groups.add(group);
        current = group;
      }
      sink!.writeln(line);
      current!
        ..bytes += bytes
        ..recordCount += 1;
    }

    final highWater = <String, int>{};
    DateTime? timestampHighWater;
    for (var index = _segmentCount - 1; index >= 0; index -= 1) {
      final segment = segmentFile(index);
      if (!await segment.exists()) continue;
      await for (final line in _boundedJsonLines(segment)) {
        if (line == null || _looksLikeStateLine(line)) continue;
        var decoded = _decodeRecordLine(line);
        if (decoded == null ||
            !_acceptIdentity(decoded.record, highWater) ||
            !decoded.record.timestampUtc.isAfter(cutoff)) {
          continue;
        }
        decoded = _clampTimestamp(decoded, timestampHighWater);
        timestampHighWater = decoded.record.timestampUtc;
        await writeLine(decoded.line, decoded.bytes);
      }
    }
    for (final additional in canonicalAdditionalRecords) {
      final decoded = _clampTimestamp(additional, timestampHighWater);
      timestampHighWater = decoded.record.timestampUtc;
      await writeLine(decoded.line, decoded.bytes);
    }
    await closeCurrent();

    while (groups.length > _segmentCount) {
      final removed = groups.removeAt(0);
      droppedRecords += removed.recordCount;
      truncated = true;
      await _deleteIfPresent(removed.file);
    }
    final metadata = _FileMetadata(
      droppedRecords: droppedRecords,
      truncated: truncated,
      activeCaptureId: activeCaptureId,
      activeCaptureStartedAtUtc: activeCaptureStartedAtUtc,
      activeCaptures: Map.unmodifiable(activeCaptures),
    );
    if (groups.isEmpty &&
        (droppedRecords > 0 || truncated || activeCaptures.isNotEmpty)) {
      final group = _TemporaryGroup(File('${file.path}.group.0.tmp'));
      await ensurePrivateFile(group.file);
      groups.add(group);
    }
    for (final group in groups) {
      await _prependMetadataHeader(group.file, metadata);
    }
    try {
      await _replaceSegmentsAtomically(groups);
    } on Object {
      // A later operation on this same instance must run generation recovery
      // before trusting its cached tail or appending another batch.
      _loaded = false;
      _fingerprint = '';
      rethrow;
    }
  }

  Future<void> _replaceSegmentsAtomically(
    List<_TemporaryGroup> oldestFirst,
  ) async {
    final originalIndices = <int>[];
    for (var index = 0; index < _segmentCount; index += 1) {
      if (await segmentFile(index).exists()) originalIndices.add(index);
      await _deleteIfPresent(File('${segmentFile(index).path}.backup'));
      await _deleteIfPresent(File('${segmentFile(index).path}.tmp'));
    }
    final newIndices = <int>[];
    for (var groupIndex = 0; groupIndex < oldestFirst.length; groupIndex += 1) {
      final targetIndex = oldestFirst.length - groupIndex - 1;
      newIndices.add(targetIndex);
      await oldestFirst[groupIndex].file.rename(
        '${segmentFile(targetIndex).path}.tmp',
      );
    }
    await _writePrivateJson(_preparedFile, {
      'originalIndices': originalIndices,
      'newIndices': newIndices,
    });

    for (final index in originalIndices) {
      await _compactionFaultInjector?.call('before_backup', index);
      await segmentFile(index).rename('${segmentFile(index).path}.backup');
      await _compactionFaultInjector?.call('after_backup', index);
    }
    for (final index in newIndices) {
      await _compactionFaultInjector?.call('before_install', index);
      await File(
        '${segmentFile(index).path}.tmp',
      ).rename(segmentFile(index).path);
      restrictPrivateFile(segmentFile(index));
      await _compactionFaultInjector?.call('after_install', index);
    }
    await _writePrivateJson(_committedFile, const {'committed': true});
    await _compactionFaultInjector?.call('after_commit', -1);
    await _finalizeCommittedReplacement(
      originalIndices: originalIndices.toSet(),
      newIndices: newIndices.toSet(),
    );
  }

  Future<void> _recoverInterruptedReplacement() async {
    if (await _preparedFile.exists()) {
      final transaction = await _readTransaction();
      if (transaction != null) {
        if (await _committedFile.exists()) {
          await _finalizeCommittedReplacement(
            originalIndices: transaction.originalIndices,
            newIndices: transaction.newIndices,
          );
        } else {
          await _rollbackPreparedReplacement(transaction.originalIndices);
        }
        return;
      }
      // A torn marker cannot authorize a mixed generation. Restore every
      // available backup and discard uncommitted temporary files.
      for (var index = 0; index < _segmentCount; index += 1) {
        final target = segmentFile(index);
        final backup = File('${target.path}.backup');
        if (await backup.exists()) {
          await _deleteIfPresent(target);
          await backup.rename(target.path);
          restrictPrivateFile(target);
        }
        await _deleteIfPresent(File('${target.path}.tmp'));
      }
      await _deleteIfPresent(_preparedFile);
      await _deleteIfPresent(_committedFile);
      return;
    }

    // Compatibility with the original per-segment recovery format.
    for (var index = 0; index < _segmentCount; index += 1) {
      final target = segmentFile(index);
      final temporary = File('${target.path}.tmp');
      final backup = File('${target.path}.backup');
      if (!await target.exists()) {
        if (await temporary.exists()) {
          await temporary.rename(target.path);
          restrictPrivateFile(target);
        } else if (await backup.exists()) {
          await backup.rename(target.path);
          restrictPrivateFile(target);
        }
      }
      if (await target.exists()) {
        await _deleteIfPresent(temporary);
        await _deleteIfPresent(backup);
      }
    }
  }

  Future<void> _rollbackPreparedReplacement(Set<int> originalIndices) async {
    for (var index = 0; index < _segmentCount; index += 1) {
      final target = segmentFile(index);
      final backup = File('${target.path}.backup');
      if (originalIndices.contains(index)) {
        if (await backup.exists()) {
          await _deleteIfPresent(target);
          await backup.rename(target.path);
          restrictPrivateFile(target);
        }
      } else {
        await _deleteIfPresent(target);
      }
      await _deleteIfPresent(File('${target.path}.tmp'));
    }
    await _deleteIfPresent(_preparedFile);
    await _deleteIfPresent(_committedFile);
    await _deleteGroupTemps();
  }

  Future<void> _finalizeCommittedReplacement({
    required Set<int> originalIndices,
    required Set<int> newIndices,
  }) async {
    for (var index = 0; index < _segmentCount; index += 1) {
      final target = segmentFile(index);
      final temporary = File('${target.path}.tmp');
      if (newIndices.contains(index)) {
        if (!await target.exists() && await temporary.exists()) {
          await temporary.rename(target.path);
          restrictPrivateFile(target);
        }
      } else {
        await _deleteIfPresent(target);
      }
      await _deleteIfPresent(temporary);
      await _deleteIfPresent(File('${target.path}.backup'));
    }
    await _deleteIfPresent(_preparedFile);
    await _deleteIfPresent(_committedFile);
    await _deleteGroupTemps();
  }

  Future<_ReplacementTransaction?> _readTransaction() async {
    try {
      final decoded = jsonDecode(await _preparedFile.readAsString());
      if (decoded is! Map) return null;
      final originals = decoded['originalIndices'];
      final replacements = decoded['newIndices'];
      if (originals is! List || replacements is! List) return null;
      final originalIndices = originals.whereType<int>().toSet();
      final newIndices = replacements.whereType<int>().toSet();
      if (originalIndices.length != originals.length ||
          newIndices.length != replacements.length ||
          originalIndices.any((index) => index < 0 || index >= _segmentCount) ||
          newIndices.any((index) => index < 0 || index >= _segmentCount)) {
        return null;
      }
      return _ReplacementTransaction(originalIndices, newIndices);
    } on Object {
      return null;
    }
  }

  Future<void> _ensureCurrentSegment() async {
    if (await file.exists()) {
      restrictPrivateFile(file);
      return;
    }
    await ensurePrivateFile(file);
    await file.writeAsBytes(
      _paddedMetadataLine(
        _FileMetadata(
          droppedRecords: _state.droppedRecords,
          truncated: _state.truncated,
          activeCaptureId: _state.activeCaptureId,
          activeCaptureStartedAtUtc: _state.activeCaptureStartedAtUtc,
          activeCaptures: _state.activeCaptures,
        ),
      ),
      flush: true,
    );
  }

  Future<void> _prependMetadataHeader(
    File target,
    _FileMetadata metadata,
  ) async {
    final replacement = File('${target.path}.header');
    await ensurePrivateFile(replacement);
    final sink = replacement.openWrite();
    try {
      sink.add(_paddedMetadataLine(metadata));
      await sink.addStream(target.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _deleteIfPresent(target);
    await replacement.rename(target.path);
    restrictPrivateFile(target);
  }

  static List<int> _paddedMetadataLine(_FileMetadata metadata) {
    final value = Map<String, Object?>.of(metadata.toJson());
    final captures = List<Object?>.of(
      (value['activeCaptures'] as List<Object?>?) ?? const [],
    );
    var encoded = utf8.encode(jsonEncode(value));
    while (encoded.length >= _metadataLineBytes && captures.isNotEmpty) {
      captures.removeAt(0);
      if (captures.isEmpty) {
        value.remove('activeCaptures');
      } else {
        value['activeCaptures'] = captures;
      }
      encoded = utf8.encode(jsonEncode(value));
    }
    if (encoded.length >= _metadataLineBytes) {
      throw StateError('Resenha diagnostics metadata exceeds its reservation.');
    }
    return [
      ...encoded,
      ...List<int>.filled(_metadataLineBytes - encoded.length - 1, 0x20),
      0x0a,
    ];
  }

  Future<void> _writePrivateJson(File target, Object value) async {
    await ensurePrivateFile(target);
    await target.writeAsString(jsonEncode(value), flush: true);
    restrictPrivateFile(target);
  }

  Future<File> _createPrivateReportSnapshotFile() async {
    await ensurePrivateDirectory(file.parent);
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final snapshot = File(
        '${file.absolute.path}.$pid.${_randomReportSnapshotSuffix()}'
        '.resenha-report-snapshot.tmp',
      );
      try {
        await snapshot.create(exclusive: true);
      } on FileSystemException {
        if (await snapshot.exists()) continue;
        rethrow;
      }
      try {
        // Restrict the empty artifact before its first sensitive byte.
        restrictPrivateFile(snapshot);
        return snapshot;
      } on Object {
        try {
          await _deleteIfPresent(snapshot);
        } on Object {
          // The private directory still contains only an empty artifact.
        }
        rethrow;
      }
    }
    throw StateError('Could not allocate a unique Resenha report snapshot.');
  }

  Future<void> _deleteStaleReportSnapshots() async {
    final parent = file.parent.absolute;
    if (!await parent.exists()) return;
    final ownedSnapshot = RegExp(
      '^${RegExp.escape(file.absolute.path)}\\.\\d+\\.[0-9a-f]{32}'
      r'\.resenha-report-snapshot\.tmp$',
    );
    final staleBefore = DateTime.now().toUtc().subtract(
      _resenhaReportSnapshotStaleAge,
    );
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File || !ownedSnapshot.hasMatch(entity.path)) continue;
      try {
        final modifiedUtc = (await entity.stat()).modified.toUtc();
        if (modifiedUtc.isAfter(staleBefore)) continue;
        await entity.delete();
      } on FileSystemException {
        // A still-open Windows snapshot or a transient cleanup failure remains
        // owner-only and is retried by a later serialized operation.
      }
    }
  }

  Future<void> _deleteGroupTemps() async {
    if (!await file.parent.exists()) return;
    final prefix = '${file.path}.group.';
    await for (final entity in file.parent.list()) {
      if (entity is File && entity.path.startsWith(prefix)) {
        await _deleteIfPresent(entity);
      }
    }
  }

  Future<String> _diskFingerprint() async {
    final output = StringBuffer();
    for (var index = 0; index < _segmentCount; index += 1) {
      final segment = segmentFile(index);
      if (!await segment.exists()) {
        output.write('$index:-;');
        continue;
      }
      final stat = await segment.stat();
      output.write(
        '$index:${stat.size}:${stat.modified.microsecondsSinceEpoch};',
      );
    }
    return output.toString();
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        final coordinator = _resenhaFileOperationCoordinators.putIfAbsent(
          _lockFile.absolute.path,
          () => _ResenhaFileOperationCoordinator(_lockFile),
        );
        completer.complete(await coordinator.run(operation));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<void> _deleteIfPresent(File target) async {
    try {
      await target.delete();
    } on FileSystemException {
      if (await target.exists()) rethrow;
    }
  }
}

final class _ResenhaFileOperationCoordinator {
  _ResenhaFileOperationCoordinator(this.lockFile);

  final File lockFile;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(
          await withPrivateAdvisoryFileLock(lockFile, operation),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _FileScan {
  const _FileScan({
    required this.state,
    required this.oldestTimestampUtc,
    required this.latestTimestampUtc,
    required this.validBytes,
    required this.needsCompaction,
  });

  final ResenhaDiagnosticsPersistenceState state;
  final DateTime? oldestTimestampUtc;
  final DateTime? latestTimestampUtc;
  final int validBytes;
  final bool needsCompaction;
}

final class _DecodedTailRecord {
  const _DecodedTailRecord(this.record, this.bytes);

  final ResenhaDiagnosticRecord record;
  final int bytes;
}

final class _DecodedRecordLine {
  const _DecodedRecordLine({
    required this.record,
    required this.line,
    required this.bytes,
  });

  final ResenhaDiagnosticRecord record;
  final String line;
  final int bytes;
}

final class _ResenhaReportSnapshot {
  const _ResenhaReportSnapshot({
    required this.file,
    required this.input,
    required this.retainedEventIds,
  });

  final File file;
  final RandomAccessFile input;
  final Set<String> retainedEventIds;
}

final class _TemporaryGroup {
  _TemporaryGroup(this.file)
    : bytes = FileResenhaDiagnosticsPersistence._metadataLineBytes;

  final File file;
  int bytes;
  int recordCount = 0;
}

final class _ReplacementTransaction {
  const _ReplacementTransaction(this.originalIndices, this.newIndices);

  final Set<int> originalIndices;
  final Set<int> newIndices;
}

bool get _canUnlinkOpenReportSnapshot =>
    Platform.isAndroid ||
    Platform.isFuchsia ||
    Platform.isIOS ||
    Platform.isLinux ||
    Platform.isMacOS;

String _randomReportSnapshotSuffix() => List<int>.generate(
  16,
  (_) => _resenhaReportSnapshotRandom.nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _FileMetadata {
  const _FileMetadata({
    required this.droppedRecords,
    required this.truncated,
    this.activeCaptureId,
    this.activeCaptureStartedAtUtc,
    this.activeCaptures = const {},
  });

  final int droppedRecords;
  final bool truncated;
  final String? activeCaptureId;
  final DateTime? activeCaptureStartedAtUtc;
  final Map<String, ResenhaDiagnosticsActiveCapture> activeCaptures;

  Map<String, Object?> toJson() => {
    'version': resenhaDiagnosticsFormatVersion,
    'record': 'state',
    'droppedRecords': droppedRecords,
    'truncated': truncated,
    if (activeCaptureId != null) 'activeCaptureId': activeCaptureId,
    if (activeCaptureStartedAtUtc != null)
      'activeCaptureStartedAtUtc': activeCaptureStartedAtUtc!
          .toUtc()
          .toIso8601String(),
    if (activeCaptures.isNotEmpty)
      'activeCaptures': [
        for (final capture in activeCaptures.values.take(
          _resenhaDiagnosticsActiveCaptureLimit,
        ))
          capture.toJson(),
      ],
  };
}

bool _acceptIdentity(
  ResenhaDiagnosticRecord record,
  Map<String, int> highWater,
) {
  final previous = highWater[record.writerId];
  if (previous != null && record.sequence <= previous) return false;
  highWater[record.writerId] = record.sequence;
  return true;
}

void _rememberActiveCapture(
  Map<String, ResenhaDiagnosticsActiveCapture> captures,
  ResenhaDiagnosticsActiveCapture capture,
) {
  captures.remove(capture.writerId);
  captures[capture.writerId] = capture;
  while (captures.length > _resenhaDiagnosticsActiveCaptureLimit) {
    captures.remove(captures.keys.first);
  }
}

bool _looksLikeStateLine(String line) => line.contains('"record":"state"');

_FileMetadata? _decodeStateLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map ||
        decoded['version'] != resenhaDiagnosticsFormatVersion ||
        decoded['record'] != 'state') {
      return null;
    }
    final dropped = decoded['droppedRecords'];
    final truncated = decoded['truncated'];
    final captureId = decoded['activeCaptureId'];
    final startedAt = decoded['activeCaptureStartedAtUtc'];
    final rawCaptures = decoded['activeCaptures'];
    final parsedStart = startedAt is String
        ? DateTime.tryParse(startedAt)
        : null;
    if (dropped is! int ||
        dropped < 0 ||
        truncated is! bool ||
        captureId is! String? ||
        startedAt is! String? ||
        (startedAt != null && parsedStart == null) ||
        (rawCaptures != null && rawCaptures is! List)) {
      return null;
    }
    final activeCaptures = <String, ResenhaDiagnosticsActiveCapture>{};
    if (rawCaptures is List) {
      for (final value in rawCaptures) {
        if (value is! Map) return null;
        final writerId = value['writerId'];
        final listedCaptureId = value['captureId'];
        final listedStart = value['startedAtUtc'];
        final parsedListedStart = listedStart is String
            ? DateTime.tryParse(listedStart)?.toUtc()
            : null;
        if (writerId is! String ||
            listedCaptureId is! String ||
            parsedListedStart == null) {
          return null;
        }
        _rememberActiveCapture(
          activeCaptures,
          ResenhaDiagnosticsActiveCapture(
            writerId: writerId,
            captureId: listedCaptureId,
            startedAtUtc: parsedListedStart,
          ),
        );
      }
    } else if (captureId != null && parsedStart != null) {
      _rememberActiveCapture(
        activeCaptures,
        ResenhaDiagnosticsActiveCapture(
          writerId: 'legacy',
          captureId: captureId,
          startedAtUtc: parsedStart.toUtc(),
        ),
      );
    }
    return _FileMetadata(
      droppedRecords: dropped,
      truncated: truncated,
      activeCaptureId: captureId,
      activeCaptureStartedAtUtc: parsedStart?.toUtc(),
      activeCaptures: Map.unmodifiable(activeCaptures),
    );
  } on FormatException {
    return null;
  }
}

final class _ResenhaDiagnosticsStore {
  List<ResenhaDiagnosticRecord> _records = [];
  Set<String> _identities = {};
  bool _timestampsMonotonic = true;
  int retainedBytes = 0;
  int droppedRecords = 0;
  bool truncated = false;
  String? activeCaptureId;
  DateTime? activeCaptureStartedAtUtc;
  Map<String, ResenhaDiagnosticsActiveCapture> activeCaptures = {};

  List<ResenhaDiagnosticRecord> get records =>
      UnmodifiableListView<ResenhaDiagnosticRecord>(_records);

  DateTime? get oldestTimestampUtc {
    DateTime? oldest;
    for (final record in _records) {
      if (oldest == null || record.timestampUtc.isBefore(oldest)) {
        oldest = record.timestampUtc;
      }
    }
    return oldest;
  }

  ResenhaDiagnosticsPersistenceState get snapshot =>
      ResenhaDiagnosticsPersistenceState(
        records: records,
        retainedBytes: retainedBytes,
        droppedRecords: droppedRecords,
        truncated: truncated,
        oldestTimestampUtc: oldestTimestampUtc,
        activeCaptureId: activeCaptureId,
        activeCaptureStartedAtUtc: activeCaptureStartedAtUtc,
        activeCaptures: Map.unmodifiable(activeCaptures),
      );

  Map<String, Object?> get metadataLine => {
    'version': resenhaDiagnosticsFormatVersion,
    'record': 'state',
    'droppedRecords': droppedRecords,
    'truncated': truncated,
    if (activeCaptureId != null) 'activeCaptureId': activeCaptureId,
    if (activeCaptureStartedAtUtc != null)
      'activeCaptureStartedAtUtc': activeCaptureStartedAtUtc!
          .toUtc()
          .toIso8601String(),
    if (activeCaptures.isNotEmpty)
      'activeCaptures': [
        for (final capture in activeCaptures.values.take(
          _resenhaDiagnosticsActiveCaptureLimit,
        ))
          capture.toJson(),
      ],
  };

  void reset() {
    _records = [];
    _identities = {};
    _timestampsMonotonic = true;
    retainedBytes = 0;
    droppedRecords = 0;
    truncated = false;
    activeCaptureId = null;
    activeCaptureStartedAtUtc = null;
    activeCaptures = {};
  }

  bool add(ResenhaDiagnosticRecord record) {
    final duplicate = !_identities.add(record.identity);
    if (duplicate) {
      final duplicateIndex = _records.indexWhere(
        (existing) => existing.identity == record.identity,
      );
      retainedBytes -= resenhaDiagnosticSerializedBytes(
        _records[duplicateIndex],
      );
      _records.removeAt(duplicateIndex);
      _timestampsMonotonic = false;
    }
    if (_records.lastOrNull case final previous?
        when record.timestampUtc.isBefore(previous.timestampUtc)) {
      _timestampsMonotonic = false;
    }
    _records.add(record);
    retainedBytes += resenhaDiagnosticSerializedBytes(record);
    truncated |= record.truncated;
    switch (record.event) {
      case 'capture.started':
        _rememberActiveCapture(
          activeCaptures,
          ResenhaDiagnosticsActiveCapture(
            writerId: record.writerId,
            captureId: record.captureId,
            startedAtUtc: record.timestampUtc,
          ),
        );
      case 'capture.stopped':
        if (activeCaptures[record.writerId]?.captureId == record.captureId) {
          activeCaptures.remove(record.writerId);
        }
      case 'capture.interrupted':
        activeCaptures.removeWhere(
          (_, capture) => capture.captureId == record.captureId,
        );
    }
    final latestCapture = activeCaptures.values.lastOrNull;
    activeCaptureId = latestCapture?.captureId;
    activeCaptureStartedAtUtc = latestCapture?.startedAtUtc;
    return duplicate;
  }

  bool loadMetadata(Map<dynamic, dynamic> json) {
    final dropped = json['droppedRecords'];
    final wasTruncated = json['truncated'];
    final captureId = json['activeCaptureId'];
    final startedAt = json['activeCaptureStartedAtUtc'];
    if (dropped is! int ||
        dropped < 0 ||
        wasTruncated is! bool ||
        captureId is! String? ||
        startedAt is! String?) {
      return false;
    }
    final parsedStart = startedAt == null ? null : DateTime.tryParse(startedAt);
    if (startedAt != null && parsedStart == null) return false;
    droppedRecords = dropped;
    truncated = wasTruncated;
    activeCaptureId = captureId;
    activeCaptureStartedAtUtc = parsedStart?.toUtc();
    activeCaptures = {
      if (captureId != null && parsedStart != null)
        'legacy': ResenhaDiagnosticsActiveCapture(
          writerId: 'legacy',
          captureId: captureId,
          startedAtUtc: parsedStart.toUtc(),
        ),
    };
    return true;
  }

  void noteDropped(int count) {
    if (count <= 0) return;
    droppedRecords += count;
    truncated = true;
  }

  void removeIdentities(Set<String> identities) {
    if (identities.isEmpty) return;
    final retained = <ResenhaDiagnosticRecord>[];
    var removed = 0;
    var bytes = 0;
    for (final record in _records) {
      if (identities.contains(record.identity)) {
        removed += 1;
      } else {
        retained.add(record);
        bytes += resenhaDiagnosticSerializedBytes(record);
      }
    }
    _records = retained;
    _identities = {for (final record in retained) record.identity};
    _timestampsMonotonic = _isTimestampMonotonic(retained);
    retainedBytes = bytes;
    noteDropped(removed);
  }

  void sort() {
    _records.sort((left, right) {
      final byTimestamp = left.timestampUtc.compareTo(right.timestampUtc);
      if (byTimestamp != 0) return byTimestamp;
      return left.sequence.compareTo(right.sequence);
    });
    _timestampsMonotonic = true;
  }

  void retain(
    DateTime nowUtc, {
    int maximumBytes = resenhaDiagnosticsRetentionBytes,
  }) {
    final cutoff = nowUtc.toUtc().subtract(resenhaDiagnosticsRetentionAge);
    if (!_timestampsMonotonic) {
      final fresh = <ResenhaDiagnosticRecord>[];
      var freshBytes = 0;
      for (final record in _records) {
        if (!record.timestampUtc.isAfter(cutoff)) {
          noteDropped(1);
          continue;
        }
        fresh.add(record);
        freshBytes += resenhaDiagnosticSerializedBytes(record);
      }
      _records = fresh;
      _identities = {for (final record in fresh) record.identity};
      retainedBytes = freshBytes;
      _timestampsMonotonic = _isTimestampMonotonic(fresh);
    }

    var removeCount = 0;
    while (removeCount < _records.length &&
        !_records[removeCount].timestampUtc.isAfter(cutoff)) {
      retainedBytes -= resenhaDiagnosticSerializedBytes(_records[removeCount]);
      removeCount += 1;
    }
    while (retainedBytes > maximumBytes && removeCount < _records.length) {
      retainedBytes -= resenhaDiagnosticSerializedBytes(_records[removeCount]);
      removeCount += 1;
    }
    if (removeCount > 0) {
      for (var index = 0; index < removeCount; index += 1) {
        _identities.remove(_records[index].identity);
      }
      _records = _records.sublist(removeCount);
      noteDropped(removeCount);
    }
  }

  static bool _isTimestampMonotonic(List<ResenhaDiagnosticRecord> records) {
    for (var index = 1; index < records.length; index += 1) {
      if (records[index].timestampUtc.isBefore(
        records[index - 1].timestampUtc,
      )) {
        return false;
      }
    }
    return true;
  }
}

String _buildJsonReport(
  List<ResenhaDiagnosticRecord> records, {
  required DateTime generatedAtUtc,
  required int reportFormatVersion,
  required Map<String, Object?> state,
  required int segmentCount,
  required int segmentBytes,
}) {
  final output = StringBuffer();
  _writeJsonReportRecordsTo(
    output,
    records,
    generatedAtUtc: generatedAtUtc,
    reportFormatVersion: reportFormatVersion,
    state: state,
    segmentCount: segmentCount,
    segmentBytes: segmentBytes,
  );
  return output.toString();
}

void _writeJsonReportRecordsTo(
  StringSink output,
  Iterable<ResenhaDiagnosticRecord> records, {
  required DateTime generatedAtUtc,
  required int reportFormatVersion,
  required Map<String, Object?> state,
  required int segmentCount,
  required int segmentBytes,
}) {
  output.writeln(
    jsonEncode(
      _reportHeader(
        generatedAtUtc: generatedAtUtc,
        reportFormatVersion: reportFormatVersion,
        state: state,
        segmentCount: segmentCount,
        segmentBytes: segmentBytes,
      ),
    ),
  );
  for (final record in records) {
    output.writeln(jsonEncode(resenhaDiagnosticLine(record)));
  }
}

Map<String, Object?> _reportHeader({
  required DateTime generatedAtUtc,
  required int reportFormatVersion,
  required Map<String, Object?> state,
  required int segmentCount,
  required int segmentBytes,
}) => {
  'formatVersion': reportFormatVersion,
  'captureFormatVersion': resenhaDiagnosticsFormatVersion,
  'record': 'report',
  'generatedAtUtc': generatedAtUtc.toUtc().toIso8601String(),
  'app': {'version': AppRelease.version},
  'platform': {
    'operatingSystem': Platform.operatingSystem,
    'operatingSystemVersion': ResenhaDiagnosticsRedactor.scrub(
      Platform.operatingSystemVersion,
    ),
  },
  'retention': {
    'days': resenhaDiagnosticsRetentionAge.inDays,
    'segmentCount': segmentCount,
    'segmentBytes': segmentBytes,
    'maximumRecordBytes': resenhaDiagnosticsMaximumRecordBytes,
  },
  'state': state,
};

Stream<String?> _boundedJsonLines(File file) async* {
  var bytes = BytesBuilder(copy: false);
  var discarding = false;

  void append(List<int> chunk, int start, int end) {
    if (discarding || start == end) return;
    if (bytes.length + end - start >= resenhaDiagnosticsMaximumRecordBytes) {
      bytes.clear();
      discarding = true;
      return;
    }
    bytes.add(chunk.sublist(start, end));
  }

  String? finish() {
    if (discarding) return null;
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      return null;
    }
  }

  await for (final chunk in file.openRead()) {
    var segmentStart = 0;
    for (var index = 0; index < chunk.length; index += 1) {
      if (chunk[index] != 0x0a) continue;
      append(chunk, segmentStart, index);
      yield finish();
      bytes = BytesBuilder(copy: false);
      discarding = false;
      segmentStart = index + 1;
    }
    append(chunk, segmentStart, chunk.length);
  }
  if (bytes.isNotEmpty || discarding) yield finish();
}
