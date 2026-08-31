import 'dart:async';
import 'dart:collection';

import 'diagnostic_event.dart';

const Duration diagnosticsRetentionAge = Duration(hours: 24);
const int diagnosticsRetentionCount = 5000;
const int diagnosticsRetentionBytes = 10 * 1024 * 1024;
const int diagnosticsEventBudgetBytes = diagnosticsRetentionBytes - 256;

typedef DiagnosticEventSizer = int Function(DiagnosticEvent event);

final class DiagnosticsJournalSnapshot {
  DiagnosticsJournalSnapshot({
    required Iterable<DiagnosticEvent> events,
    required Map<String, int> serializedEventBytes,
    required this.lastSeenSequence,
  }) : events = List.unmodifiable(events),
       serializedEventBytes = Map.unmodifiable(serializedEventBytes);

  final List<DiagnosticEvent> events;
  final Map<String, int> serializedEventBytes;
  final int lastSeenSequence;
}

final class DiagnosticsJournalRetention {
  const DiagnosticsJournalRetention._(this.evictedEvents);

  final List<DiagnosticEvent> evictedEvents;

  bool get evicted => evictedEvents.isNotEmpty;
}

typedef _JournalEntry = ({DiagnosticEvent event, int serializedBytes});

/// Owns the canonical diagnostics history independently of presentation and
/// storage. Every consumer therefore folds lifecycle replacements, orders
/// events, accounts bytes, and applies retention with the same rules.
final class DiagnosticsJournal {
  factory DiagnosticsJournal({
    required DiagnosticEventSizer sizeOf,
    Iterable<DiagnosticEvent> events = const [],
    Map<String, int> serializedEventBytes = const {},
    int lastSeenSequence = 0,
  }) => DiagnosticsJournal._(
    sizeOf: sizeOf,
    events: events,
    serializedEventBytes: serializedEventBytes,
    lastSeenSequence: lastSeenSequence,
  );

  DiagnosticsJournal._({
    required this._sizeOf,
    required Iterable<DiagnosticEvent> events,
    required Map<String, int> serializedEventBytes,
    required this._lastSeenSequence,
  }) {
    for (final event in events) {
      put(event, serializedBytes: serializedEventBytes[event.id]);
    }
  }

  factory DiagnosticsJournal.fromSnapshot(
    DiagnosticsJournalSnapshot snapshot, {
    required DiagnosticEventSizer sizeOf,
  }) => DiagnosticsJournal(
    sizeOf: sizeOf,
    events: snapshot.events,
    serializedEventBytes: snapshot.serializedEventBytes,
    lastSeenSequence: snapshot.lastSeenSequence,
  );

  final DiagnosticEventSizer _sizeOf;
  final List<DiagnosticEvent> _events = [];
  late final List<DiagnosticEvent> _eventView = UnmodifiableListView(_events);
  final Map<String, _JournalEntry> _byId = {};
  final SplayTreeMap<int, Set<String>> _eventIdsByTimestamp = SplayTreeMap();
  int _lastSeenSequence;
  int _totalSerializedBytes = 0;
  int _unseenErrorCount = 0;

  List<DiagnosticEvent> get events => _eventView;

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  int get totalSerializedBytes => _totalSerializedBytes;

  int get lastSeenSequence => _lastSeenSequence;

  int get unseenErrorCount => _unseenErrorCount;

  int get maximumSequence {
    final eventSequence = _events.isEmpty ? 0 : _events.last.sequence;
    return eventSequence > _lastSeenSequence
        ? eventSequence
        : _lastSeenSequence;
  }

  DateTime? get oldestTimestamp {
    final timestamp = _eventIdsByTimestamp.firstKey();
    return timestamp == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(timestamp, isUtc: true);
  }

  DiagnosticEvent? eventById(String id) => _byId[id]?.event;

  bool containsId(String id) => _byId.containsKey(id);

  int? serializedBytesFor(String id) => _byId[id]?.serializedBytes;

  void put(DiagnosticEvent event, {int? serializedBytes}) {
    final previous = _byId[event.id];
    if (previous != null) {
      _removeEntry(previous);
    }

    final entry = (
      event: event,
      serializedBytes: serializedBytes ?? _sizeOf(event),
    );
    _events.insert(_insertionIndexFor(event), event);
    _byId[event.id] = entry;
    _eventIdsByTimestamp
        .putIfAbsent(event.timestampUtc.microsecondsSinceEpoch, () => {})
        .add(event.id);
    _totalSerializedBytes += entry.serializedBytes;
    if (event.isError && event.sequence > _lastSeenSequence) {
      _unseenErrorCount += 1;
    }
  }

