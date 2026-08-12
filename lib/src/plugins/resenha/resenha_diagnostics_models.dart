import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:flutter/foundation.dart';

const int resenhaDiagnosticsFormatVersion = 1;
const int resenhaDiagnosticsMaximumRecordBytes = 256 * 1024;
const String resenhaDiagnosticsEventIdField = '_resenhaEventId';

@immutable
final class ResenhaDiagnosticsState {
  const ResenhaDiagnosticsState({
    this.enabled = false,
    this.captureId,
    this.startedAtUtc,
    this.retainedBytes = 0,
    this.droppedRecords = 0,
    this.truncated = false,
  });

  final bool enabled;
  final String? captureId;
  final DateTime? startedAtUtc;
  final int retainedBytes;
  final int droppedRecords;
  final bool truncated;

  ResenhaDiagnosticsState copyWith({
    bool? enabled,
    Object? captureId = _notProvided,
    Object? startedAtUtc = _notProvided,
    int? retainedBytes,
    int? droppedRecords,
    bool? truncated,
  }) => ResenhaDiagnosticsState(
    enabled: enabled ?? this.enabled,
    captureId: identical(captureId, _notProvided)
        ? this.captureId
        : captureId as String?,
    startedAtUtc: identical(startedAtUtc, _notProvided)
        ? this.startedAtUtc
        : (startedAtUtc as DateTime?)?.toUtc(),
    retainedBytes: retainedBytes ?? this.retainedBytes,
    droppedRecords: droppedRecords ?? this.droppedRecords,
    truncated: truncated ?? this.truncated,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    if (captureId != null) 'captureId': captureId,
    if (startedAtUtc != null)
      'startedAtUtc': startedAtUtc!.toUtc().toIso8601String(),
    'retainedBytes': retainedBytes,
    'droppedRecords': droppedRecords,
    'truncated': truncated,
  };
}

const Object _notProvided = Object();

@immutable
final class ResenhaDiagnosticRecord {
  ResenhaDiagnosticRecord({
    required this.sequence,
    String writerId = 'legacy',
    required DateTime timestampUtc,
    required String captureId,
    required String event,
    required String component,
    required this.severity,
    String? correlationId,
    String? message,
    Map<String, Object?> data = const {},
    this.truncated = false,
    String? homeDirectory,
  }) : writerId = ResenhaDiagnosticsRedactor.scrub(
         writerId,
         homeDirectory: homeDirectory,
         maximumLength: 256,
       ),
       timestampUtc = timestampUtc.toUtc(),
       captureId = ResenhaDiagnosticsRedactor.scrub(
         captureId,
         homeDirectory: homeDirectory,
         maximumLength: 256,
       ),
       event = ResenhaDiagnosticsRedactor.scrub(
         event,
         homeDirectory: homeDirectory,
         maximumLength: 1024,
       ),
       component = ResenhaDiagnosticsRedactor.scrub(
         component,
         homeDirectory: homeDirectory,
         maximumLength: 1024,
       ),
       correlationId = correlationId == null
           ? null
           : ResenhaDiagnosticsRedactor.scrub(
               correlationId,
               homeDirectory: homeDirectory,
               maximumLength: 4096,
             ),
       message = message == null
           ? null
           : ResenhaDiagnosticsRedactor.scrub(
               message,
               homeDirectory: homeDirectory,
             ),
       data = Map.unmodifiable(
         ResenhaDiagnosticsRedactor.data(data, homeDirectory: homeDirectory),
       );

  /// Identifies the app process which allocated [sequence].
  ///
  /// Sequences are intentionally process-local. Combining both fields keeps
  /// persisted identities collision-safe when two Linux app processes append
  /// to the same diagnostics store.
  final String writerId;
  final int sequence;
  final DateTime timestampUtc;
  final String captureId;
  final String event;
  final String component;
  final DiagnosticSeverity severity;
  final String? correlationId;
  final String? message;
  final Map<String, Object?> data;
  final bool truncated;

  String get identity => '$writerId:$sequence';

  String get searchText {
    try {
      return [
        event,
        component,
        severity.name,
        correlationId,
        message,
        jsonEncode(data),
      ].whereType<String>().join(' ').toLowerCase();
    } on Object {
      return '$event $component ${severity.name}'.toLowerCase();
    }
  }

  Map<String, Object?> toJson() => {
    'writerId': writerId,
    'sequence': sequence,
    'timestampUtc': timestampUtc.toIso8601String(),
    'captureId': captureId,
    'event': event,
    'component': component,
    'severity': severity.name,
    if (correlationId != null) 'correlationId': correlationId,
    if (message != null) 'message': message,
    'data': data,
    'truncated': truncated,
  };

