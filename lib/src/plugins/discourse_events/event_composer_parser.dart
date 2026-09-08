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
  final excluded = _ExclusionCursor(source);
  return RegExp(
    r'^ {0,3}\[event(?=[\s\]])',
    multiLine: true,
    caseSensitive: false,
  ).allMatches(source).any((match) => !excluded.contains(match.start));
}

List<EventBlock> parseEventBlocks(String source) {
  // Index delimiters once: unfinished openers must not copy/search the entire
  // remaining draft, and rejected outer blocks must not rescan nested bodies.
  final closings = RegExp(
    r'\[/event\]',
    caseSensitive: false,
  ).allMatches(source).map((match) => match.start).toList();
  if (closings.isEmpty) return const [];
  final nested = RegExp(
    r'\[event',
    caseSensitive: false,
  ).allMatches(source).map((match) => match.start).toList();
  final excluded = _ExclusionCursor(source);
  final blocks = <EventBlock>[];
  final starts = RegExp(
    r'^ {0,3}\[event(?=[\s\]])',
    multiLine: true,
    caseSensitive: false,
  );
  for (final match in starts.allMatches(source)) {
    final start = source.indexOf('[', match.start);
    if (excluded.contains(start) ||
        (blocks.isNotEmpty && start < blocks.last.end)) {
      continue;
    }
    final openEnd = _tagEnd(source, start + 6);
    if (openEnd == null) continue;
    final closingIndex = _firstAtOrAfter(closings, openEnd);
    if (closingIndex == closings.length) continue;
    final closeStart = closings[closingIndex];
    final nestedIndex = _firstAtOrAfter(nested, openEnd);
    if (nestedIndex < nested.length && nested[nestedIndex] < closeStart) {
      continue;
    }
    final attributes = _attributes(
      source.substring(start, openEnd),
      openEnd - start,
    );
    if (attributes == null ||
        !attributes.any(
          (a) => a.normalizedName == 'start' && a.value.isNotEmpty,
        )) {
      continue;
    }
    final end = closeStart + '[/event]'.length;
    blocks.add(
      EventBlock(
        start: start,
        end: end,
        source: source.substring(start, end),
        openEnd: openEnd - start,
        closeStart: closeStart - start,
        attributes: attributes,
      ),
    );
  }
  return List.unmodifiable(blocks);
}

int _firstAtOrAfter(List<int> offsets, int offset) {
  var low = 0;
  var high = offsets.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (offsets[middle] < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
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

/// Both callers visit offsets in source order. Walk the sorted ranges once,
/// including overlaps, instead of checking every range for every event opener.
final class _ExclusionCursor {
  _ExclusionCursor(String source) : _ranges = _excluded(source).iterator;

  final Iterator<(int, int)> _ranges;
  (int, int)? _current;

  bool contains(int offset) {
    while (_current == null || _current!.$2 <= offset) {
      if (!_ranges.moveNext()) return false;
      _current = _ranges.current;
    }
    return _current!.$1 <= offset;
  }
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
  for (final (tag, end) in _terminatedTags(
    source,
    RegExp(r'\[(/?)(?:quote|code)(?=[=\s\]])', caseSensitive: false),
    ']',
  )) {
    if (tag[1]!.isEmpty) {
      stack.add(tag.start);
    } else if (stack.isNotEmpty) {
      final start = stack.removeLast();
      if (stack.isEmpty) ranges.add((start, end));
    }
  }
  if (stack.isNotEmpty) ranges.add((stack.first, source.length));
  for (final (opening, closing, tagEnd) in [
    (r'\[quote(?=[=\s\]])', r'\[/quote\]', ']'),
    (r'\[code(?=[=\]])', r'\[/code\]', ']'),
    (r'<(?:pre|code)\b', r'</(?:pre|code)>', '>'),
    ('<!--', '-->', null),
  ]) {
    ranges.addAll(
      _delimitedRanges(
        source,
        RegExp(opening, caseSensitive: false),
        RegExp(closing, caseSensitive: false),
        tagEnd: tagEnd,
      ),
    );
  }
  ranges.addAll(_inlineCodeRanges(source));
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  return ranges;
}

/// Match a tag prefix, then consume through the next terminator. If it is
/// missing, later prefixes cannot finish either; do not retry the same suffix.
Iterable<(RegExpMatch, int)> _terminatedTags(
  String source,
  RegExp prefix,
  String terminator,
) sync* {
  var consumed = 0;
  for (final match in prefix.allMatches(source)) {
    if (match.start < consumed) continue;
    final end = source.indexOf(terminator, match.end);
    if (end == -1) break;
    consumed = end + terminator.length;
    yield (match, consumed);
  }
}

/// Preserve the non-nesting, first-closing-delimiter behavior of the exclusion
/// patterns, without backtracking over the body for every unfinished opener.
Iterable<(int, int)> _delimitedRanges(
  String source,
  RegExp opening,
  RegExp closing, {
  String? tagEnd,
}) sync* {
  final starts = tagEnd == null
      ? opening.allMatches(source).map((match) => (match.start, match.end))
      : _terminatedTags(
          source,
          opening,
          tagEnd,
        ).map((tag) => (tag.$1.start, tag.$2));
  final ends = closing.allMatches(source).iterator;
  var hasEnd = ends.moveNext();
  var consumed = 0;
  for (final (start, openEnd) in starts) {
    if (start < consumed) continue;
    while (hasEnd && ends.current.start < openEnd) {
      hasEnd = ends.moveNext();
    }
    if (!hasEnd) break;
    consumed = ends.current.end;
    yield (start, consumed);
  }
}

Iterable<(int, int)> _inlineCodeRanges(String source) sync* {
  final runs = RegExp(r'`+').allMatches(source).toList();
  final longestAfter = List.filled(runs.length + 1, 0);
  for (var i = runs.length - 1; i >= 0; i--) {
    final length = runs[i].end - runs[i].start;
    longestAfter[i] = length > longestAfter[i + 1]
        ? length
        : longestAfter[i + 1];
  }
  var index = 0;
  var offset = 0;
  while (index < runs.length) {
    final run = runs[index];
    if (offset < run.start) offset = run.start;
    final start = offset;
    final length = run.end - start;
    // The old (`+)...\1 pattern chose the longest opener that could close,
    // including within its own run after backtracking. A closer can consume
    // only part of a run; its remainder can open the next span.
    var width = longestAfter[index + 1];
    if (width < length ~/ 2) width = length ~/ 2;
    if (width > length) width = length;
    if (width == 0) break;
    if (width * 2 <= length) {
      offset = start + width * 2;
    } else {
      do {
        index++;
      } while (runs[index].end - runs[index].start < width);
      offset = runs[index].start + width;
    }
    yield (start, offset);
    if (offset == runs[index].end) index++;
  }
}
