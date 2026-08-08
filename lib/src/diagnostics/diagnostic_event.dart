import 'dart:convert';

import 'package:discourse_native/src/diagnostics/diagnostics_redactor.dart';

enum DiagnosticEventKind { session, http, error }

enum DiagnosticSeverity { debug, info, warning, error }

enum DiagnosticHttpState { pending, completed, failed, cancelled, interrupted }

enum DiagnosticSessionState { started, ended }

/// One immutable item in the diagnostics timeline.
sealed class DiagnosticEvent {
  DiagnosticEvent({
    required this.id,
    required this.sessionId,
    required this.sequence,
    required DateTime timestampUtc,
    required DateTime updatedAtUtc,
    required this.severity,
    required String source,
    String? operation,
    String? correlationId,
    required this.handled,
    required this.degraded,
  }) : timestampUtc = timestampUtc.toUtc(),
       updatedAtUtc = updatedAtUtc.toUtc(),
       source = DiagnosticsRedactor.scrub(source),
       operation = operation == null
           ? null
           : DiagnosticsRedactor.scrub(operation),
       correlationId = correlationId == null
           ? null
           : DiagnosticsRedactor.scrub(correlationId);

  final String id;
  final String sessionId;
  final int sequence;
  final DateTime timestampUtc;
  final DateTime updatedAtUtc;
  final DiagnosticSeverity severity;
  final String source;
  final String? operation;
  final String? correlationId;
  final bool handled;
  final bool degraded;

  DiagnosticEventKind get kind;

  bool get isError;

  String get searchText;

  Map<String, Object?> toJson();

  static DiagnosticEvent? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<Object?, Object?>();
    final kind = _enumByName(DiagnosticEventKind.values, json['kind']);
    return switch (kind) {
      DiagnosticEventKind.session => DiagnosticSessionEvent.fromJson(json),
      DiagnosticEventKind.http => HttpDiagnosticEvent.fromJson(json),
      DiagnosticEventKind.error => ErrorDiagnosticEvent.fromJson(json),
      null => null,
    };
  }

  Map<String, Object?> commonJson() => {
    'id': id,
    'kind': kind.name,
    'sessionId': sessionId,
    'sequence': sequence,
    'timestampUtc': timestampUtc.toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toIso8601String(),
    'severity': severity.name,
    'source': source,
    if (operation != null) 'operation': operation,
    if (correlationId != null) 'correlationId': correlationId,
    'handled': handled,
    'degraded': degraded,
  };

  @override
  String toString() => jsonEncode(toJson());
}

final class DiagnosticSessionEvent extends DiagnosticEvent {
  DiagnosticSessionEvent({
    required super.id,
    required super.sessionId,
    required super.sequence,
    required super.timestampUtc,
    required super.updatedAtUtc,
    super.severity = DiagnosticSeverity.info,
    super.source = 'diagnostics',
    super.operation,
    super.correlationId,
    super.handled = true,
    super.degraded = false,
    required this.state,
    String? message,
  }) : message = message == null ? null : DiagnosticsRedactor.scrub(message);

  final DiagnosticSessionState state;
  final String? message;

  @override
  DiagnosticEventKind get kind => DiagnosticEventKind.session;

  @override
  bool get isError => false;

  @override
  String get searchText => [
    source,
    operation,
    correlationId,
    state.name,
    message,
  ].whereType<String>().join(' ').toLowerCase();

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'state': state.name,
    if (message != null) 'message': message,
  };

  static DiagnosticSessionEvent? fromJson(Map<Object?, Object?> json) {
    final common = _CommonFields.fromJson(json);
    final state = _enumByName(DiagnosticSessionState.values, json['state']);
    if (common == null || state == null) return null;
    return DiagnosticSessionEvent(
      id: common.id,
      sessionId: common.sessionId,
      sequence: common.sequence,
      timestampUtc: common.timestampUtc,
      updatedAtUtc: common.updatedAtUtc,
      severity: common.severity,
      source: common.source,
      operation: common.operation,
      correlationId: common.correlationId,
      handled: common.handled,
      degraded: common.degraded,
      state: state,
      message: json['message'] as String?,
    );
  }
}

final class DiagnosticRedirect {
  DiagnosticRedirect({
    required this.statusCode,
    this.method,
    required Object location,
  }) : location = DiagnosticsRedactor.uri(location);

  final int statusCode;
  final String? method;
  final String location;

  Map<String, Object?> toJson() => {
    'statusCode': statusCode,
    if (method != null) 'method': method,
    'location': location,
  };

  static DiagnosticRedirect? fromJson(Object? value) {
    if (value is! Map) return null;
    final statusCode = value['statusCode'];
    final method = value['method'];
    final location = value['location'];
    if (statusCode is! int || method is! String? || location is! String) {
      return null;
    }
    return DiagnosticRedirect(
      statusCode: statusCode,
      method: method,
      location: location,
    );
  }
}

