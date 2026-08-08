import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:path_provider/path_provider.dart';

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

abstract interface class DiagnosticsPersistence {
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc});

  /// Appends one timer batch using a single serialized storage operation.
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  });

  Future<void> writeLastSeenSequence(int sequence);

  Future<void> compact({required DateTime nowUtc});

  Future<void> clear();

  Future<void> close();
}

/// Applies all three rolling-history limits to an already-folded event list.
List<DiagnosticEvent> retainDiagnosticEvents(
  Iterable<DiagnosticEvent> events, {
  required DateTime nowUtc,
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
    final eventBytes = diagnosticEventSerializedBytes(event);
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

/// Versioned JSONL persistence in the platform application-support directory.
final class FileDiagnosticsPersistence implements DiagnosticsPersistence {
  FileDiagnosticsPersistence(this.file);

  static const int formatVersion = 1;
  static const String directoryName = 'diagnostics';
  static const String fileName = 'diagnostics-v1.jsonl';

  final File file;
  final Map<String, DiagnosticEvent> _events = {};
  final Map<String, int> _eventBytes = {};
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
          events: retainDiagnosticEvents(_events.values, nowUtc: nowUtc),
          lastSeenSequence: _lastSeenSequence,
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
      _putEvent(event);
    }
    final evicted = _retainInMemory(nowUtc);
    await _appendLines([for (final event in events) _eventLine(event)]);
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
    await _ensureLoaded(nowUtc: nowUtc);
    await _compactNow(nowUtc);
  });

  @override
  Future<void> clear() => _serialize(() async {
    _events.clear();
    _eventBytes.clear();
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

  Future<void> _loadFromDisk({required DateTime nowUtc}) async {
    _events.clear();
    _eventBytes.clear();
    _totalEventBytes = 0;
    _lastSeenSequence = 0;
    _loaded = true;
    // A process can stop after the compacted history is flushed but before it
    // is renamed. The main JSONL remains authoritative; the orphan contains a
    // second full copy which must not outlive the same retention policy.
    await _deleteIfPresent(File('${file.path}.tmp'));
    if (!await file.exists()) return;

    final contents = await file.readAsString();
    for (final line in const LineSplitter().convert(contents)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map || decoded['version'] != formatVersion) continue;
        switch (decoded['record']) {
          case 'event':
            final event = DiagnosticEvent.fromJson(decoded['event']);
            if (event != null) _putEvent(event);
          case 'lastSeen':
            final sequence = decoded['sequence'];
            if (sequence is int) _lastSeenSequence = sequence;
        }
      } on FormatException {
        // A crash can leave one incomplete line; healthy lines still load.
      } on TypeError {
        // Version-compatible but malformed records are ignored individually.
      }
    }
    final evicted = _retainInMemory(nowUtc);
    if (evicted || await file.length() > diagnosticsRetentionBytes) {
      await _compactNow(nowUtc);
    }
  }

  Future<void> _ensureLoaded({required DateTime nowUtc}) async {
    if (!_loaded) await _loadFromDisk(nowUtc: nowUtc);
  }

  bool _retainInMemory(DateTime nowUtc) {
    var evicted = false;
    final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
    final staleIds = [
      for (final event in _events.values)
        if (!event.timestampUtc.isAfter(cutoff)) event.id,
    ];
    for (final id in staleIds) {
      _removeEvent(id);
      evicted = true;
    }
    while (_events.length > diagnosticsRetentionCount ||
        _totalEventBytes > diagnosticsEventBudgetBytes) {
      if (_events.isEmpty) break;
      final oldest = _events.values.reduce(
        (left, right) => left.sequence <= right.sequence ? left : right,
      );
      _removeEvent(oldest.id);
      evicted = true;
    }
    return evicted;
  }

  void _putEvent(DiagnosticEvent event) {
    final previousBytes = _eventBytes[event.id];
    if (previousBytes != null) _totalEventBytes -= previousBytes;
    final bytes = diagnosticEventSerializedBytes(event);
    _events[event.id] = event;
    _eventBytes[event.id] = bytes;
    _totalEventBytes += bytes;
  }

  void _removeEvent(String id) {
    _events.remove(id);
    final bytes = _eventBytes.remove(id);
    if (bytes != null) _totalEventBytes -= bytes;
  }

  Future<void> _appendLines(List<Map<String, Object?>> lines) async {
    if (lines.isEmpty) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${lines.map(jsonEncode).join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _compactNow(DateTime nowUtc) async {
    _retainInMemory(nowUtc);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
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
      // It was already absent, which is the requested end state.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// A deterministic persistence implementation for tests and embedders.
final class MemoryDiagnosticsPersistence implements DiagnosticsPersistence {
  final Map<String, DiagnosticEvent> _events = {};
  final Map<String, int> _eventBytes = {};
  int _lastSeenSequence = 0;
  int _totalEventBytes = 0;

  /// Exposed for deterministic retention tests and memory-store embedders.
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
