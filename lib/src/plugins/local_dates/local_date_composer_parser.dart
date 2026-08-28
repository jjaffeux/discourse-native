import 'package:flutter/foundation.dart';

import '../../plugin_api/composer_syntax.dart';
import '../../shell/markdown_editing_controller.dart';
import '../../shell/markdown_highlight.dart';
import 'local_date_environment.dart';

const localDateComposerSyntaxId = 'discourse-local-dates/local-date';

/// Typed view retained by Local Dates projections while core keeps them
/// opaque.
abstract interface class LocalDateComposerProjectionData {
  LocalDateComposerBlock get localDateBlock;
}

final RegExp _unquotedValuePattern = RegExp(r'[\s\]]');
final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _recurringPattern = RegExp(
  r'^[1-9]\d*\.(years?|quarters?|months?|weeks?|days?|hours?|minutes?|seconds?)$',
);
final RegExp _timePattern = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');

@immutable
class LocalDateMarkupAttribute {
  const LocalDateMarkupAttribute({
    required this.name,
    required this.value,
    required this.raw,
    required this.leadingWhitespace,
    required this.whitespaceBeforeEquals,
    required this.whitespaceAfterEquals,
    required this.openingQuote,
    required this.closingQuote,
    this.implicit = false,
  });

  final String name;
  final String value;
  final String raw;
  final String leadingWhitespace;
  final String whitespaceBeforeEquals;
  final String whitespaceAfterEquals;
  final String? openingQuote;
  final String? closingQuote;
  final bool implicit;

  String get normalizedName => name.toLowerCase();

  String withValue(String next) {
    if (next == value) return raw;
    var open = openingQuote;
    var close = closingQuote;
    if (open == null && _needsQuote(next)) {
      open = '"';
      close = '"';
    }
    if (open != null && next.contains(close!)) {
      if (!next.contains("'")) {
        open = close = "'";
      } else if (!next.contains('"')) {
        open = close = '"';
      } else {
        throw ArgumentError.value(next, 'next', 'cannot be represented safely');
      }
    }
    final rendered = open == null ? next : '$open$next$close';
    if (implicit) {
      return '$leadingWhitespace$whitespaceBeforeEquals='
          '$whitespaceAfterEquals$rendered';
    }
    return '$leadingWhitespace$name$whitespaceBeforeEquals='
        '$whitespaceAfterEquals$rendered';
  }

  static bool _needsQuote(String value) =>
      value.isEmpty || value.contains(_unquotedValuePattern);
}

/// Typed compatibility helpers for Local Dates-owned tests and widgets.
extension LocalDateComposerEditing on MarkdownEditingController {
  List<LocalDateComposerBlock> get localDateBlocks => [
    for (final occurrence in syntaxBlocks) ?_localDateBlock(occurrence),
  ];

  LocalDateComposerBlock? collapsedLocalDateAtOffset(int offset) {
    final occurrence = collapsedSyntaxAtOffset(offset);
    return occurrence == null ? null : _localDateBlock(occurrence);
  }

  LocalDateComposerBlock? get keyboardSelectedLocalDate {
    final occurrence = keyboardSelectedSyntax;
    return occurrence == null ? null : _localDateBlock(occurrence);
  }
}

LocalDateComposerBlock? _localDateBlock(ComposerSyntaxOccurrence occurrence) {
  if (occurrence.kind.id != localDateComposerSyntaxId) return null;
  return switch (occurrence.projection) {
    final LocalDateComposerProjectionData projection =>
      projection.localDateBlock,
    _ => null,
  };
}

enum LocalDateComposerKind { date, range }