final class HttpDiagnosticEvent extends DiagnosticEvent {
  HttpDiagnosticEvent({
    required super.id,
    required super.sessionId,
    required super.sequence,
    required super.timestampUtc,
    required super.updatedAtUtc,
    required super.severity,
    super.source = 'http',
    super.operation,
    super.correlationId,
    super.handled = true,
    super.degraded = false,
    required String method,
    required Object uri,
    required this.state,
    this.statusCode,
    String? reasonPhrase,
    Iterable<DiagnosticRedirect> redirects = const [],
    Map<String, List<String>> responseHeaders = const {},
    this.headerDuration,
    this.totalDuration,
    this.sentBytes = 0,
    this.receivedBytes = 0,
    String? errorType,
    String? errorMessage,
    String? stackTrace,
  }) : method = method.toUpperCase(),
       uri = DiagnosticsRedactor.uri(uri),
       reasonPhrase = reasonPhrase == null
           ? null
           : DiagnosticsRedactor.scrub(reasonPhrase),
       redirects = List.unmodifiable(redirects),
       responseHeaders = DiagnosticsRedactor.responseHeaders(responseHeaders),
       errorType = errorType == null
           ? null
           : DiagnosticsRedactor.scrub(errorType),
       errorMessage = errorMessage == null
           ? null
           : DiagnosticsRedactor.scrub(errorMessage),
       stackTrace = stackTrace == null
           ? null
           : DiagnosticsRedactor.scrub(stackTrace);

  final String method;
  final String uri;
  final DiagnosticHttpState state;
  final int? statusCode;
  final String? reasonPhrase;
  final List<DiagnosticRedirect> redirects;
  final Map<String, List<String>> responseHeaders;
  final Duration? headerDuration;
  final Duration? totalDuration;
  final int sentBytes;
  final int receivedBytes;
  final String? errorType;
  final String? errorMessage;
  final String? stackTrace;

  @override
  DiagnosticEventKind get kind => DiagnosticEventKind.http;

  @override
  bool get isError =>
      state == DiagnosticHttpState.failed ||
      (statusCode != null && statusCode! >= 400);

  @override
  String get searchText => [
    source,
    operation,
    correlationId,
    method,
    uri,
    state.name,
    statusCode?.toString(),
    reasonPhrase,
    errorType,
    errorMessage,
  ].whereType<String>().join(' ').toLowerCase();

