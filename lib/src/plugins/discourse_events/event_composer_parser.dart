import 'package:flutter/foundation.dart';

@immutable
final class EventAttribute {
  const EventAttribute({
    required this.name,
    required this.value,
    required this.start,
    required this.end,
    required this.valueStart,
    required this.valueEnd,
  });
  final String name;
  final String value;
  final int start;
  final int end;
  final int valueStart;
  final int valueEnd;
  String get normalizedName => eventAttributeName(name);
}

String eventAttributeName(String name) => name
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
    .replaceAll(RegExp(r'[_.]'), '-')
    .toLowerCase();

@immutable
final class EventBlock {
  EventBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.openEnd,
    required this.closeStart,
    required List<EventAttribute> attributes,
  }) : attributes = List.unmodifiable(attributes);
  final int start;
  final int end;
  final String source;

  /// Offsets within [source].
  final int openEnd;
  final int closeStart;
  final List<EventAttribute> attributes;
  String get description => source.substring(openEnd, closeStart);
  String? attribute(String name) => attributes
      .where((a) => a.normalizedName == eventAttributeName(name))
      .firstOrNull
      ?.value;

  /// Replaces only changed values. Unknown attributes, spelling, whitespace,
  /// order, description, and the original recurrence anchor remain verbatim.
  String replace(Map<String, String?> changes, {String? description}) {
    final edits = <({int start, int end, String text})>[];
    final remaining = {
      for (final entry in changes.entries)
        eventAttributeName(entry.key): entry.value,
    };
    for (final attr in attributes) {
      if (!remaining.containsKey(attr.normalizedName)) continue;
      final value = remaining.remove(attr.normalizedName);
      if (value == attr.value) continue;
      edits.add(
        value == null || value.isEmpty
            ? (start: attr.start, end: attr.end, text: '')
            : (
                start: attr.valueStart,
                end: attr.valueEnd,
                text: eventAttributeSource(value),
              ),
      );
    }
    final additions = [
      for (final entry in remaining.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          ' ${entry.key}=${eventAttributeSource(entry.value!)}',
    ].join();
    if (additions.isNotEmpty) {
      edits.add((start: openEnd - 1, end: openEnd - 1, text: additions));
    }
    if (description != null && description != this.description) {
      edits.add((start: openEnd, end: closeStart, text: description));
    }
    edits.sort((a, b) => b.start.compareTo(a.start));
    var result = source;
    for (final edit in edits) {
      result = result.replaceRange(edit.start, edit.end, edit.text);
    }
    return result;
  }
}

String eventAttributeSource(String value) {
  if (value.contains('\n') ||
      value.contains('\r') ||
      (value.contains('"') && value.contains("'"))) {
    throw const FormatException(
      'Attribute values cannot contain line breaks or both kinds of quotation mark.',
    );
  }
  final quote = value.contains('"') ? "'" : '"';
  return '$quote$value$quote';
}

/// Conservative authoring recognition: malformed blocks remain editable raw
/// text. Examples in code, quotes, and indented blocks never become controls.
bool hasEventMarkup(String source) {
  final excluded = _excluded(source);
  return RegExp(
        r'^ {0,3}\[event(?=[\s\]])',
        multiLine: true,
        caseSensitive: false,
      )
      .allMatches(source)
      .any(
        (match) => !excluded.any(
          (range) => range.$1 <= match.start && match.start < range.$2,
        ),
      );
}

List<EventBlock> parseEventBlocks(String source) {
  final excluded = _excluded(source);
  bool ignored(int offset) =>
      excluded.any((r) => r.$1 <= offset && offset < r.$2);
  final blocks = <EventBlock>[];
  final starts = RegExp(
    r'^ {0,3}\[event(?=[\s\]])',
    multiLine: true,
    caseSensitive: false,
  );
  for (final match in starts.allMatches(source)) {
    final start = source.indexOf('[', match.start);
    if (ignored(start) || blocks.any((b) => start < b.end)) continue;
    final openEnd = _tagEnd(source, start + 6);
    if (openEnd == null) continue;
    final closing = RegExp(
      r'\[/event\]',
      caseSensitive: false,
    ).firstMatch(source.substring(openEnd));
    if (closing == null) continue;
    final closeStart = openEnd + closing.start;
    if (source
        .substring(openEnd, closeStart)
        .toLowerCase()
        .contains('[event')) {
      continue;
    }
    final end = openEnd + closing.end;
    final raw = source.substring(start, end);
    final attributes = _attributes(raw, openEnd - start);
    if (attributes == null ||
        !attributes.any(
          (a) => a.normalizedName == 'start' && a.value.isNotEmpty,
        )) {
      continue;
    }
    blocks.add(
      EventBlock(
        start: start,
        end: end,
        source: raw,
        openEnd: openEnd - start,
        closeStart: closeStart - start,
        attributes: attributes,
      ),
    );
  }
  return List.unmodifiable(blocks);
}

