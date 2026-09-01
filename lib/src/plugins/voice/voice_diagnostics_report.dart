import 'dart:collection';
import 'dart:convert';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'voice_diagnostics.dart';
import 'voice_report_exporter.dart';

/// The ordinary recorder intentionally retains more detail than Voice can
/// safely expose without explicit capture. This boundary owns that projection,
/// exact de-duplication against deep history, and chronological report merge so
/// callers cannot accidentally compose the two streams with different privacy
/// or ordering rules.
final class VoiceDiagnosticsReport {
  VoiceDiagnosticsReport({
    required PluginDiagnosticsReadExportHost diagnostics,
    required VoiceDiagnosticsController voice,
    @visibleForTesting ValueChanged<String>? onEventProjected,
  }) : this._(diagnostics, voice, onEventProjected);

  VoiceDiagnosticsReport._(
    this._diagnostics,
    this._voice,
    ValueChanged<String>? onEventProjected,
  ) : _timeline = _VoiceDiagnosticsTimelineProjection(
        onEventProjected: onEventProjected,
      );

  final PluginDiagnosticsReadExportHost _diagnostics;
  final VoiceDiagnosticsController _voice;
  final _VoiceDiagnosticsTimelineProjection _timeline;

  List<Map<String, Object?>> get events =>
      _timeline.project(_voice.eventsTail, _diagnostics.events);

  Future<String> buildJson() async {
    final deepReport = await _voice.buildJsonReport();
    final capturedOrdinaryIds = voiceDiagnosticsEventIdsInJsonReport(
      deepReport,
    );
    final ordinaryEvents = _diagnostics.events.where(
      (event) =>
          _isVoiceOrdinaryEvent(event) &&
          !_duplicatesDeepEvent(event, capturedOrdinaryIds),
    );
    final ordinaryRecords = [
      for (final event in ordinaryEvents) _ordinaryVoiceReportRecord(event),
    ]..sort(_compareVoiceReportRecords);

    final firstLineEnd = deepReport.indexOf('\n');
    if (firstLineEnd < 0) return deepReport;
    final rawHeader = deepReport.substring(0, firstLineEnd);
    final header = _enrichVoiceReportHeader(
      rawHeader,
      ordinaryEventCount: ordinaryRecords.length,
    );

    final deepEvents = deepReport.substring(firstLineEnd + 1);
    return '$header\n${_mergeVoiceReportEvents(deepEvents, ordinaryRecords)}';
  }

  Future<VoiceClipboardReport> buildClipboard(int byteLimit) async {
    // A full deep report below the clipboard threshold is cheap enough to
    // build and lets the exact ordinary/deep de-duplicator decide whether the
    // combined report still fits. Above the threshold, never materialize the
    // retained (up to 50 MiB) history merely to throw its oldest bytes away.
    if (_voice.state.retainedBytes <= byteLimit) {
      return boundVoiceReportForClipboard(
        await buildJson(),
        byteLimit: byteLimit,
      );
    }

    final capturedOrdinaryIds = <String>{
      for (final event in _voice.eventsTail)
        if (event.data[voiceDiagnosticsEventIdField] case final String id) id,
    };
    final recent = <_VoiceReportRecord>[
      for (final event in _diagnostics.events)
        if (_isVoiceOrdinaryEvent(event) &&
            !_duplicatesDeepEvent(event, capturedOrdinaryIds))
          _ordinaryVoiceReportRecord(event),
      for (final event in _voice.eventsTail)
        (
          timestamp: event.timestampUtc,
          identity: 'deep:${event.identity}',
          line: jsonEncode(voiceDiagnosticLine(event)),
        ),
    ]..sort(_compareVoiceReportRecords);
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
      'deepRetainedBytes': _voice.state.retainedBytes,
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
    return VoiceClipboardReport(
      '$marker\n${retained.reversed.join('\n')}',
      truncated: true,
    );
  }

