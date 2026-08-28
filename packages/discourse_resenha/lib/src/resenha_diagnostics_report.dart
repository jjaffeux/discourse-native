import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'resenha_diagnostics.dart';
import 'resenha_report_exporter.dart';

/// Builds the combined ordinary and deep-capture Resenha diagnostics surface.
///
/// The ordinary recorder intentionally retains more detail than Resenha can
/// safely expose without explicit capture. This boundary owns that projection,
/// exact de-duplication against deep history, and chronological report merge so
/// callers cannot accidentally compose the two streams with different privacy
/// or ordering rules.
final class ResenhaDiagnosticsReport {
  ResenhaDiagnosticsReport({
    required DiagnosticsController diagnostics,
    required ResenhaDiagnosticsController resenha,
    @visibleForTesting ValueChanged<String>? onEventProjected,
  }) : this._(diagnostics, resenha, onEventProjected);

  ResenhaDiagnosticsReport._(
    this._diagnostics,
    this._resenha,
    ValueChanged<String>? onEventProjected,
  ) : _timeline = _ResenhaDiagnosticsTimelineProjection(
        onEventProjected: onEventProjected,
      );

  final DiagnosticsController _diagnostics;
  final ResenhaDiagnosticsController _resenha;
  final _ResenhaDiagnosticsTimelineProjection _timeline;

  /// The chronological, JSON-shaped events used by the live timeline.
  List<Map<String, Object?>> get events =>
      _timeline.project(_resenha.eventsTail, _diagnostics.events);

  /// Builds the complete combined JSONL report in memory.
  Future<String> buildJson() async {
    final deepReport = await _resenha.buildJsonReport();
    final capturedOrdinaryIds = resenhaDiagnosticsEventIdsInJsonReport(
      deepReport,
    );
    final ordinaryEvents = _diagnostics.events.where(
      (event) =>
          _isResenhaOrdinaryEvent(event) &&
          !_duplicatesDeepEvent(event, capturedOrdinaryIds),
    );
    final ordinaryRecords = [
      for (final event in ordinaryEvents) _ordinaryResenhaReportRecord(event),
    ]..sort(_compareResenhaReportRecords);

    final firstLineEnd = deepReport.indexOf('\n');
    if (firstLineEnd < 0) return deepReport;
    final rawHeader = deepReport.substring(0, firstLineEnd);
    final header = _enrichResenhaReportHeader(
      rawHeader,
      ordinaryEventCount: ordinaryRecords.length,
    );

    final deepEvents = deepReport.substring(firstLineEnd + 1);
    return '$header\n${_mergeResenhaReportEvents(deepEvents, ordinaryRecords)}';
  }

  /// Builds a clipboard-safe tail without materializing a large deep report.
  Future<ResenhaClipboardReport> buildClipboard(int byteLimit) async {
    // A full deep report below the clipboard threshold is cheap enough to
    // build and lets the exact ordinary/deep de-duplicator decide whether the
    // combined report still fits. Above the threshold, never materialize the
    // retained (up to 50 MiB) history merely to throw its oldest bytes away.
    if (_resenha.state.retainedBytes <= byteLimit) {
      return boundResenhaReportForClipboard(
        await buildJson(),
        byteLimit: byteLimit,
      );
    }

    final capturedOrdinaryIds = <String>{
      for (final event in _resenha.eventsTail)
        if (event.data[resenhaDiagnosticsEventIdField] case final String id) id,
    };
    final recent = <_ResenhaReportRecord>[
      for (final event in _diagnostics.events)
        if (_isResenhaOrdinaryEvent(event) &&
            !_duplicatesDeepEvent(event, capturedOrdinaryIds))
          _ordinaryResenhaReportRecord(event),
      for (final event in _resenha.eventsTail)
        (
          timestamp: event.timestampUtc,
          identity: 'deep:${event.identity}',
          line: jsonEncode(resenhaDiagnosticLine(event)),
        ),
    ]..sort(_compareResenhaReportRecords);
    final ordinaryBytes = recent
        .where((record) => record.identity.startsWith('ordinary:'))
        .fold<int>(
          0,
          (total, record) => total + utf8.encode(record.line).length + 1,
        );
    final marker = jsonEncode({
      'kind': 'export_metadata',
      'truncated': true,
      'reason': 'clipboard_limit',
      'deepRetainedBytes': _resenha.state.retainedBytes,
      'ordinaryRecentBytes': ordinaryBytes,
      'message': 'Recent records only. Use Share/Save for the full report.',
    });
    final retained = <String>[];
    var retainedBytes = utf8.encode('$marker\n').length;
    for (final record in recent.reversed) {
      final lineBytes = utf8.encode('${record.line}\n').length;
      if (retainedBytes + lineBytes > byteLimit) break;
      retained.add(record.line);
      retainedBytes += lineBytes;
    }
    return ResenhaClipboardReport(
      '$marker\n${retained.reversed.join('\n')}',
      truncated: true,
    );
  }

