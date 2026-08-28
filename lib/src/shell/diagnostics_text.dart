/// Presentation of captured diagnostics, shared by the core panel and
/// plugin-owned diagnostics views.
///
/// What a field looks like on screen has to agree across those views, or the
/// same event read twice reads as two events.
library;

import 'dart:convert';

/// Structured payloads as indented JSON, everything else as itself.
String diagnosticValueText(Object? value) => value is Map || value is Iterable
    ? const JsonEncoder.withIndent('  ').convert(value)
    : '$value';

/// The UTC wall clock to the millisecond.
///
/// Diagnostics are read against one another and against a server log, so the
/// date is noise and the zone must not be the reader's.
String diagnosticTimeText(DateTime timestamp) {
  final utc = timestamp.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  return '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}'
      '.${three(utc.millisecond)}';
}

final RegExp _camelBoundary = RegExp(r'([a-z0-9])([A-Z])');

/// Turns a payload key such as `retryAfter` or `status_code` into words.
String splitIdentifier(String value) => value
    .replaceAll('_', ' ')
    .replaceAllMapped(_camelBoundary, (match) => '${match[1]} ${match[2]}');

String sentenceCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