int? _tagEnd(String source, int offset) {
  String? quote;
  for (var i = offset; i < source.length; i++) {
    final c = source[i];
    if (c == '\n' || c == '\r') return null;
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == ']') {
      return i + 1;
    }
  }
  return null;
}

List<EventAttribute>? _attributes(String source, int openEnd) {
  final attrs = <EventAttribute>[];
  final names = <String>{};
  var offset = 6;
  while (offset < openEnd - 1) {
    final start = offset;
    while (offset < openEnd - 1 && source[offset].trim().isEmpty) {
      offset++;
    }
    if (offset == openEnd - 1) break;
    final nameMatch = RegExp(
      r'[A-Za-z][A-Za-z0-9_.-]*',
    ).matchAsPrefix(source, offset);
    if (nameMatch == null) return null;
    final name = nameMatch[0]!;
    offset = nameMatch.end;
    while (offset < openEnd - 1 && source[offset].trim().isEmpty) {
      offset++;
    }
    if (offset >= openEnd - 1 || source[offset++] != '=') return null;
    while (offset < openEnd - 1 && source[offset].trim().isEmpty) {
      offset++;
    }
    if (offset >= openEnd - 1) return null;
    final valueStart = offset;
    final quote = source[offset] == '"' || source[offset] == "'"
        ? source[offset++]
        : null;
    final contentStart = offset;
    if (quote != null) {
      while (offset < openEnd - 1 && source[offset] != quote) {
        offset++;
      }
      if (offset >= openEnd - 1) return null;
    } else {
      while (offset < openEnd - 1 && source[offset].trim().isNotEmpty) {
        offset++;
      }
    }
    final value = source.substring(contentStart, offset);
    if (quote != null) offset++;
    final attribute = EventAttribute(
      name: name,
      value: value,
      start: start,
      end: offset,
      valueStart: valueStart,
      valueEnd: offset,
    );
    if (!names.add(attribute.normalizedName)) return null;
    attrs.add(attribute);
  }
  return attrs;
}

List<(int, int)> _excluded(String source) {
  final ranges = <(int, int)>[];
  String? fence;
  var fenceStart = 0;
  var fenceLength = 0;
  final lines = RegExp(r'^.*(?:\n|$)', multiLine: true);
  for (final line in lines.allMatches(source)) {
    final text = line[0]!;
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(text)?[1];
    if (fence != null) {
      if (marker != null &&
          marker[0] == fence &&
          marker.length >= fenceLength &&
          text.substring(text.indexOf(marker) + marker.length).trim().isEmpty) {
        ranges.add((fenceStart, line.end));
        fence = null;
      }
    } else if (marker != null) {
      fence = marker[0];
      fenceStart = line.start;
      fenceLength = marker.length;
    } else if (text.startsWith('    ') ||
        text.startsWith('\t') ||
        text.trimLeft().startsWith('>')) {
      ranges.add((line.start, line.end));
    }
  }
  if (fence != null) ranges.add((fenceStart, source.length));
  final stack = <int>[];
  for (final tag in RegExp(
    r'\[(/?)(?:quote|code)(?:[=\s][^\]]*)?\]',
    caseSensitive: false,
  ).allMatches(source)) {
    if (tag[1]!.isEmpty) {
      stack.add(tag.start);
    } else if (stack.isNotEmpty) {
      final start = stack.removeLast();
      if (stack.isEmpty) ranges.add((start, tag.end));
    }
  }
  if (stack.isNotEmpty) ranges.add((stack.first, source.length));
  for (final pattern in [
    r'\[quote(?:[=\s][^\]]*)?\][\s\S]*?\[/quote\]',
    r'\[code(?:=[^\]]*)?\][\s\S]*?\[/code\]',
    r'<(?:pre|code)\b[^>]*>[\s\S]*?</(?:pre|code)>',
    r'<!--[\s\S]*?-->',
    r'(`+)[\s\S]*?\1',
  ]) {
    for (final match in RegExp(
      pattern,
      caseSensitive: false,
    ).allMatches(source)) {
      ranges.add((match.start, match.end));
    }
  }
  return ranges;
}