@immutable
class LocalDateComposerBlock {
  const LocalDateComposerBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.kind,
    required this.tagName,
    required this.attributes,
    required this.trailingWhitespace,
    required this.environment,
  });

  final int start;
  final int end;
  final String source;
  final LocalDateComposerKind kind;
  final String tagName;
  final List<LocalDateMarkupAttribute> attributes;
  final String trailingWhitespace;
  final LocalDateEnvironment environment;

  int get length => end - start;

  String? attribute(String name) {
    final normalized = name.toLowerCase();
    for (final attribute in attributes) {
      if (attribute.normalizedName == normalized) return attribute.value;
    }
    return null;
  }

  bool get canProject =>
      _supportedOptions(this, environment) &&
      switch (kind) {
        LocalDateComposerKind.date =>
          attribute('from') == null &&
              attribute('to') == null &&
              _validDate(attribute('date')),
        LocalDateComposerKind.range =>
          attribute('date') == null &&
              attribute('time') == null &&
              attribute('recurring') == null &&
              attribute('countdown') == null &&
              _validDateTime(attribute('from')) &&
              _validDateTime(attribute('to')),
      };

  bool containsOffset(int offset, {bool includeEnd = false}) =>
      offset >= start && (includeEnd ? offset <= end : offset < end);
}

/// Losslessly recognizes inline local-date markup outside inline/fenced code.
/// Ambiguous, malformed, or duplicate-attribute tokens remain ordinary text.
///
/// [knownCodeRanges] lets a caller that has already scanned [source] hand its
/// answer over rather than have the scan repeated here.
List<LocalDateComposerBlock> parseLocalDateComposerBlocks(
  String source, {
  required LocalDateEnvironment environment,
  CodeRanges? knownCodeRanges,
}) {
  if (source.isEmpty) return const [];
  final codeRanges = knownCodeRanges ?? CodeRanges.of(scanMarkdown(source));
  final blocks = <LocalDateComposerBlock>[];
  var offset = 0;
  // The end of a stretch already shown to hold no closer, and the offset it
  // was shown from. Without it, a line of openers that never close re-walks
  // the rest of that line once per opener.
  var barrenFrom = -1;
  var barrenTo = -1;
  while (offset < source.length) {
    final opening = source.indexOf('[', offset);
    if (opening == -1) break;
    if (codeRanges.contains(opening)) {
      offset = opening + 1;
      continue;
    }
    final header = _tagAt(source, opening);
    if (header == null) {
      offset = opening + 1;
      continue;
    }
    if (header.contentStart >= barrenFrom && header.contentStart <= barrenTo) {
      offset = opening + 1;
      continue;
    }
    final (:close, :firstQuoteAt, :scannedTo) = _closingBracket(
      source,
      header.contentStart,
    );
    if (close == null) {
      // Conclusive only as far as the first quote: a scan starting inside one
      // would begin outside it, and could find a `]` this one skipped.
      barrenFrom = header.contentStart;
      barrenTo = firstQuoteAt ?? scannedTo;
      offset = opening + 1;
      continue;
    }
    if (codeRanges.overlaps(opening, close + 1)) {
      offset = opening + 1;
      continue;
    }
    final inside = source.substring(header.contentStart, close);
    final parsed = _parseAttributes(inside, kind: header.kind);
    if (parsed != null) {
      final block = LocalDateComposerBlock(
        start: opening,
        end: close + 1,
        source: source.substring(opening, close + 1),
        kind: header.kind,
        tagName: header.tagName,
        attributes: List.unmodifiable(parsed.attributes),
        trailingWhitespace: parsed.trailingWhitespace,
        environment: environment,
      );
      if (block.canProject) blocks.add(block);
    }
    offset = close + 1;
  }
  return List.unmodifiable(blocks);
}

LocalDateComposerBlock? localDateBlockAtComposerOffset(
  Iterable<LocalDateComposerBlock> blocks,
  int offset,
) {
  for (final block in blocks) {
    if (block.containsOffset(offset)) return block;
  }
  return null;
}

@immutable
class _TagHeader {
  const _TagHeader(this.kind, this.tagName, this.contentStart);

  final LocalDateComposerKind kind;
  final String tagName;
  final int contentStart;
}

_TagHeader? _tagAt(String source, int opening) {
  const names = ['date-range', 'date'];
  for (final name in names) {
    final end = opening + 1 + name.length;
    if (end > source.length ||
        source.substring(opening + 1, end).toLowerCase() != name) {
      continue;
    }
    if (end == source.length) return null;
    final next = source[end];
    final kind = name == 'date'
        ? LocalDateComposerKind.date
        : LocalDateComposerKind.range;
    if (kind == LocalDateComposerKind.date && (next == '=' || _space(next))) {
      return _TagHeader(kind, source.substring(opening + 1, end), end);
    }
    if (kind == LocalDateComposerKind.range && _space(next)) {
      return _TagHeader(kind, source.substring(opening + 1, end), end);
    }
  }
  return null;
}