  DiagnosticsJournalRetention retain({required DateTime nowUtc}) {
    final cutoff = nowUtc.toUtc().subtract(diagnosticsRetentionAge);
    final oldest = _eventIdsByTimestamp.firstKey();
    if (_events.length <= diagnosticsRetentionCount &&
        _totalSerializedBytes <= diagnosticsEventBudgetBytes &&
        (oldest == null || oldest > cutoff.microsecondsSinceEpoch)) {
      return const DiagnosticsJournalRetention._([]);
    }

    final evicted = <DiagnosticEvent>[];
    while (_eventIdsByTimestamp.isNotEmpty) {
      final timestamp = _eventIdsByTimestamp.firstKey()!;
      if (timestamp > cutoff.microsecondsSinceEpoch) break;
      for (final id in _eventIdsByTimestamp[timestamp]!.toList()) {
        final removed = removeById(id);
        if (removed != null) evicted.add(removed);
      }
    }

    while (_events.length > diagnosticsRetentionCount) {
      evicted.add(_removeOldest());
    }

    if (_totalSerializedBytes > diagnosticsEventBudgetBytes) {
      for (final entry in _byId.values.toList()) {
        if (entry.serializedBytes <= diagnosticsEventBudgetBytes) continue;
        final removed = removeById(entry.event.id);
        if (removed != null) evicted.add(removed);
      }
    }

    while (_totalSerializedBytes > diagnosticsEventBudgetBytes) {
      evicted.add(_removeOldest());
    }
    return DiagnosticsJournalRetention._(List.unmodifiable(evicted));
  }

  DiagnosticEvent? removeById(String id) {
    final entry = _byId[id];
    if (entry == null) return null;
    _removeEntry(entry);
    return entry.event;
  }

  int markErrorsSeen() {
    var latestErrorSequence = _lastSeenSequence;
    for (var index = _events.length - 1; index >= 0; index -= 1) {
      final event = _events[index];
      if (event.sequence <= latestErrorSequence) break;
      if (event.isError) {
        latestErrorSequence = event.sequence;
        break;
      }
    }
    setLastSeenSequence(latestErrorSequence);
    return latestErrorSequence;
  }

  void setLastSeenSequence(int sequence) {
    _lastSeenSequence = sequence;
    _recountUnseenErrors();
  }

  void clear({int lastSeenSequence = 0}) {
    _events.clear();
    _byId.clear();
    _eventIdsByTimestamp.clear();
    _totalSerializedBytes = 0;
    _unseenErrorCount = 0;
    _lastSeenSequence = lastSeenSequence;
  }

  DiagnosticsJournalSnapshot snapshot() => DiagnosticsJournalSnapshot(
    events: _events,
    serializedEventBytes: {
      for (final entry in _byId.entries) entry.key: entry.value.serializedBytes,
    },
    lastSeenSequence: _lastSeenSequence,
  );

  DiagnosticEvent _removeOldest() {
    final event = _events.first;
    _removeEntry(_byId[event.id]!);
    return event;
  }

  void _removeEntry(_JournalEntry entry) {
    final event = entry.event;
    final index = _indexOf(event);
    if (index >= 0) _events.removeAt(index);
    _byId.remove(event.id);
    _removeTimestampIndex(event);
    _totalSerializedBytes -= entry.serializedBytes;
    if (event.isError && event.sequence > _lastSeenSequence) {
      _unseenErrorCount -= 1;
    }
  }

  int _insertionIndexFor(DiagnosticEvent event) {
    var lower = 0;
    var upper = _events.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      if (_compareEvents(_events[middle], event) < 0) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower;
  }

  int _indexOf(DiagnosticEvent event) {
    var lower = 0;
    var upper = _events.length;
    while (lower < upper) {
      final middle = lower + ((upper - lower) >> 1);
      final comparison = _compareEvents(_events[middle], event);
      if (comparison < 0) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    if (lower < _events.length && _events[lower].id == event.id) return lower;
    return -1;
  }

  void _removeTimestampIndex(DiagnosticEvent event) {
    final timestamp = event.timestampUtc.microsecondsSinceEpoch;
    final ids = _eventIdsByTimestamp[timestamp];
    if (ids == null) return;
    ids.remove(event.id);
    if (ids.isEmpty) _eventIdsByTimestamp.remove(timestamp);
  }

  void _recountUnseenErrors() {
    var unseen = 0;
    for (var index = _events.length - 1; index >= 0; index -= 1) {
      final event = _events[index];
      if (event.sequence <= _lastSeenSequence) break;
      if (event.isError) unseen += 1;
    }
    _unseenErrorCount = unseen;
  }

  static int _compareEvents(DiagnosticEvent left, DiagnosticEvent right) {
    final bySequence = left.sequence.compareTo(right.sequence);
    return bySequence != 0 ? bySequence : left.id.compareTo(right.id);
  }
}

/// Serializes accepted journal work without allowing one failed operation to
/// poison later writes. [done] observes every operation accepted before it.
final class DiagnosticsJournalOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> get done => _tail;

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
