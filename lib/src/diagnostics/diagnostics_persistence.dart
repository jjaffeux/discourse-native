import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_journal.dart';
import 'package:path_provider/path_provider.dart';

import '../foundation/private_file_permissions.dart';

export 'diagnostics_journal.dart'
    show
        diagnosticsEventBudgetBytes,
        diagnosticsRetentionAge,
        diagnosticsRetentionBytes,
        diagnosticsRetentionCount;

final class DiagnosticsPersistenceState {
  const DiagnosticsPersistenceState({
    this.events = const [],
    this.serializedEventBytes = const {},
    this.lastSeenSequence = 0,
  });

  final List<DiagnosticEvent> events;
  final Map<String, int> serializedEventBytes;
  final int lastSeenSequence;
}

final class _DecodedDiagnosticsFile {
  const _DecodedDiagnosticsFile({required this.journal, required this.evicted});

  final DiagnosticsJournalSnapshot journal;
  final bool evicted;
}

abstract interface class DiagnosticsPersistence {
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc});

  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  });

  Future<void> writeLastSeenSequence(int sequence);

  Future<void> compact({required DateTime nowUtc});

  Future<void> clear();

  Future<void> close();
}

/// [bytesOf] supplies a size a caller has already measured. Sizing an event
/// means encoding it, and the decode that produced these events did that work
/// off the main isolate deliberately; recomputing it here would put the whole
/// history's worth of `jsonEncode` back on the isolate that draws.
List<DiagnosticEvent> retainDiagnosticEvents(
  Iterable<DiagnosticEvent> events, {
  required DateTime nowUtc,
  int Function(DiagnosticEvent event)? bytesOf,
}) {
  final sizeOf = bytesOf ?? diagnosticEventSerializedBytes;
  final journal = DiagnosticsJournal(sizeOf: sizeOf);
  for (final event in events) {
    journal.put(event, serializedBytes: sizeOf(event));
  }
  journal.retain(nowUtc: nowUtc);
  return List.unmodifiable(journal.events);
}

int diagnosticEventSerializedBytes(DiagnosticEvent event) =>
    utf8.encode(jsonEncode(_eventLine(event))).length + 1;

final class FileDiagnosticsPersistence implements DiagnosticsPersistence {
  FileDiagnosticsPersistence(this.file)
    : _journal = DiagnosticsJournal(sizeOf: diagnosticEventSerializedBytes);

  static const int formatVersion = 1;
  static const String directoryName = 'diagnostics';
  static const String fileName = 'diagnostics-v1.jsonl';
  static final Map<String, _DiagnosticsFileCoordinator> _coordinators = {};

  final File file;
  DiagnosticsJournal _journal;
  final DiagnosticsJournalOperationQueue _operations =
      DiagnosticsJournalOperationQueue();
  bool _loaded = false;

  static Future<FileDiagnosticsPersistence> applicationSupport() async {
    final support = await getApplicationSupportDirectory();
    return FileDiagnosticsPersistence(
      File('${support.path}/$directoryName/$fileName'),
    );
  }

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _serialize(() async {
        await _loadFromDisk(nowUtc: nowUtc);
        final snapshot = _journal.snapshot();
        return DiagnosticsPersistenceState(
          events: snapshot.events,
          serializedEventBytes: snapshot.serializedEventBytes,
          lastSeenSequence: snapshot.lastSeenSequence,
        );
      });

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _serialize(() async {
    if (events.isEmpty) return;
    await _ensureLoaded(nowUtc: nowUtc);
    for (final event in events) {
      _journal.put(event);
    }
    final evicted = _journal.retain(nowUtc: nowUtc).evicted;
    await _appendLines([for (final event in events) _eventLine(event)]);
    // Deliberately eager, and deliberately not amortised on file growth: a
    // record dropped by the retention age has to leave the disk when it is
    // dropped, not once the file happens to be worth rewriting. Diagnostics
    // hold captured request data, so the age limit is a promise about what is
    // stored, and `test/diagnostics_persistence_test.dart` pins it.
    if (evicted || await file.length() > diagnosticsRetentionBytes) {
      await _compactNow(nowUtc);
    }
  });

  @override
  Future<void> writeLastSeenSequence(int sequence) => _serialize(() async {
    await _ensureLoaded(nowUtc: DateTime.now().toUtc());
    _journal.setLastSeenSequence(sequence);
    await _appendLines([
      {'version': formatVersion, 'record': 'lastSeen', 'sequence': sequence},
    ]);
    if (await file.length() > diagnosticsRetentionBytes) {
      await _compactNow(DateTime.now().toUtc());
    }
  });