/// The `]` closing a tag whose attributes start at [start].
///
/// Bounded to the line, because upstream's matchers are `/\[date=.+?\]/` and
/// `/\[date-range .+?\]/` with no `s` flag: a tag broken over a newline is
/// not a tag on the server, so it must not be one here either. Only a quoted
/// attribute value could previously hold one open across a break, and only
/// this client would then have drawn it.
///
/// [firstQuoteAt] is where the scan first opened a quote and [scannedTo] how
/// far it reached. A caller that found no closer has thereby shown every
/// offset up to [firstQuoteAt] barren too, since a scan starting in that
/// stretch reads the same characters in the same state.
({int? close, int? firstQuoteAt, int scannedTo}) _closingBracket(
  String source,
  int start,
) {
  String? closeQuote;
  int? firstQuoteAt;
  var offset = start;
  for (; offset < source.length; offset++) {
    final character = source[offset];
    if (character == '\n') break;
    if (closeQuote != null) {
      if (character == closeQuote) closeQuote = null;
      continue;
    }
    closeQuote = switch (character) {
      '"' => '"',
      "'" => "'",
      '“' => '”',
      '‘' => '’',
      _ => null,
    };
    if (closeQuote != null) {
      firstQuoteAt ??= offset;
      continue;
    }
    if (character == ']') {
      return (close: offset, firstQuoteAt: firstQuoteAt, scannedTo: offset);
    }
  }
  return (close: null, firstQuoteAt: firstQuoteAt, scannedTo: offset);
}

@immutable
class _ParsedAttributes {
  const _ParsedAttributes(this.attributes, this.trailingWhitespace);

  final List<LocalDateMarkupAttribute> attributes;
  final String trailingWhitespace;
}

_ParsedAttributes? _parseAttributes(
  String source, {
  required LocalDateComposerKind kind,
}) {
  final attributes = <LocalDateMarkupAttribute>[];
  final seen = <String>{};
  var offset = 0;
  if (kind == LocalDateComposerKind.date && source.startsWith('=')) {
    final value = _parseValue(source, 1);
    if (value == null) return null;
    attributes.add(
      LocalDateMarkupAttribute(
        name: 'date',
        value: value.value,
        raw: source.substring(0, value.end),
        leadingWhitespace: '',
        whitespaceBeforeEquals: '',
        whitespaceAfterEquals: value.whitespaceAfterEquals,
        openingQuote: value.openingQuote,
        closingQuote: value.closingQuote,
        implicit: true,
      ),
    );
    seen.add('date');
    offset = value.end;
  }

  var trailingWhitespace = '';
  while (offset < source.length) {
    final start = offset;
    while (offset < source.length && _space(source[offset])) {
      offset++;
    }
    final leading = source.substring(start, offset);
    if (offset == source.length) {
      trailingWhitespace = leading;
      break;
    }
    if (leading.isEmpty) return null;
    final nameStart = offset;
    if (!_nameStart(source.codeUnitAt(offset))) return null;
    offset++;
    while (offset < source.length && _namePart(source.codeUnitAt(offset))) {
      offset++;
    }
    final name = source.substring(nameStart, offset);
    final beforeStart = offset;
    while (offset < source.length && _space(source[offset])) {
      offset++;
    }
    final before = source.substring(beforeStart, offset);
    if (offset >= source.length || source[offset] != '=') return null;
    offset++;
    final value = _parseValue(source, offset);
    if (value == null) return null;
    offset = value.end;
    final normalized = name.toLowerCase();
    if (!seen.add(normalized)) return null;
    attributes.add(
      LocalDateMarkupAttribute(
        name: name,
        value: value.value,
        raw: source.substring(start, offset),
        leadingWhitespace: leading,
        whitespaceBeforeEquals: before,
        whitespaceAfterEquals: value.whitespaceAfterEquals,
        openingQuote: value.openingQuote,
        closingQuote: value.closingQuote,
      ),
    );
  }
  return _ParsedAttributes(attributes, trailingWhitespace);
}