  HttpDiagnosticEvent copyWith({
    int? sequence,
    DateTime? updatedAtUtc,
    DiagnosticSeverity? severity,
    DiagnosticHttpState? state,
    int? statusCode,
    String? reasonPhrase,
    Iterable<DiagnosticRedirect>? redirects,
    Map<String, List<String>>? responseHeaders,
    Duration? headerDuration,
    Duration? totalDuration,
    int? sentBytes,
    int? receivedBytes,
    String? errorType,
    String? errorMessage,
    String? stackTrace,
  }) => HttpDiagnosticEvent(
    id: id,
    sessionId: sessionId,
    sequence: sequence ?? this.sequence,
    timestampUtc: timestampUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    severity: severity ?? this.severity,
    source: source,
    operation: operation,
    correlationId: correlationId,
    handled: handled,
    degraded: degraded,
    method: method,
    uri: uri,
    state: state ?? this.state,
    statusCode: statusCode ?? this.statusCode,
    reasonPhrase: reasonPhrase ?? this.reasonPhrase,
    redirects: redirects ?? this.redirects,
    responseHeaders: responseHeaders ?? this.responseHeaders,
    headerDuration: headerDuration ?? this.headerDuration,
    totalDuration: totalDuration ?? this.totalDuration,
    sentBytes: sentBytes ?? this.sentBytes,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    errorType: errorType ?? this.errorType,
    errorMessage: errorMessage ?? this.errorMessage,
    stackTrace: stackTrace ?? this.stackTrace,
  );

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'method': method,
    'uri': uri,
    'state': state.name,
    if (statusCode != null) 'statusCode': statusCode,
    if (reasonPhrase != null) 'reasonPhrase': reasonPhrase,
    'redirects': [for (final redirect in redirects) redirect.toJson()],
    'responseHeaders': responseHeaders,
    if (headerDuration != null)
      'headerDurationMicros': headerDuration!.inMicroseconds,
    if (totalDuration != null)
      'totalDurationMicros': totalDuration!.inMicroseconds,
    'sentBytes': sentBytes,
    'receivedBytes': receivedBytes,
    if (errorType != null) 'errorType': errorType,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };

  static HttpDiagnosticEvent? fromJson(Map<Object?, Object?> json) {
    final common = _CommonFields.fromJson(json);
    final state = _enumByName(DiagnosticHttpState.values, json['state']);
    final method = json['method'];
    final uri = json['uri'];
    if (common == null ||
        state == null ||
        method is! String ||
        uri is! String) {
      return null;
    }
    return HttpDiagnosticEvent(
      id: common.id,
      sessionId: common.sessionId,
      sequence: common.sequence,
      timestampUtc: common.timestampUtc,
      updatedAtUtc: common.updatedAtUtc,
      severity: common.severity,
      source: common.source,
      operation: common.operation,
      correlationId: common.correlationId,
      handled: common.handled,
      degraded: common.degraded,
      method: method,
      uri: uri,
      state: state,
      statusCode: json['statusCode'] as int?,
      reasonPhrase: json['reasonPhrase'] as String?,
      redirects: _redirects(json['redirects']),
      responseHeaders: _headers(json['responseHeaders']),
      headerDuration: _duration(json['headerDurationMicros']),
      totalDuration: _duration(json['totalDurationMicros']),
      sentBytes: json['sentBytes'] as int? ?? 0,
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      errorType: json['errorType'] as String?,
      errorMessage: json['errorMessage'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }
}

final class ErrorDiagnosticEvent extends DiagnosticEvent {
  ErrorDiagnosticEvent({
    required super.id,
    required super.sessionId,
    required super.sequence,
    required super.timestampUtc,
    required super.updatedAtUtc,
    super.severity = DiagnosticSeverity.error,
    required super.source,
    super.operation,
    super.correlationId,
    required super.handled,
    required super.degraded,
    required String errorType,
    required String message,
    required String stackTrace,
  }) : errorType = DiagnosticsRedactor.scrub(errorType),
       message = DiagnosticsRedactor.scrub(message),
       stackTrace = DiagnosticsRedactor.scrub(stackTrace);

  final String errorType;
  final String message;
  final String stackTrace;

  @override
  DiagnosticEventKind get kind => DiagnosticEventKind.error;

  @override
  bool get isError => true;

  @override
  String get searchText => [
    source,
    operation,
    correlationId,
    errorType,
    message,
  ].whereType<String>().join(' ').toLowerCase();

  @override
  Map<String, Object?> toJson() => {
    ...commonJson(),
    'errorType': errorType,
    'message': message,
    'stackTrace': stackTrace,
  };

  static ErrorDiagnosticEvent? fromJson(Map<Object?, Object?> json) {
    final common = _CommonFields.fromJson(json);
    final errorType = json['errorType'];
    final message = json['message'];
    final stackTrace = json['stackTrace'];
    if (common == null ||
        errorType is! String ||
        message is! String ||
        stackTrace is! String) {
      return null;
    }
    return ErrorDiagnosticEvent(
      id: common.id,
      sessionId: common.sessionId,
      sequence: common.sequence,
      timestampUtc: common.timestampUtc,
      updatedAtUtc: common.updatedAtUtc,
      severity: common.severity,
      source: common.source,
      operation: common.operation,
      correlationId: common.correlationId,
      handled: common.handled,
      degraded: common.degraded,
      errorType: errorType,
      message: message,
      stackTrace: stackTrace,
    );
  }
}

final class _CommonFields {
  const _CommonFields({
    required this.id,
    required this.sessionId,
    required this.sequence,
    required this.timestampUtc,
    required this.updatedAtUtc,
    required this.severity,
    required this.source,
    required this.operation,
    required this.correlationId,
    required this.handled,
    required this.degraded,
  });

  final String id;
  final String sessionId;
  final int sequence;
  final DateTime timestampUtc;
  final DateTime updatedAtUtc;
  final DiagnosticSeverity severity;
  final String source;
  final String? operation;
  final String? correlationId;
  final bool handled;
  final bool degraded;

  static _CommonFields? fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    final sessionId = json['sessionId'];
    final sequence = json['sequence'];
    final timestampUtc = DateTime.tryParse(
      json['timestampUtc'] as String? ?? '',
    );
    final updatedAtUtc = DateTime.tryParse(
      json['updatedAtUtc'] as String? ?? '',
    );
    final severity = _enumByName(DiagnosticSeverity.values, json['severity']);
    final source = json['source'];
    final handled = json['handled'];
    final degraded = json['degraded'];
    if (id is! String ||
        sessionId is! String ||
        sequence is! int ||
        timestampUtc == null ||
        updatedAtUtc == null ||
        severity == null ||
        source is! String ||
        handled is! bool ||
        degraded is! bool) {
      return null;
    }
    return _CommonFields(
      id: id,
      sessionId: sessionId,
      sequence: sequence,
      timestampUtc: timestampUtc,
      updatedAtUtc: updatedAtUtc,
      severity: severity,
      source: source,
      operation: json['operation'] as String?,
      correlationId: json['correlationId'] as String?,
      handled: handled,
      degraded: degraded,
    );
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Duration? _duration(Object? micros) =>
    micros is int ? Duration(microseconds: micros) : null;

List<DiagnosticRedirect> _redirects(Object? value) {
  if (value is! List) return const [];
  return value
      .map(DiagnosticRedirect.fromJson)
      .whereType<DiagnosticRedirect>()
      .toList();
}

Map<String, List<String>> _headers(Object? value) {
  if (value is! Map) return const {};
  final headers = <String, List<String>>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! List) continue;
    final values = (entry.value as List).whereType<String>().toList();
    headers[entry.key as String] = values;
  }
  return headers;
}