  @override
  Future<void> compact({required DateTime nowUtc}) => _serialize(() async {
    await _compactNow(nowUtc);
  });

  @override
  Future<void> clear() => _serialize(() async {
    _journal.clear();
    _loaded = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final target in [file, File('${file.path}.tmp')]) {
      try {
        await _deleteIfPresent(target);
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  });

  @override
  Future<void> close() => _operations.done;

  Future<void> _loadFromDisk({
    required DateTime nowUtc,
    bool compactIfNeeded = true,
  }) async {
    _journal.clear();
    _loaded = true;
    // A process can stop after the compacted history is flushed but before it
    // is renamed. The main JSONL remains authoritative; the orphan contains a
    // second full copy which must not outlive the same retention policy.
    await _deleteIfPresent(File('${file.path}.tmp'));
    if (!await file.exists()) return;
    await ensurePrivateDirectory(file.parent);
    restrictPrivateFile(file);

    // A retained history may contain thousands of events with long error
    // strings. JSON decoding and the mandatory privacy scrub are CPU-bound;
    // doing them on the UI isolate made an ordinary diagnostics compaction
    // contend with scrolling for multiple seconds in debug/profile captures.
    final path = file.absolute.path;
    final nowUtcMicroseconds = nowUtc.microsecondsSinceEpoch;
    final decoded = await Isolate.run(
      () => _decodeDiagnosticsFile(path, nowUtcMicroseconds),
      debugName: 'diagnostics-file-decode',
    );
    _journal = DiagnosticsJournal.fromSnapshot(
      decoded.journal,
      sizeOf: diagnosticEventSerializedBytes,
    );
    var evicted = decoded.evicted;
    evicted |= _journal.retain(nowUtc: nowUtc).evicted;
    if (compactIfNeeded &&
        (evicted || await file.length() > diagnosticsRetentionBytes)) {
      await _compactNow(nowUtc, reloadFromDisk: false);
    }
  }

  Future<void> _ensureLoaded({required DateTime nowUtc}) async {
    if (!_loaded) await _loadFromDisk(nowUtc: nowUtc);
  }

  Future<void> _appendLines(List<Map<String, Object?>> lines) async {
    if (lines.isEmpty) return;
    await ensurePrivateFile(file);
    // A kill mid-write can leave the file ending without its newline. The
    // decoder already tolerates that one torn line, but appending straight
    // onto it would splice the next record into the fragment and lose that
    // record too — and the file would stay one line out of step until an
    // unrelated compaction. Close the torn line first; it costs a byte and
    // bounds the damage to the record that was actually interrupted.
    final terminator = await _needsLineTerminator() ? '\n' : '';
    await file.writeAsString(
      '$terminator${lines.map(jsonEncode).join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<bool> _needsLineTerminator() async {
    final length = await file.length();
    if (length == 0) return false;
    final handle = await file.open();
    try {
      await handle.setPosition(length - 1);
      final last = await handle.readByte();
      return last != 0x0a;
    } finally {
      await handle.close();
    }
  }

  Future<void> _compactNow(
    DateTime nowUtc, {
    bool reloadFromDisk = true,
  }) async {
    // Another persistence object or process can append after this object's
    // in-memory fold was loaded. Reconcile the locked JSONL immediately before
    // replacing it so compaction never publishes a stale snapshot.
    if (reloadFromDisk) {
      await _loadFromDisk(nowUtc: nowUtc, compactIfNeeded: false);
    }
    _journal.retain(nowUtc: nowUtc);
    await ensurePrivateDirectory(file.parent);
    final temporary = File('${file.path}.tmp');
    try {
      await ensurePrivateFile(temporary);
      final sink = temporary.openWrite();
      try {
        for (final event in _journal.events) {
          sink.writeln(jsonEncode(_eventLine(event)));
        }
        sink.writeln(
          jsonEncode({
            'version': formatVersion,
            'record': 'lastSeen',
            'sequence': _journal.lastSeenSequence,
          }),
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
      await temporary.rename(file.path);
      restrictPrivateFile(file);
    } on Object {
      try {
        await _deleteIfPresent(temporary);
      } on Object {
        // Preserve the compaction failure. Clear retries both paths later.
      }
      rethrow;
    }
  }

  static Future<void> _deleteIfPresent(File target) async {
    try {
      await target.delete();
    } on FileSystemException {
      if (await target.exists()) rethrow;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final path = file.absolute.path;
    final coordinator = _coordinators.putIfAbsent(
      path,
      () => _DiagnosticsFileCoordinator(File(path)),
    );
    return _operations.run(() => coordinator.run(operation));
  }
}

/// Serializes each complete diagnostics-file operation across persistence
/// objects and holds a process-aware sidecar lock across read/append/replace.
final class _DiagnosticsFileCoordinator {
  _DiagnosticsFileCoordinator(this.file);

  final File file;
  final DiagnosticsJournalOperationQueue _operations =
      DiagnosticsJournalOperationQueue();

  Future<T> run<T>(Future<T> Function() operation) => _operations.run(
    () => withPrivateAdvisoryFileLock(File('${file.path}.lock'), operation),
  );
}

/// Streams JSONL without retaining the whole history or an unbounded corrupt
/// line. A valid persisted event already has to fit inside the total history
/// budget, so anything larger cannot survive retention and is skipped until
/// its next newline. This matters most after a crash, before compaction has had
/// a chance to restore the normal ten-megabyte file bound.
Stream<String> _boundedJsonLines(File file) async* {
  var bytes = BytesBuilder(copy: false);
  var discardingLine = false;

  void appendSegment(List<int> chunk, int start, int end) {
    if (discardingLine || start == end) return;
    if (bytes.length + end - start > diagnosticsRetentionBytes) {
      bytes.clear();
      discardingLine = true;
      return;
    }
    bytes.add(chunk.sublist(start, end));
  }

  String? finishLine() {
    if (discardingLine) return null;
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
      appendSegment(chunk, segmentStart, index);
      final line = finishLine();
      if (line != null) yield line;
      bytes = BytesBuilder(copy: false);
      discardingLine = false;
      segmentStart = index + 1;
    }
    appendSegment(chunk, segmentStart, chunk.length);
  }

  if (bytes.isNotEmpty && !discardingLine) {
    final line = finishLine();
    if (line != null) yield line;
  }
}

/// Decodes and privacy-scrubs a diagnostics history away from Flutter's UI
/// isolate while retaining the same incremental memory bounds as the owner.
Future<_DecodedDiagnosticsFile> _decodeDiagnosticsFile(
  String path,
  int nowUtcMicroseconds,
) async {
  final nowUtc = DateTime.fromMicrosecondsSinceEpoch(
    nowUtcMicroseconds,
    isUtc: true,
  );
  final journal = DiagnosticsJournal(sizeOf: diagnosticEventSerializedBytes);
  var evicted = false;

  await for (final line in _boundedJsonLines(File(path))) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map ||
          decoded['version'] != FileDiagnosticsPersistence.formatVersion) {
        continue;
      }
      switch (decoded['record']) {
        case 'event':
          final event = DiagnosticEvent.fromJson(decoded['event']);
          if (event != null) {
            journal.put(event);
            // Fold duplicate lifecycle records first, then enforce a limit as
            // soon as this record crosses one. Even a crash-grown file stays
            // bounded by the retained budget plus the record being decoded.
            evicted |= journal.retain(nowUtc: nowUtc).evicted;
          }
        case 'lastSeen':
          final sequence = decoded['sequence'];
          if (sequence is int) journal.setLastSeenSequence(sequence);
      }
    } on FormatException {
      // A crash can leave one incomplete line; healthy lines still load.
    } on TypeError {
      // Version-compatible but malformed records are ignored individually.
    }
  }
  evicted |= journal.retain(nowUtc: nowUtc).evicted;

  return _DecodedDiagnosticsFile(journal: journal.snapshot(), evicted: evicted);
}

final class MemoryDiagnosticsPersistence implements DiagnosticsPersistence {
  final DiagnosticsJournal _journal = DiagnosticsJournal(
    sizeOf: diagnosticEventSerializedBytes,
  );
  final DiagnosticsJournalOperationQueue _operations =
      DiagnosticsJournalOperationQueue();

  int get retainedEventCount => _journal.length;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _operations.run(() async {
        _journal.retain(nowUtc: nowUtc);
        final snapshot = _journal.snapshot();
        return DiagnosticsPersistenceState(
          events: snapshot.events,
          serializedEventBytes: snapshot.serializedEventBytes,
          lastSeenSequence: snapshot.lastSeenSequence,
        );
      });

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _operations.run(() async {
    for (final event in events) {
      _journal.put(event);
    }
    _journal.retain(nowUtc: nowUtc);
  });

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _operations.run(() async => _journal.setLastSeenSequence(sequence));

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _operations.run(() async => _journal.retain(nowUtc: nowUtc));

  @override
  Future<void> clear() => _operations.run(() async => _journal.clear());

  @override
  Future<void> close() => _operations.done;
}

Map<String, Object?> _eventLine(DiagnosticEvent event) => {
  'version': FileDiagnosticsPersistence.formatVersion,
  'record': 'event',
  'event': event.toJson(),
};