  ResenhaDiagnosticRecord copyWith({
    String? writerId,
    int? sequence,
    DateTime? timestampUtc,
    String? captureId,
    String? event,
    String? component,
    DiagnosticSeverity? severity,
    Object? correlationId = _notProvided,
    Object? message = _notProvided,
    Map<String, Object?>? data,
    bool? truncated,
  }) => ResenhaDiagnosticRecord(
    writerId: writerId ?? this.writerId,
    sequence: sequence ?? this.sequence,
    timestampUtc: timestampUtc ?? this.timestampUtc,
    captureId: captureId ?? this.captureId,
    event: event ?? this.event,
    component: component ?? this.component,
    severity: severity ?? this.severity,
    correlationId: identical(correlationId, _notProvided)
        ? this.correlationId
        : correlationId as String?,
    message: identical(message, _notProvided)
        ? this.message
        : message as String?,
    data: data ?? this.data,
    truncated: truncated ?? this.truncated,
  );

  static ResenhaDiagnosticRecord? fromJson(
    Object? value, {
    String? homeDirectory,
  }) {
    if (value is! Map) return null;
    final writerId = value['writerId'];
    final sequence = value['sequence'];
    final timestamp = value['timestampUtc'];
    final captureId = value['captureId'];
    final event = value['event'];
    final component = value['component'];
    final severityName = value['severity'];
    final correlationId = value['correlationId'];
    final message = value['message'];
    final data = value['data'];
    final truncated = value['truncated'];
    final timestampUtc = timestamp is String
        ? DateTime.tryParse(timestamp)?.toUtc()
        : null;
    final severity = severityName is String
        ? DiagnosticSeverity.values
              .where((candidate) => candidate.name == severityName)
              .firstOrNull
        : null;
    if (writerId is! String? ||
        sequence is! int ||
        sequence < 0 ||
        timestampUtc == null ||
        captureId is! String ||
        event is! String ||
        component is! String ||
        severity == null ||
        correlationId is! String? ||
        message is! String? ||
        data is! Map ||
        truncated is! bool) {
      return null;
    }
    return ResenhaDiagnosticRecord(
      writerId: writerId ?? 'legacy',
      sequence: sequence,
      timestampUtc: timestampUtc,
      captureId: captureId,
      event: event,
      component: component,
      severity: severity,
      correlationId: correlationId,
      message: message,
      data: {for (final entry in data.entries) '${entry.key}': entry.value},
      truncated: truncated,
      homeDirectory: homeDirectory,
    );
  }
}

int resenhaDiagnosticSerializedBytes(ResenhaDiagnosticRecord record) =>
    utf8.encode(jsonEncode(resenhaDiagnosticLine(record))).length + 1;

Map<String, Object?> resenhaDiagnosticLine(ResenhaDiagnosticRecord record) => {
  'version': resenhaDiagnosticsFormatVersion,
  'record': 'event',
  'origin': 'deep',
  'event': record.toJson(),
};

ResenhaDiagnosticRecord fitResenhaDiagnosticRecord(
  ResenhaDiagnosticRecord record, {
  int maximumBytes = resenhaDiagnosticsMaximumRecordBytes,
}) {
  if (resenhaDiagnosticSerializedBytes(record) <= maximumBytes) return record;

  final payload = jsonEncode({
    if (record.message != null) 'message': record.message,
    'data': record.data,
  });
  final payloadBytes = utf8.encode(payload);
  ResenhaDiagnosticRecord candidate(String prefix) => record.copyWith(
    message: null,
    data: {
      '_truncatedPayloadPrefix': prefix,
      '_originalPayloadBytes': payloadBytes.length,
    },
    truncated: true,
  );

  var lower = 0;
  var upper = payloadBytes.length;
  var best = candidate('');
  while (lower <= upper) {
    final middle = lower + ((upper - lower) ~/ 2);
    final prefix = utf8.decode(
      payloadBytes.sublist(0, middle),
      allowMalformed: true,
    );
    final attempted = candidate(prefix);
    if (resenhaDiagnosticSerializedBytes(attempted) <= maximumBytes) {
      best = attempted;
      lower = middle + 1;
    } else {
      upper = middle - 1;
    }
  }
  return best;
}