  /// Writes the complete combined JSONL report without retaining it in memory.
  Future<void> writeJsonTo(StringSink output) async {
    final ordinarySnapshot = _diagnostics.events
        .where(_isResenhaOrdinaryEvent)
        .toList(growable: false);
    final candidateIds = <String>{
      for (final event in ordinarySnapshot.whereType<DiagnosticLogEvent>())
        if (event.attributes[resenhaDiagnosticsEventIdField]
            case final String id)
          id,
    };
    _MergingResenhaReportSink? merged;
    await _resenha.writeJsonReportSnapshotTo(
      candidateEventIds: candidateIds,
      outputForRetainedEventIds: (capturedIds) {
        final ordinaryRecords = [
          for (final event in ordinarySnapshot)
            if (!_duplicatesDeepEvent(event, capturedIds))
              _ordinaryResenhaReportRecord(event),
        ]..sort(_compareResenhaReportRecords);
        return merged = _MergingResenhaReportSink(output, ordinaryRecords);
      },
    );
    merged!.finish();
  }
}

typedef _ResenhaTimelineKey = ({DateTime timestamp, String identity});
typedef _ResenhaTimelineEntry = ({
  Object source,
  _ResenhaTimelineKey key,
  Map<String, Object?> json,
});

/// Retains JSON projections while their immutable recorder events are current.
///
/// Each recorder already publishes its history in stable event objects. Ordered
/// maps preserve the timeline's timestamp-and-identity tie break across updates,
/// leaving each publication as one linear merge instead of a full re-projection
/// and sort.
final class _ResenhaDiagnosticsTimelineProjection {
  _ResenhaDiagnosticsTimelineProjection({this.onEventProjected});

  final ValueChanged<String>? onEventProjected;

  final Map<String, _ResenhaTimelineEntry> _deepByIdentity = {};
  final Map<String, _ResenhaTimelineEntry> _ordinaryByIdentity = {};
  final SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> _deepByOrder =
      SplayTreeMap(_compareKeys);
  final SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry>
  _ordinaryByOrder = SplayTreeMap(_compareKeys);

  List<Map<String, Object?>> project(
    List<ResenhaDiagnosticRecord> deepEvents,
    List<DiagnosticEvent> ordinaryEvents,
  ) {
    final capturedOrdinaryIds = <String>{};
    final seenDeep = <String>{};
    for (final event in deepEvents) {
      if (event.data[resenhaDiagnosticsEventIdField] case final String id) {
        capturedOrdinaryIds.add(id);
      }
      final identity = 'deep:${event.captureId}:${event.sequence}';
      seenDeep.add(identity);
      if (identical(_deepByIdentity[identity]?.source, event)) continue;
      _upsert(
        source: event,
        key: (timestamp: event.timestampUtc, identity: identity),
        json: Map.unmodifiable({
          ...event.toJson(),
          'id': identity,
          'origin': 'deep',
        }),
        byIdentity: _deepByIdentity,
        byOrder: _deepByOrder,
      );
    }
    _removeMissing(seenDeep, _deepByIdentity, _deepByOrder);

    final seenOrdinary = <String>{};
    for (final event in ordinaryEvents) {
      if (!_isResenhaOrdinaryEvent(event) ||
          _duplicatesDeepEvent(event, capturedOrdinaryIds)) {
        continue;
      }
      final identity = 'ordinary:${event.id}';
      seenOrdinary.add(identity);
      if (identical(_ordinaryByIdentity[identity]?.source, event)) continue;
      _upsert(
        source: event,
        key: (timestamp: event.timestampUtc, identity: identity),
        json: _ordinaryResenhaEventJson(event),
        byIdentity: _ordinaryByIdentity,
        byOrder: _ordinaryByOrder,
      );
    }
    _removeMissing(seenOrdinary, _ordinaryByIdentity, _ordinaryByOrder);

    return _merge();
  }