  Future<void> writeJsonTo(StringSink output) async {
    final ordinarySnapshot = _diagnostics.events
        .where(_isVoiceOrdinaryEvent)
        .toList(growable: false);
    final candidateIds = <String>{
      for (final event in ordinarySnapshot.whereType<DiagnosticLogEvent>())
        if (event.attributes[voiceDiagnosticsEventIdField] case final String id)
          id,
    };
    _MergingVoiceReportSink? merged;
    await _voice.writeJsonReportSnapshotTo(
      candidateEventIds: candidateIds,
      outputForRetainedEventIds: (capturedIds) {
        final ordinaryRecords = [
          for (final event in ordinarySnapshot)
            if (!_duplicatesDeepEvent(event, capturedIds))
              _ordinaryVoiceReportRecord(event),
        ]..sort(_compareVoiceReportRecords);
        return merged = _MergingVoiceReportSink(output, ordinaryRecords);
      },
    );
    merged!.finish();
  }
}

typedef _VoiceTimelineKey = ({DateTime timestamp, String identity});
typedef _VoiceTimelineEntry = ({
  Object source,
  _VoiceTimelineKey key,
  Map<String, Object?> json,
});

/// Each recorder already publishes its history in stable event objects. Ordered
/// maps preserve the timeline's timestamp-and-identity tie break across updates,
/// leaving each publication as one linear merge instead of a full re-projection
/// and sort.
final class _VoiceDiagnosticsTimelineProjection {
  _VoiceDiagnosticsTimelineProjection({this.onEventProjected});

  final ValueChanged<String>? onEventProjected;

  final Map<String, _VoiceTimelineEntry> _deepByIdentity = {};
  final Map<String, _VoiceTimelineEntry> _ordinaryByIdentity = {};
  final SplayTreeMap<_VoiceTimelineKey, _VoiceTimelineEntry> _deepByOrder =
      SplayTreeMap(_compareKeys);
  final SplayTreeMap<_VoiceTimelineKey, _VoiceTimelineEntry> _ordinaryByOrder =
      SplayTreeMap(_compareKeys);

