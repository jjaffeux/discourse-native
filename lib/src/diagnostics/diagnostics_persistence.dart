import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:path_provider/path_provider.dart';

import '../foundation/private_file_permissions.dart';

const Duration diagnosticsRetentionAge = Duration(hours: 24);
const int diagnosticsRetentionCount = 5000;
const int diagnosticsRetentionBytes = 10 * 1024 * 1024;
const int diagnosticsEventBudgetBytes = diagnosticsRetentionBytes - 256;

final class DiagnosticsPersistenceState {
  const DiagnosticsPersistenceState({
    this.events = const [],
    this.lastSeenSequence = 0,
  });

  final List<DiagnosticEvent> events;
  final int lastSeenSequence;
}

typedef _DecodedDiagnosticEvent = ({
  DiagnosticEvent event,
  int serializedBytes,
});

final class _DecodedDiagnosticsFile {
  const _DecodedDiagnosticsFile({
    required this.events,
    required this.lastSeenSequence,
    required this.evicted,
  });

  final List<_DecodedDiagnosticEvent> events;
  final int lastSeenSequence;
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
  final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
  final chronological =
      events.where((event) => event.timestampUtc.isAfter(cutoff)).toList()
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
  final countLimited = chronological.length <= diagnosticsRetentionCount
      ? chronological
      : chronological.sublist(chronological.length - diagnosticsRetentionCount);

  var bytes = 0;
  final retainedNewestFirst = <DiagnosticEvent>[];
  for (final event in countLimited.reversed) {
    final eventBytes =
        bytesOf?.call(event) ?? diagnosticEventSerializedBytes(event);
    if (eventBytes > diagnosticsEventBudgetBytes) {
      continue;
    }
    if (bytes + eventBytes > diagnosticsEventBudgetBytes) {
      break;
    }
    retainedNewestFirst.add(event);
    bytes += eventBytes;
  }
  return List.unmodifiable(retainedNewestFirst.reversed);
}

int diagnosticEventSerializedBytes(DiagnosticEvent event) =>
    utf8.encode(jsonEncode(_eventLine(event))).length + 1;

final class FileDiagnosticsPersistence implements DiagnosticsPersistence {
  FileDiagnosticsPersistence(this.file);

  static const int formatVersion = 1;
  static const String directoryName = 'diagnostics';
  static const String fileName = 'diagnostics-v1.jsonl';
  static final Map<String, _DiagnosticsFileCoordinator> _coordinators = {};