abstract final class ResenhaDiagnosticsRedactor {
  static final RegExp _url = RegExp(
    r'''\b(?:https?|wss?|turns?|stuns?):(?://)?[^\s<>"']+''',
    caseSensitive: false,
  );
  static final RegExp _sensitiveAssignment = RegExp(
    r'''["']?\b(authorization|proxy[-_ ]?authorization|cookie|set[-_ ]?cookie|x[-_ ]?api[-_ ]?key|api[-_ ]?key|access[-_ ]?token|refresh[-_ ]?token|auth[-_ ]?token|token|password|passwd|secret|credential|client[-_ ]?(?:id|secret)|ice[-_ ]?(?:pwd|password|ufrag)|livekit[-_ ]?(?:token|jwt|key|secret|credential|password)|turn[-_ ]?(?:username|token|key|secret|credential|password))\b["']?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;]+)''',
    caseSensitive: false,
  );
  static final RegExp _authorization = RegExp(
    r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])',
  );
  static final RegExp _iceCredential = RegExp(
    r'(^|\r?\n)(a=ice-(?:pwd|ufrag):)[^\r\n]*',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _inlineIceCredential = RegExp(
    r'\b(ice[-_ ]?(?:pwd|password|ufrag))\b\s*[:=]\s*[^\s,;]+',
    caseSensitive: false,
  );
  static final RegExp _iceServerRepresentation = RegExp(
    r'\b(?:rtc[-_ ]?)?(?:ice|turn)[-_ ]?servers?\b\s*(?:[:=]\s*)?(?:\[[\s\S]{0,4096}?\]|\{[\s\S]{0,4096}?\}|\([\s\S]{0,4096}?\))',
    caseSensitive: false,
  );
  static final RegExp _iceServerUsername = RegExp(
    r'''(["']?\busername\b["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;\]\}]+)''',
    caseSensitive: false,
  );
  static final RegExp _queryAssignment = RegExp(
    r'([?&][A-Za-z0-9_.~%+-]+)=[^\s&#]*',
  );

  static String scrub(
    Object? value, {
    String? homeDirectory,
    int? maximumLength,
  }) {
    var text = _safeString(value);
    if (text.isEmpty) return text;
    text = text.replaceAllMapped(
      _iceCredential,
      (match) => '${match.group(1)}${match.group(2)}<redacted>',
    );
    text = text.replaceAllMapped(
      _inlineIceCredential,
      (match) => '${match.group(1)}=<redacted>',
    );
    text = text.replaceAllMapped(
      _iceServerRepresentation,
      (match) => match
          .group(0)!
          .replaceAllMapped(
            _iceServerUsername,
            (username) => '${username.group(1)}<redacted>',
          ),
    );
    // Strip complete URL query values before assignment redaction can mistake
    // an entire `token=x&room=y` suffix for one token value.
    text = text.replaceAllMapped(_url, (match) => _redactUri(match.group(0)!));
    text = text.replaceAllMapped(
      _sensitiveAssignment,
      (match) => '${match.group(1)}=<redacted>',
    );
    text = text.replaceAllMapped(
      _authorization,
      (match) => '${match.group(1)} <redacted>',
    );
    text = text.replaceAll(_jwt, '<redacted-jwt>');
    text = text.replaceAllMapped(_queryAssignment, (match) => match.group(1)!);
    for (final home in _homeDirectories(homeDirectory)) {
      text = text.replaceAll(home, '<home>');
    }
    if (maximumLength != null && text.length > maximumLength) {
      return '${text.substring(0, maximumLength)}…<truncated>';
    }
    return text;
  }

  static Map<String, Object?> data(
    Map<String, Object?> input, {
    String? homeDirectory,
  }) {
    final seen = HashSet<Object>.identity();
    final sanitized = _sanitizeValue(
      input,
      homeDirectory: homeDirectory,
      seen: seen,
      depth: 0,
    );
    return sanitized is Map<String, Object?> ? sanitized : const {};
  }

  static Object? _sanitizeValue(
    Object? value, {
    required String? homeDirectory,
    required HashSet<Object> seen,
    required int depth,
    String? key,
  }) {
    if (key != null && _sensitiveKey(key)) return '<redacted>';
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : '$value';
    if (value is String || value is Uri) {
      return scrub(value, homeDirectory: homeDirectory);
    }
    if (depth >= 16) return '<maximum-depth>';
    if (value is Map) {
      if (!seen.add(value)) return '<cyclic>';
      try {
        final result = <String, Object?>{};
        final turnServer = _isTurnServerMap(value);
        var count = 0;
        for (final entry in value.entries) {
          if (count >= 4096) {
            result['_truncatedEntries'] = value.length - count;
            break;
          }
          final safeKey = scrub(
            entry.key,
            homeDirectory: homeDirectory,
            maximumLength: 1024,
          );
          result[safeKey] = _sanitizeValue(
            entry.value,
            homeDirectory: homeDirectory,
            seen: seen,
            depth: depth + 1,
            key:
                turnServer &&
                    safeKey.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '') ==
                        'username'
                ? 'turnUsername'
                : safeKey,
          );
          count += 1;
        }
        return Map<String, Object?>.unmodifiable(result);
      } finally {
        seen.remove(value);
      }
    }
    if (value is Iterable) {
      if (!seen.add(value)) return '<cyclic>';
      try {
        final result = <Object?>[];
        var count = 0;
        for (final item in value) {
          if (count >= 4096) {
            result.add('<truncated-items>');
            break;
          }
          result.add(
            _sanitizeValue(
              item,
              homeDirectory: homeDirectory,
              seen: seen,
              depth: depth + 1,
            ),
          );
          count += 1;
        }
        return List<Object?>.unmodifiable(result);
      } finally {
        seen.remove(value);
      }
    }
    return scrub(value, homeDirectory: homeDirectory);
  }

  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (normalized == 'clientid' ||
        normalized.contains('icepwd') ||
        normalized.contains('icepassword') ||
        normalized.contains('iceufrag')) {
      return true;
    }
    if (normalized.endsWith('id')) return false;
    if ({
      'authorization',
      'proxyauthorization',
      'cookie',
      'setcookie',
      'password',
      'passwd',
      'secret',
      'credential',
      'token',
    }.contains(normalized)) {
      return true;
    }
    if (normalized.contains('apikey') ||
        normalized.endsWith('token') ||
        normalized.endsWith('password') ||
        normalized.endsWith('secret')) {
      return true;
    }
    if (normalized.contains('livekit')) {
      return normalized.contains('token') ||
          normalized.contains('jwt') ||
          normalized.contains('key') ||
          normalized.contains('secret') ||
          normalized.contains('credential') ||
          normalized.contains('password');
    }
    if (normalized.contains('turn')) {
      return normalized.contains('username') ||
          normalized.contains('token') ||
          normalized.contains('key') ||
          normalized.contains('secret') ||
          normalized.contains('credential') ||
          normalized.contains('password');
    }
    return false;
  }

  static bool _isTurnServerMap(Map<dynamic, dynamic> value) {
    for (final entry in value.entries) {
      final key = _safeString(
        entry.key,
      ).toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
      if (key != 'url' && key != 'urls') continue;
      final urls = entry.value is Iterable
          ? entry.value as Iterable<dynamic>
          : [entry.value];
      for (final url in urls) {
        final text = _safeString(url).trimLeft().toLowerCase();
        if (text.startsWith('turn:') || text.startsWith('turns:')) return true;
      }
    }
    return false;
  }

  static String _redactUri(String raw) {
    var suffix = '';
    while (raw.isNotEmpty && '.,;)]}'.contains(raw[raw.length - 1])) {
      suffix = '${raw[raw.length - 1]}$suffix';
      raw = raw.substring(0, raw.length - 1);
    }
    final fragment = raw.indexOf('#');
    final withoutFragment = fragment < 0 ? raw : raw.substring(0, fragment);
    final question = withoutFragment.indexOf('?');
    var base = question < 0
        ? withoutFragment
        : withoutFragment.substring(0, question);
    final query = question < 0 ? '' : withoutFragment.substring(question + 1);
    final authorityMarker = base.indexOf('://');
    if (authorityMarker >= 0) {
      final authorityStart = authorityMarker + 3;
      var authorityEnd = base.indexOf('/', authorityStart);
      if (authorityEnd < 0) authorityEnd = base.length;
      final at = base.lastIndexOf('@', authorityEnd);
      if (at >= authorityStart) {
        base = base.replaceRange(authorityStart, at + 1, '');
      }
    } else if (base.toLowerCase().startsWith('turn')) {
      final colon = base.indexOf(':');
      final at = base.lastIndexOf('@');
      if (colon >= 0 && at > colon) {
        base = base.replaceRange(colon + 1, at + 1, '');
      }
    }
    final names = <String>[];
    for (final part in query.split('&')) {
      if (part.isEmpty) continue;
      final equals = part.indexOf('=');
      final name = equals < 0 ? part : part.substring(0, equals);
      names.add(_safeQueryName(name));
    }
    return '${names.isEmpty ? base : '$base?${names.join('&')}'}$suffix';
  }

  static String _safeQueryName(String value) {
    try {
      return Uri.encodeQueryComponent(Uri.decodeQueryComponent(value));
    } on ArgumentError {
      return 'invalid-query-name';
    }
  }

  static Set<String> _homeDirectories(String? injected) {
    try {
      return {
        if (injected != null && injected.isNotEmpty) injected,
        if (Platform.environment['HOME'] case final home? when home.isNotEmpty)
          home,
        if (Platform.environment['USERPROFILE'] case final home?
            when home.isNotEmpty)
          home,
      };
    } on Object {
      return {if (injected != null && injected.isNotEmpty) injected};
    }
  }

  static String _safeString(Object? value) {
    if (value == null) return '';
    try {
      return value.toString();
    } on Object {
      return '<unprintable ${value.runtimeType}>';
    }
  }
}