  void _upsert({
    required Object source,
    required _ResenhaTimelineKey key,
    required Map<String, Object?> json,
    required Map<String, _ResenhaTimelineEntry> byIdentity,
    required SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> byOrder,
  }) {
    final held = byIdentity[key.identity];
    if (held != null) byOrder.remove(held.key);

    final entry = (source: source, key: key, json: json);
    byIdentity[key.identity] = entry;
    byOrder[key] = entry;
    onEventProjected?.call(key.identity);
  }

  void _removeMissing(
    Set<String> seen,
    Map<String, _ResenhaTimelineEntry> byIdentity,
    SplayTreeMap<_ResenhaTimelineKey, _ResenhaTimelineEntry> byOrder,
  ) {
    final removed = [
      for (final identity in byIdentity.keys)
        if (!seen.contains(identity)) identity,
    ];
    for (final identity in removed) {
      final entry = byIdentity.remove(identity);
      if (entry != null) byOrder.remove(entry.key);
    }
  }

  List<Map<String, Object?>> _merge() {
    final deep = _deepByOrder.values.iterator;
    final ordinary = _ordinaryByOrder.values.iterator;
    var hasDeep = deep.moveNext();
    var hasOrdinary = ordinary.moveNext();
    final merged = <Map<String, Object?>>[];

    while (hasDeep && hasOrdinary) {
      if (_compareKeys(deep.current.key, ordinary.current.key) <= 0) {
        merged.add(deep.current.json);
        hasDeep = deep.moveNext();
      } else {
        merged.add(ordinary.current.json);
        hasOrdinary = ordinary.moveNext();
      }
    }
    while (hasDeep) {
      merged.add(deep.current.json);
      hasDeep = deep.moveNext();
    }
    while (hasOrdinary) {
      merged.add(ordinary.current.json);
      hasOrdinary = ordinary.moveNext();
    }
    return List.unmodifiable(merged);
  }

  static int _compareKeys(_ResenhaTimelineKey left, _ResenhaTimelineKey right) {
    final timestamp = left.timestamp.compareTo(right.timestamp);
    return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
  }
}

Map<String, Object?> _ordinaryResenhaEventJson(DiagnosticEvent event) {
  final json = <String, Object?>{
    ..._resenhaOrdinaryEventPayload(event),
    'id': 'ordinary:${event.id}',
    'ordinaryEventId': event.id,
    'origin': 'ordinary',
  };
  switch (event) {
    case HttpDiagnosticEvent():
      json['event'] = '${event.method} ${_resenhaHttpPath(event.uri)}';
      json['component'] = 'http';
      json['message'] = [
        event.statusCode,
        event.state.name,
        if (event.totalDuration != null)
          '${event.totalDuration!.inMilliseconds} ms',
      ].join(' · ');
    case ErrorDiagnosticEvent():
      json['event'] = event.operation ?? event.errorType;
      json['component'] = event.source;
    case DiagnosticLogEvent():
      // The view already understands its `name`, `component`, and `message`.
      break;
    case DiagnosticSessionEvent():
      json['event'] = 'session.${event.state.name}';
      json['component'] = event.source;
  }
  return Map.unmodifiable(json);
}