  final File file;
  final Map<String, DiagnosticEvent> _events = {};
  final Map<String, int> _eventBytes = {};
  final SplayTreeMap<int, Set<String>> _eventIdsBySequence = SplayTreeMap();
  final SplayTreeMap<int, Set<String>> _eventIdsByTimestamp = SplayTreeMap();
  Future<void> _tail = Future<void>.value();
  int _lastSeenSequence = 0;
  int _totalEventBytes = 0;
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
        return DiagnosticsPersistenceState(
          events: retainDiagnosticEvents(
            _events.values,
            nowUtc: nowUtc,
            bytesOf: _serializedBytesOf,
          ),
          lastSeenSequence: _lastSeenSequence,
        );
      });

  int _serializedBytesOf(DiagnosticEvent event) =>
      _eventBytes[event.id] ?? diagnosticEventSerializedBytes(event);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) => _serialize(() async {
    if (events.isEmpty) return;
    await _ensureLoaded(nowUtc: nowUtc);
    for (final event in events) {
      _putEvent(event);
    }
    final evicted = _retainInMemory(nowUtc);
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
    _lastSeenSequence = sequence;
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
    _events.clear();
    _eventBytes.clear();
    _eventIdsBySequence.clear();
    _eventIdsByTimestamp.clear();
    _totalEventBytes = 0;
    _lastSeenSequence = 0;
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
  Future<void> close() async {
    await _tail;
  }

  Future<void> _loadFromDisk({
    required DateTime nowUtc,
    bool compactIfNeeded = true,
  }) async {
    _events.clear();
    _eventBytes.clear();
    _eventIdsBySequence.clear();
    _eventIdsByTimestamp.clear();
    _totalEventBytes = 0;
    _lastSeenSequence = 0;
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
    _lastSeenSequence = decoded.lastSeenSequence;
    for (final item in decoded.events) {
      _putEvent(item.event, serializedBytes: item.serializedBytes);
    }
    var evicted = decoded.evicted;
    evicted |= _retainInMemory(nowUtc);
    if (compactIfNeeded &&
        (evicted || await file.length() > diagnosticsRetentionBytes)) {
      await _compactNow(nowUtc, reloadFromDisk: false);
    }
  }

  Future<void> _ensureLoaded({required DateTime nowUtc}) async {
    if (!_loaded) await _loadFromDisk(nowUtc: nowUtc);
  }

  bool _retainInMemory(DateTime nowUtc) {
    final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
    final oldestTimestamp = _eventIdsByTimestamp.firstKey();
    if (_events.length <= diagnosticsRetentionCount &&
        _totalEventBytes <= diagnosticsEventBudgetBytes &&
        (oldestTimestamp == null ||
            oldestTimestamp > cutoff.microsecondsSinceEpoch)) {
      return false;
    }

    var evicted = false;
    while (_eventIdsByTimestamp.isNotEmpty) {
      final timestamp = _eventIdsByTimestamp.firstKey()!;
      if (timestamp > cutoff.microsecondsSinceEpoch) break;
      for (final id in _eventIdsByTimestamp[timestamp]!.toList()) {
        _removeEvent(id);
        evicted = true;
      }
    }

    while (_events.length > diagnosticsRetentionCount) {
      _removeOldestEvent();
      evicted = true;
    }

    if (_totalEventBytes > diagnosticsEventBudgetBytes) {
      for (final entry in _eventBytes.entries.toList()) {
        if (entry.value <= diagnosticsEventBudgetBytes) continue;
        _removeEvent(entry.key);
        evicted = true;
      }
    }

    while (_totalEventBytes > diagnosticsEventBudgetBytes) {
      _removeOldestEvent();
      evicted = true;
    }
    return evicted;
  }

  void _removeOldestEvent() {
    final oldestSequence = _eventIdsBySequence.firstKey();
    if (oldestSequence == null) return;
    _removeEvent(_eventIdsBySequence[oldestSequence]!.first);
  }

  void _putEvent(DiagnosticEvent event, {int? serializedBytes}) {
    final previous = _events[event.id];
    if (previous != null) {
      _removeIndex(_eventIdsBySequence, previous.sequence, event.id);
      _removeIndex(
        _eventIdsByTimestamp,
        previous.timestampUtc.microsecondsSinceEpoch,
        event.id,
      );
    }
    final previousBytes = _eventBytes[event.id];
    if (previousBytes != null) _totalEventBytes -= previousBytes;
    final bytes = serializedBytes ?? diagnosticEventSerializedBytes(event);
    _events[event.id] = event;
    _eventBytes[event.id] = bytes;
    _eventIdsBySequence.putIfAbsent(event.sequence, () => {}).add(event.id);
    _eventIdsByTimestamp
        .putIfAbsent(event.timestampUtc.microsecondsSinceEpoch, () => {})
        .add(event.id);
    _totalEventBytes += bytes;
  }

  void _removeEvent(String id) {
    final event = _events.remove(id);
    if (event != null) {
      _removeIndex(_eventIdsBySequence, event.sequence, id);
      _removeIndex(
        _eventIdsByTimestamp,
        event.timestampUtc.microsecondsSinceEpoch,
        id,
      );
    }
    final bytes = _eventBytes.remove(id);
    if (bytes != null) _totalEventBytes -= bytes;
  }

  static void _removeIndex(
    SplayTreeMap<int, Set<String>> index,
    int key,
    String id,
  ) {
    final ids = index[key];
    if (ids == null) return;
    ids.remove(id);
    if (ids.isEmpty) index.remove(key);
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
    _retainInMemory(nowUtc);
    await ensurePrivateDirectory(file.parent);
    final temporary = File('${file.path}.tmp');
    try {
      await ensurePrivateFile(temporary);
      final sink = temporary.openWrite();
      try {
        for (final event
            in _events.values.toList()..sort(
              (left, right) => left.sequence.compareTo(right.sequence),
            )) {
          sink.writeln(jsonEncode(_eventLine(event)));
        }
        sink.writeln(
          jsonEncode({
            'version': formatVersion,
            'record': 'lastSeen',
            'sequence': _lastSeenSequence,
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
    final completer = Completer<T>();
    final path = file.absolute.path;
    final coordinator = _coordinators.putIfAbsent(
      path,
      () => _DiagnosticsFileCoordinator(File(path)),
    );
    _tail = _tail.then((_) async {
      try {
        completer.complete(await coordinator.run(operation));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// Serializes each complete diagnostics-file operation across persistence
/// objects and holds a process-aware sidecar lock across read/append/replace.
final class _DiagnosticsFileCoordinator {
  _DiagnosticsFileCoordinator(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(
          await withPrivateAdvisoryFileLock(
            File('${file.path}.lock'),
            operation,
          ),
        );
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
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
  final events = <String, DiagnosticEvent>{};
  final eventBytes = <String, int>{};
  final eventIdsBySequence = SplayTreeMap<int, Set<String>>();
  final eventIdsByTimestamp = SplayTreeMap<int, Set<String>>();
  final nowUtc = DateTime.fromMicrosecondsSinceEpoch(
    nowUtcMicroseconds,
    isUtc: true,
  );
  final cutoff = nowUtc.subtract(diagnosticsRetentionAge);
  var totalEventBytes = 0;
  var lastSeenSequence = 0;
  var evicted = false;

  void removeIndex(SplayTreeMap<int, Set<String>> index, int key, String id) {
    final ids = index[key];
    if (ids == null) return;
    ids.remove(id);
    if (ids.isEmpty) index.remove(key);
  }

  void removeEvent(String id) {
    final event = events.remove(id);
    if (event != null) {
      removeIndex(eventIdsBySequence, event.sequence, id);
      removeIndex(
        eventIdsByTimestamp,
        event.timestampUtc.microsecondsSinceEpoch,
        id,
      );
    }
    final bytes = eventBytes.remove(id);
    if (bytes != null) totalEventBytes -= bytes;
  }

  void removeOldestEvent() {
    final oldestSequence = eventIdsBySequence.firstKey();
    if (oldestSequence == null) return;
    removeEvent(eventIdsBySequence[oldestSequence]!.first);
  }

  bool retain() {
    final oldestTimestamp = eventIdsByTimestamp.firstKey();
    if (events.length <= diagnosticsRetentionCount &&
        totalEventBytes <= diagnosticsEventBudgetBytes &&
        (oldestTimestamp == null ||
            oldestTimestamp > cutoff.microsecondsSinceEpoch)) {
      return false;
    }

    var removed = false;
    while (eventIdsByTimestamp.isNotEmpty) {
      final timestamp = eventIdsByTimestamp.firstKey()!;
      if (timestamp > cutoff.microsecondsSinceEpoch) break;
      for (final id in eventIdsByTimestamp[timestamp]!.toList()) {
        removeEvent(id);
        removed = true;
      }
    }
    while (events.length > diagnosticsRetentionCount) {
      removeOldestEvent();
      removed = true;
    }
    if (totalEventBytes > diagnosticsEventBudgetBytes) {
      for (final entry in eventBytes.entries.toList()) {
        if (entry.value <= diagnosticsEventBudgetBytes) continue;
        removeEvent(entry.key);
        removed = true;
      }
    }
    while (totalEventBytes > diagnosticsEventBudgetBytes) {
      removeOldestEvent();
      removed = true;
    }
    return removed;
  }

  void putEvent(DiagnosticEvent event) {
    final previous = events[event.id];
    if (previous != null) {
      removeIndex(eventIdsBySequence, previous.sequence, event.id);
      removeIndex(
        eventIdsByTimestamp,
        previous.timestampUtc.microsecondsSinceEpoch,
        event.id,
      );
    }
    final previousBytes = eventBytes[event.id];
    if (previousBytes != null) totalEventBytes -= previousBytes;
    final bytes = diagnosticEventSerializedBytes(event);
    events[event.id] = event;
    eventBytes[event.id] = bytes;
    eventIdsBySequence.putIfAbsent(event.sequence, () => {}).add(event.id);
    eventIdsByTimestamp
        .putIfAbsent(event.timestampUtc.microsecondsSinceEpoch, () => {})
        .add(event.id);
    totalEventBytes += bytes;
  }

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
            putEvent(event);
            // Fold duplicate lifecycle records first, then enforce a limit as
            // soon as this record crosses one. Even a crash-grown file stays
            // bounded by the retained budget plus the record being decoded.
            if (events.length > diagnosticsRetentionCount ||
                totalEventBytes > diagnosticsEventBudgetBytes ||
                !event.timestampUtc.isAfter(cutoff)) {
              evicted |= retain();
            }
          }
        case 'lastSeen':
          final sequence = decoded['sequence'];
          if (sequence is int) lastSeenSequence = sequence;
      }
    } on FormatException {
      // A crash can leave one incomplete line; healthy lines still load.
    } on TypeError {
      // Version-compatible but malformed records are ignored individually.
    }
  }
  evicted |= retain();

  return _DecodedDiagnosticsFile(
    events: [
      for (final event in events.values)
        (event: event, serializedBytes: eventBytes[event.id]!),
    ],
    lastSeenSequence: lastSeenSequence,
    evicted: evicted,
  );
}

final class MemoryDiagnosticsPersistence implements DiagnosticsPersistence {
  final Map<String, DiagnosticEvent> _events = {};
  final Map<String, int> _eventBytes = {};
  int _lastSeenSequence = 0;
  int _totalEventBytes = 0;

  int get retainedEventCount => _events.length;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) async {
    _retain(nowUtc);
    return DiagnosticsPersistenceState(
      events: retainDiagnosticEvents(_events.values, nowUtc: nowUtc),
      lastSeenSequence: _lastSeenSequence,
    );
  }

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) async {
    for (final event in events) {
      final previousBytes = _eventBytes[event.id];
      if (previousBytes != null) _totalEventBytes -= previousBytes;
      final bytes = diagnosticEventSerializedBytes(event);
      _events[event.id] = event;
      _eventBytes[event.id] = bytes;
      _totalEventBytes += bytes;
    }
    _retain(nowUtc);
  }

  void _retain(DateTime nowUtc) {
    final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
    final staleIds = [
      for (final item in _events.values)
        if (!item.timestampUtc.isAfter(cutoff)) item.id,
    ];
    for (final id in staleIds) {
      _removeEvent(id);
    }
    while (_events.length > diagnosticsRetentionCount ||
        _totalEventBytes > diagnosticsEventBudgetBytes) {
      if (_events.isEmpty) break;
      final oldest = _events.values.reduce(
        (left, right) => left.sequence <= right.sequence ? left : right,
      );
      _removeEvent(oldest.id);
    }
  }

  @override
  Future<void> writeLastSeenSequence(int sequence) async {
    _lastSeenSequence = sequence;
  }

  @override
  Future<void> compact({required DateTime nowUtc}) async => _retain(nowUtc);

  @override
  Future<void> clear() async {
    _events.clear();
    _eventBytes.clear();
    _totalEventBytes = 0;
    _lastSeenSequence = 0;
  }

  @override
  Future<void> close() async {}

  void _removeEvent(String id) {
    _events.remove(id);
    final bytes = _eventBytes.remove(id);
    if (bytes != null) _totalEventBytes -= bytes;
  }
}

Map<String, Object?> _eventLine(DiagnosticEvent event) => {
  'version': FileDiagnosticsPersistence.formatVersion,
  'record': 'event',
  'event': event.toJson(),
};
