library;

import 'dart:convert';

String diagnosticValueText(Object? value) => value is Map || value is Iterable
    ? const JsonEncoder.withIndent('  ').convert(value)
    : '$value';

String diagnosticTimeText(DateTime timestamp) {
  final utc = timestamp.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  return '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}'
      '.${three(utc.millisecond)}';
}

final RegExp _camelBoundary = RegExp(r'([a-z0-9])([A-Z])');

String splitIdentifier(String value) => value
    .replaceAll('_', ' ')
    .replaceAllMapped(_camelBoundary, (match) => '${match[1]} ${match[2]}');

String sentenceCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