/// Strict projection for data copied from the app-wide recorder into the
/// Resenha surface. General diagnostics may retain a scrubbed exception and
/// response metadata, but those strings can still contain peer addresses or
/// media identifiers. The always-on Resenha stream keeps only allowlisted
/// causal fields; full detail belongs to explicit deep capture.
Map<String, Object?> _resenhaOrdinaryEventPayload(DiagnosticEvent event) =>
    switch (event) {
      HttpDiagnosticEvent() => {
        ...event.commonJson(),
        'method': event.method,
        'uri': _resenhaHttpPath(event.uri),
        'state': event.state.name,
        if (event.statusCode != null) 'statusCode': event.statusCode,
        if (event.headerDuration != null)
          'headerDurationMicros': event.headerDuration!.inMicroseconds,
        if (event.totalDuration != null)
          'totalDurationMicros': event.totalDuration!.inMicroseconds,
        'sentBytes': event.sentBytes,
        'receivedBytes': event.receivedBytes,
        if (event.errorType != null) 'errorType': event.errorType,
      },
      ErrorDiagnosticEvent() => {
        ...event.commonJson(),
        'errorType': event.errorType,
      },
      DiagnosticLogEvent() => event.toJson(),
      DiagnosticSessionEvent() => {
        ...event.commonJson(),
        'state': event.state.name,
      },
    };

String _resenhaHttpPath(String value) {
  final parsed = Uri.tryParse(value);
  if (parsed == null) return '<unavailable-path>';
  final path = parsed.path.isEmpty ? '/' : parsed.path;
  final queryNames = parsed.query
      .split('&')
      .map((part) => part.split('=').first)
      .where((name) => name.isNotEmpty)
      .join('&');
  return queryNames.isEmpty ? path : '$path?$queryNames';
}

bool _isResenhaOrdinaryEvent(DiagnosticEvent event) {
  if (event.source == 'resenha' ||
      event.operation == 'resenha' ||
      (event.operation?.startsWith('resenha.') ?? false) ||
      (event.correlationId?.startsWith('resenha-call-') ?? false)) {
    return true;
  }
  if (event case HttpDiagnosticEvent(:final uri)) {
    final path = Uri.tryParse(uri)?.path ?? uri.split('?').first;
    return path.toLowerCase().contains('/resenha/');
  }
  return false;
}

bool _duplicatesDeepEvent(
  DiagnosticEvent event,
  Set<String> capturedOrdinaryIds,
) {
  if (event is! DiagnosticLogEvent) return false;
  final eventId = event.attributes[resenhaDiagnosticsEventIdField];
  return eventId is String && capturedOrdinaryIds.contains(eventId);
}

typedef _ResenhaReportRecord = ({
  DateTime timestamp,
  String identity,
  String line,
});

_ResenhaReportRecord _ordinaryResenhaReportRecord(DiagnosticEvent event) => (
  timestamp: event.timestampUtc,
  identity: 'ordinary:${event.id}',
  line: jsonEncode({
    'version': resenhaDiagnosticsFormatVersion,
    'record': 'event',
    'origin': 'ordinary',
    'event': _resenhaOrdinaryEventPayload(event),
  }),
);

int _compareResenhaReportRecords(
  _ResenhaReportRecord left,
  _ResenhaReportRecord right,
) {
  final timestamp = left.timestamp.compareTo(right.timestamp);
  return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
}

String _enrichResenhaReportHeader(
  String rawHeader, {
  required int ordinaryEventCount,
}) {
  try {
    final decoded = jsonDecode(rawHeader);
    if (decoded is Map) {
      return jsonEncode({
        for (final entry in decoded.entries) '${entry.key}': entry.value,
        'streams': {
          'ordinary': {
            'retentionHours': diagnosticsRetentionAge.inHours,
            'maximumEvents': diagnosticsRetentionCount,
            'maximumBytes': diagnosticsRetentionBytes,
            'eventCount': ordinaryEventCount,
            'selection': [
              'source=resenha',
              'operation=resenha.*',
              'correlationId=resenha-call-*',
              'HTTP path contains /resenha/',
            ],
          },
          'deep': {
            'requiresExplicitCapture': true,
            'retentionDays': resenhaDiagnosticsRetentionAge.inDays,
            'maximumBytes': resenhaDiagnosticsRetentionBytes,
          },
        },
      });
    }
  } on FormatException {
    // The deep controller currently emits valid JSON. Preserve a future or
    // externally supplied header instead of making report export fail.
  }
  return rawHeader;
}