@immutable
class _ParsedValue {
  const _ParsedValue({
    required this.value,
    required this.end,
    required this.whitespaceAfterEquals,
    required this.openingQuote,
    required this.closingQuote,
  });

  final String value;
  final int end;
  final String whitespaceAfterEquals;
  final String? openingQuote;
  final String? closingQuote;
}

_ParsedValue? _parseValue(String source, int start) {
  var offset = start;
  while (offset < source.length && _space(source[offset])) {
    offset++;
  }
  final after = source.substring(start, offset);
  if (offset >= source.length) return null;
  final open = source[offset];
  final close = switch (open) {
    '"' => '"',
    "'" => "'",
    '“' => '”',
    '‘' => '’',
    _ => null,
  };
  if (close != null) {
    offset++;
    final valueStart = offset;
    while (offset < source.length && source[offset] != close) {
      offset++;
    }
    if (offset >= source.length) return null;
    final value = source.substring(valueStart, offset);
    offset++;
    if (offset < source.length && !_space(source[offset])) return null;
    return _ParsedValue(
      value: value,
      end: offset,
      whitespaceAfterEquals: after,
      openingQuote: open,
      closingQuote: close,
    );
  }
  final valueStart = offset;
  while (offset < source.length && !_space(source[offset])) {
    offset++;
  }
  final value = source.substring(valueStart, offset);
  if (value.isEmpty || value.contains(']')) return null;
  return _ParsedValue(
    value: value,
    end: offset,
    whitespaceAfterEquals: after,
    openingQuote: null,
    closingQuote: null,
  );
}

bool _validDate(String? value) {
  if (value == null) return false;
  final match = _datePattern.firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= DateTime.utc(year, month + 1, 0).day;
}

bool _supportedOptions(
  LocalDateComposerBlock block,
  LocalDateEnvironment environment,
) {
  final calendar = block.attribute('calendar');
  if (calendar != null && calendar != 'on' && calendar != 'off') return false;
  final recurring = block.attribute('recurring');
  if (recurring != null && !_recurringPattern.hasMatch(recurring)) {
    return false;
  }
  final previewZones = (block.attribute('timezones') ?? '')
      .split('|')
      .where((zone) => zone.isNotEmpty)
      .toList(growable: false);
  final namedZones = [
    block.attribute('timezone'),
    block.attribute('displayedtimezone'),
    ...previewZones,
  ].whereType<String>().toList(growable: false);
  return previewZones.length <= 5 &&
      namedZones.every((zone) => environment.canonicalTimezone(zone) != null);
}

bool _validDateTime(String? value) {
  if (value == null) return false;
  final pieces = value.split('T');
  if (pieces.length > 2 || !_validDate(pieces.first)) return false;
  if (pieces.length == 1) return true;
  final match = _timePattern.firstMatch(pieces[1]);
  if (match == null) return false;
  return int.parse(match.group(1)!) <= 23 &&
      int.parse(match.group(2)!) <= 59 &&
      int.parse(match.group(3) ?? '0') <= 59;
}

bool _space(String character) => character == ' ' || character == '\t';
bool _nameStart(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    codeUnit == 0x5F ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

bool _namePart(int codeUnit) =>
    _nameStart(codeUnit) ||
    codeUnit == 0x2D ||
    (codeUnit >= 0x30 && codeUnit <= 0x39);

/// Every option this client can read out of `[date]` markup, in the order it
/// writes them back.
///
/// Upstream's `local-dates` can grow one at a time, and what this client does
/// with an option it has never heard of is refuse to touch the block — the
/// editor declines to open it, and chat preview declines to draw it — rather
/// than rewrite it without the part it did not understand. Three places asked
/// that question and each carried its own copy of the answer, so a new option
/// taught to one of them was a block silently rewritten by another.
const List<String> localDateAttributesInWriteOrder = [
  'date',
  'time',
  'from',
  'to',
  'timezone',
  'format',
  'recurring',
  'timezones',
  'countdown',
  'displayedTimezone',
  'calendar',
];

/// [localDateAttributesInWriteOrder] as [LocalDateComposerAttribute.normalizedName]
/// spells them, which is what an author's arbitrary casing is matched against.
final Set<String> localDateAttributeNames = {
  for (final name in localDateAttributesInWriteOrder) name.toLowerCase(),
};