  List<Map<String, Object?>> project(
    List<VoiceDiagnosticRecord> deepEvents,
    List<DiagnosticEvent> ordinaryEvents,
  ) {
    final capturedOrdinaryIds = <String>{};
    final seenDeep = <String>{};
    for (final event in deepEvents) {
      if (event.data[voiceDiagnosticsEventIdField] case final String id) {
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
      if (!_isVoiceOrdinaryEvent(event) ||
          _duplicatesDeepEvent(event, capturedOrdinaryIds)) {
        continue;
      }
      final identity = 'ordinary:${event.id}';
      seenOrdinary.add(identity);
      if (identical(_ordinaryByIdentity[identity]?.source, event)) continue;
      _upsert(
        source: event,
        key: (timestamp: event.timestampUtc, identity: identity),
        json: _ordinaryVoiceEventJson(event),
        byIdentity: _ordinaryByIdentity,
        byOrder: _ordinaryByOrder,
      );
    }
    _removeMissing(seenOrdinary, _ordinaryByIdentity, _ordinaryByOrder);

    return _merge();
  }

  void _upsert({
    required Object source,
    required _VoiceTimelineKey key,
    required Map<String, Object?> json,
    required Map<String, _VoiceTimelineEntry> byIdentity,
    required SplayTreeMap<_VoiceTimelineKey, _VoiceTimelineEntry> byOrder,
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
    Map<String, _VoiceTimelineEntry> byIdentity,
    SplayTreeMap<_VoiceTimelineKey, _VoiceTimelineEntry> byOrder,
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

  static int _compareKeys(_VoiceTimelineKey left, _VoiceTimelineKey right) {
    final timestamp = left.timestamp.compareTo(right.timestamp);
    return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
  }
}

Map<String, Object?> _ordinaryVoiceEventJson(DiagnosticEvent event) {
  final json = <String, Object?>{
    ..._voiceOrdinaryEventPayload(event),
    'id': 'ordinary:${event.id}',
    'ordinaryEventId': event.id,
    'origin': 'ordinary',
  };
  switch (event) {
    case HttpDiagnosticEvent():
      json['event'] = '${event.method} ${_voiceHttpPath(event.uri)}';
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
      break;
    case DiagnosticSessionEvent():
      json['event'] = 'session.${event.state.name}';
      json['component'] = event.source;
  }
  return Map.unmodifiable(json);
}

/// Strict projection for data copied from the app-wide recorder into the
/// Voice surface. General diagnostics may retain a scrubbed exception and
/// response metadata, but those strings can still contain peer addresses or
/// media identifiers. The always-on Voice stream keeps only allowlisted
/// causal fields; full detail belongs to explicit deep capture.
Map<String, Object?> _voiceOrdinaryEventPayload(DiagnosticEvent event) =>
    switch (event) {
      HttpDiagnosticEvent() => {
        ...event.commonJson(),
        'method': event.method,
        'uri': _voiceHttpPath(event.uri),
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

String _voiceHttpPath(String value) {
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

bool _isVoiceOrdinaryEvent(DiagnosticEvent event) {
  if (event.source == 'voice' ||
      event.operation == 'voice' ||
      (event.operation?.startsWith('voice.') ?? false) ||
      (event.correlationId?.startsWith('voice-call-') ?? false)) {
    return true;
  }
  if (event case HttpDiagnosticEvent(:final uri)) {
    final path = Uri.tryParse(uri)?.path ?? uri.split('?').first;
    return path.toLowerCase().contains('/voice/');
  }
  return false;
}

bool _duplicatesDeepEvent(
  DiagnosticEvent event,
  Set<String> capturedOrdinaryIds,
) {
  if (event is! DiagnosticLogEvent) return false;
  final eventId = event.attributes[voiceDiagnosticsEventIdField];
  return eventId is String && capturedOrdinaryIds.contains(eventId);
}

typedef _VoiceReportRecord = ({
  DateTime timestamp,
  String identity,
  String line,
});

_VoiceReportRecord _ordinaryVoiceReportRecord(DiagnosticEvent event) => (
  timestamp: event.timestampUtc,
  identity: 'ordinary:${event.id}',
  line: jsonEncode({
    'version': voiceDiagnosticsFormatVersion,
    'record': 'event',
    'origin': 'ordinary',
    'event': _voiceOrdinaryEventPayload(event),
  }),
);

int _compareVoiceReportRecords(
  _VoiceReportRecord left,
  _VoiceReportRecord right,
) {
  final timestamp = left.timestamp.compareTo(right.timestamp);
  return timestamp != 0 ? timestamp : left.identity.compareTo(right.identity);
}

String _enrichVoiceReportHeader(
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
              'source=voice',
              'operation=voice.*',
              'correlationId=voice-call-*',
              'HTTP path contains /voice/',
            ],
          },
          'deep': {
            'requiresExplicitCapture': true,
            'retentionDays': voiceDiagnosticsRetentionAge.inDays,
            'maximumBytes': voiceDiagnosticsRetentionBytes,
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

final class _MergingVoiceReportSink implements StringSink {
  _MergingVoiceReportSink(this.output, this.ordinaryEvents);

  final StringSink output;
  final List<_VoiceReportRecord> ordinaryEvents;
  final StringBuffer _pending = StringBuffer();
  var _ordinaryIndex = 0;
  var _lineIndex = 0;
  var _finished = false;

  @override
  void write(Object? object) {
    if (_finished) throw StateError('The Voice report sink is finished.');
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
        _enrichVoiceReportHeader(
          line,
          ordinaryEventCount: ordinaryEvents.length,
        ),
      );
      _lineIndex += 1;
      return;
    }
    if (line.isEmpty) return;
    final deepTimestamp = _voiceReportLineTimestamp(line);
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

final RegExp _voiceReportTimestampPattern = RegExp(r'"timestampUtc":"([^"]+)"');

String _mergeVoiceReportEvents(
  String deepEvents,
  List<_VoiceReportRecord> ordinaryEvents,
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

    final deepTimestamp = _voiceReportLineTimestamp(line);
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

DateTime? _voiceReportLineTimestamp(String line) {
  final match = _voiceReportTimestampPattern.firstMatch(line);
  return match == null ? null : DateTime.tryParse(match.group(1)!)?.toUtc();
}