final class _MergingResenhaReportSink implements StringSink {
  _MergingResenhaReportSink(this.output, this.ordinaryEvents);

  final StringSink output;
  final List<_ResenhaReportRecord> ordinaryEvents;
  final StringBuffer _pending = StringBuffer();
  var _ordinaryIndex = 0;
  var _lineIndex = 0;
  var _finished = false;

  @override
  void write(Object? object) {
    if (_finished) throw StateError('The Resenha report sink is finished.');
    final chunk = '$object';
    var offset = 0;
    while (offset < chunk.length) {
      final newline = chunk.indexOf('\n', offset);
      if (newline < 0) {
        _pending.write(chunk.substring(offset));
        return;
      }
      _pending.write(chunk.substring(offset, newline));
      final line = _pending.toString();
      _pending.clear();
      _emitLine(
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      );
      offset = newline + 1;
    }
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final object in objects) {
      if (!first) write(separator);
      first = false;
      write(object);
    }
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  void finish() {
    if (_finished) return;
    if (_pending.isNotEmpty) _emitLine(_pending.toString());
    while (_ordinaryIndex < ordinaryEvents.length) {
      output.writeln(ordinaryEvents[_ordinaryIndex].line);
      _ordinaryIndex += 1;
    }
    _pending.clear();
    _finished = true;
  }

  void _emitLine(String line) {
    if (_lineIndex == 0) {
      output.writeln(
        _enrichResenhaReportHeader(
          line,
          ordinaryEventCount: ordinaryEvents.length,
        ),
      );
      _lineIndex += 1;
      return;
    }
    if (line.isEmpty) return;
    final deepTimestamp = _resenhaReportLineTimestamp(line);
    if (deepTimestamp != null) {
      while (_ordinaryIndex < ordinaryEvents.length &&
          ordinaryEvents[_ordinaryIndex].timestamp.isBefore(deepTimestamp)) {
        output.writeln(ordinaryEvents[_ordinaryIndex].line);
        _ordinaryIndex += 1;
      }
    }
    output.writeln(line);
    _lineIndex += 1;
  }
}

final RegExp _resenhaReportTimestampPattern = RegExp(
  r'"timestampUtc":"([^"]+)"',
);

String _mergeResenhaReportEvents(
  String deepEvents,
  List<_ResenhaReportRecord> ordinaryEvents,
) {
  if (ordinaryEvents.isEmpty) return deepEvents;
  final output = StringBuffer();
  var ordinaryIndex = 0;
  var offset = 0;
  while (offset < deepEvents.length) {
    final newline = deepEvents.indexOf('\n', offset);
    final end = newline < 0 ? deepEvents.length : newline;
    final line = deepEvents.substring(offset, end);
    offset = newline < 0 ? deepEvents.length : newline + 1;
    if (line.isEmpty) continue;

    final deepTimestamp = _resenhaReportLineTimestamp(line);
    if (deepTimestamp != null) {
      // Deep wins an exact timestamp tie. Its capture sequence is the most
      // precise ordering available for callbacks recorded in the same tick.
      while (ordinaryIndex < ordinaryEvents.length &&
          ordinaryEvents[ordinaryIndex].timestamp.isBefore(deepTimestamp)) {
        output.writeln(ordinaryEvents[ordinaryIndex].line);
        ordinaryIndex += 1;
      }
    }
    output.writeln(line);
  }
  while (ordinaryIndex < ordinaryEvents.length) {
    output.writeln(ordinaryEvents[ordinaryIndex].line);
    ordinaryIndex += 1;
  }
  return output.toString();
}

DateTime? _resenhaReportLineTimestamp(String line) {
  final match = _resenhaReportTimestampPattern.firstMatch(line);
  return match == null ? null : DateTime.tryParse(match.group(1)!)?.toUtc();
}
