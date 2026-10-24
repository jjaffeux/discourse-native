import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import '../../shell/composer/components/list_source.dart';

const pollComposerSyntaxId = 'poll/poll';

abstract interface class PollComposerProjectionData {
  PollComposerBlock get pollBlock;
}

/// [raw] retains separating whitespace so edits preserve unknown future
/// attributes and their order.
@immutable
class PollMarkupAttribute {
  const PollMarkupAttribute({
    required this.name,
    required this.value,
    required this.raw,
    required this.leadingWhitespace,
    required this.whitespaceBeforeEquals,
    required this.whitespaceAfterEquals,
    required this.quote,
  });

  final String name;
  final String value;
  final String raw;
  final String leadingWhitespace;
  final String whitespaceBeforeEquals;
  final String whitespaceAfterEquals;
  final String? quote;

  String get normalizedName => name.toLowerCase();

  String withValue(String next) {
    if (next == value) return raw;

    var chosenQuote = quote;
    if (chosenQuote == null && _needsQuote(next)) chosenQuote = '"';
    if (chosenQuote == '"' && next.contains('"')) {
      chosenQuote = next.contains("'") ? null : "'";
    } else if (chosenQuote == "'" && next.contains("'")) {
      chosenQuote = next.contains('"') ? null : '"';
    }

    // BBCode has no safe escaping when a future value contains both quotes.
    if (chosenQuote == null && _needsQuote(next)) {
      throw ArgumentError.value(next, 'next', 'cannot be represented safely');
    }

    final rendered = chosenQuote == null
        ? next
        : '$chosenQuote$next$chosenQuote';
    return '$leadingWhitespace$name$whitespaceBeforeEquals='
        '$whitespaceAfterEquals$rendered';
  }

  static bool _needsQuote(String value) =>
      value.isEmpty || value.contains(RegExp(r'''[\s\]]'''));
}

extension PollComposerEditing on MarkdownEditingController {
  List<PollComposerBlock> get pollBlocks => [
    for (final occurrence in syntaxBlocks) ?_pollBlock(occurrence),
  ];

  ComposerSyntaxOccurrence? _pollOccurrence(PollComposerBlock block) {
    for (final occurrence in syntaxBlocks) {
      final projected = _pollBlock(occurrence);
      if (projected != null &&
          (identical(projected, block) ||
              occurrence.start == block.start &&
                  occurrence.end == block.end &&
                  occurrence.source == block.source)) {
        return occurrence;
      }
    }
    return null;
  }

  PollComposerBlock? collapsedPollAtOffset(int offset) {
    final occurrence = collapsedSyntaxAtOffset(offset);
    return occurrence == null ? null : _pollBlock(occurrence);
  }

  bool isPollCollapsed(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    return occurrence != null && isSyntaxCollapsed(occurrence);
  }

  void keepPollCollapsedForPointerEdit(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    if (occurrence != null) keepSyntaxCollapsedForPointerEdit(occurrence);
  }

  void releasePollPointerEdit(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    if (occurrence != null) releaseSyntaxPointerEdit(occurrence);
  }

  PollComposerBlock? get keyboardSelectedPoll {
    final occurrence = keyboardSelectedSyntax;
    return occurrence == null ? null : _pollBlock(occurrence);
  }
}

PollComposerBlock? _pollBlock(ComposerSyntaxOccurrence occurrence) {
  if (occurrence.kind.id != pollComposerSyntaxId) return null;
  return switch (occurrence.projection) {
    final PollComposerProjectionData projection => projection.pollBlock,
    _ => null,
  };
}

enum ComposerPollType {
  regular('regular'),
  multiple('multiple'),
  number('number'),
  rankedChoice('ranked_choice'),
  unknown('');

  const ComposerPollType(this.markupValue);

  final String markupValue;

  static ComposerPollType parse(String? value) => switch (value) {
    null || '' || 'regular' => regular,
    'multiple' => multiple,
    'number' => number,
    'ranked_choice' => rankedChoice,
    _ => unknown,
  };
}

@immutable
class PollComposerBlock {
  const PollComposerBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.attributes,
    required this.openingIndent,
    required this.attributeTrailingWhitespace,
    required this.openingTrailingWhitespace,
    required this.closingIndent,
    required this.closingTrailingWhitespace,
    required this.lineEnding,
    required this.titleSource,
    required this.optionSources,
  });

  final int start;
  final int end;

  final String source;
  final List<PollMarkupAttribute> attributes;
  final String openingIndent;

  final String attributeTrailingWhitespace;

  final String openingTrailingWhitespace;
  final String closingIndent;
  final String closingTrailingWhitespace;
  final String lineEnding;
  final String? titleSource;
  final List<String> optionSources;

  String? attribute(String name) {
    final normalized = name.toLowerCase();
    for (final attribute in attributes) {
      if (attribute.normalizedName == normalized) return attribute.value;
    }
    return null;
  }

  String get name => attribute('name') ?? 'poll';

  ComposerPollType get type => ComposerPollType.parse(attribute('type'));

  bool get canProject => type != ComposerPollType.unknown;

  bool containsOffset(int offset) => offset >= start && offset < end;
}

/// Projects only unambiguous, lossless poll blocks; complex or malformed forms
/// remain raw source.
List<PollComposerBlock> parsePollComposerBlocks(String source) {
  if (source.isEmpty) return const [];

  final lines = _linesOf(source);
  final excluded = _excludedLineMap(source, lines);
  final blocks = <PollComposerBlock>[];

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final opening = excluded[index] ? null : _parseOpening(line.text);
    if (opening == null) {
      index++;
      continue;
    }

    var depth = 1;
    var nested = false;
    _Closing? closing;
    var cursor = index + 1;
    for (; cursor < lines.length; cursor++) {
      if (excluded[cursor]) continue;
      final current = lines[cursor];
      if (_parseOpening(current.text) != null) {
        depth++;
        nested = true;
        continue;
      }
      final candidate = _parseClosing(current.text);
      if (candidate != null) {
        depth--;
        if (depth == 0) {
          closing = candidate;
          break;
        }
      }
    }

    // An unmatched outer opener makes every apparent inner poll ambiguous.
    if (cursor == lines.length) break;

    assert(closing != null);
    final matchedClosing = closing!;
    if (!nested) {
      final body = _parseBody(
        lines.sublist(index + 1, cursor),
        ComposerPollType.parse(_attributeValue(opening.attributes, 'type')),
      );
      if (body != null) {
        final end = lines[cursor].contentEnd;
        final raw = source.substring(line.start, end);
        blocks.add(
          PollComposerBlock(
            start: line.start,
            end: end,
            source: raw,
            attributes: List.unmodifiable(opening.attributes),
            openingIndent: opening.indent,
            attributeTrailingWhitespace: opening.attributeTrailingWhitespace,
            openingTrailingWhitespace: opening.trailingWhitespace,
            closingIndent: matchedClosing.indent,
            closingTrailingWhitespace: matchedClosing.trailingWhitespace,
            lineEnding: raw.contains('\r\n') ? '\r\n' : '\n',
            titleSource: body.title,
            optionSources: List.unmodifiable(body.options),
          ),
        );
      }
    }

    index = cursor + 1;
  }

  return List.unmodifiable(blocks);
}

/// Includes valid openers with complex raw bodies so new polls cannot collide.
Set<String> pollNamesInComposerSource(String source) {
  final lines = _linesOf(source);
  final excluded = _excludedLineMap(source, lines);
  final names = <String>{};
  for (var index = 0; index < lines.length; index++) {
    if (excluded[index]) continue;
    final opening = _parseOpening(lines[index].text);
    if (opening == null) continue;
    names.add(_attributeValue(opening.attributes, 'name') ?? 'poll');
  }
  return names;
}

String nextPollName(String source) {
  final names = pollNamesInComposerSource(source);
  if (!names.contains('poll')) return 'poll';
  for (var suffix = 2; ; suffix++) {
    final candidate = 'poll$suffix';
    if (!names.contains(candidate)) return candidate;
  }
}

class _Body {
  const _Body(this.title, this.options);

  final String? title;
  final List<String> options;
}

_Body? _parseBody(List<_SourceLine> lines, ComposerPollType type) {
  String? title;
  final options = <String>[];
  String? optionIndent;
  var sawOption = false;

  for (final line in lines) {
    final text = line.text;
    if (text.trim().isEmpty) continue;

    final heading = _headingPattern.firstMatch(text);
    if (heading != null && title == null && !sawOption) {
      title = heading.group(2)!.trim();
      continue;
    }

    final option = _optionPattern.firstMatch(text);
    if (option == null || type == ComposerPollType.number) return null;
    final indent = option.group(1)!;
    if (optionIndent != null && optionIndent != indent) return null;
    optionIndent = indent;
    options.add((option.group(3) ?? '').trim());
    sawOption = true;
  }

  // Number polls derive options from min/max/step; other types require a list.
  if (type == ComposerPollType.number) return _Body(title, const []);
  if (type == ComposerPollType.unknown || options.isEmpty) return null;
  return _Body(title, options);
}

final RegExp _headingPattern = RegExp(r'^( {0,3})#[ \t]+(.+?)[ \t]*$');
final RegExp _optionPattern = RegExp(r'^( {0,3})([*+-])(?:[ \t]+(.*))?$');
final RegExp _openingPattern = RegExp(
  r'^([ ]{0,3})\[poll((?:.|\t)*)\]([ \t]*)$',
  caseSensitive: false,
);
final RegExp _closingPattern = RegExp(
  r'^([ ]{0,3})\[/poll\]([ \t]*)$',
  caseSensitive: false,
);
final RegExp _leadingHorizontalSpacePattern = RegExp(r'^[ \t]');
final RegExp _fenceOpeningPattern = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final RegExp _commentOpeningPattern = RegExp(r'^ {0,3}<!--');

enum _BbcodeBlock { code, quote, excerpt, grid, wrap, poll }

final String _bbcodeBlockNames = _BbcodeBlock.values
    .map((block) => block.name)
    .join('|');

final RegExp _bbcodeClosingPattern = RegExp(
  '^ {0,3}\\[/($_bbcodeBlockNames)\\]\\s*\$',
  caseSensitive: false,
);
const _bbcodeQuotationPairs = [
  '""',
  "''",
  '«»',
  '“”',
  '””',
  '‘’',
  '„“',
  '‚’',
  '‹›',
];
final String _bbcodeQuotedValuePattern = [
  for (final pair in _bbcodeQuotationPairs)
    '${RegExp.escape(pair[0])}[^${RegExp.escape(pair[1])}]+${RegExp.escape(pair[1])}',
].join('|');
final RegExp _bbcodeOpeningPattern = RegExp(
  '^ {0,3}\\[(?=($_bbcodeBlockNames)(?:[=\\s\\]]))'
  '(?:(?:[-\\w]+(?:=(?:$_bbcodeQuotedValuePattern|[^\\s\\]]+))?)+\\s*)+',
  caseSensitive: false,
);
final RegExp _legacyQuoteOpeningPattern = RegExp(
  '^ {0,3}\\[(quote)=(\\s*[^${RegExp.escape(_bbcodeQuotationPairs.join())}].+?)\\]',
  caseSensitive: false,
);

_BbcodeBlock? _bbcodeBlockOpening(String line) {
  final legacyQuote = _legacyQuoteOpeningPattern.firstMatch(line);
  if (legacyQuote != null) {
    return legacyQuote.group(1) == 'quote' &&
            line.substring(legacyQuote.end).trim().isEmpty
        ? _BbcodeBlock.quote
        : null;
  }
  final opening = _bbcodeOpeningPattern.firstMatch(line);
  if (opening == null ||
      opening.end == line.length ||
      line[opening.end] != ']' ||
      line.substring(opening.end + 1).trim().isNotEmpty) {
    return null;
  }
  return _BbcodeBlock.values.byName(opening.group(1)!.toLowerCase());
}

class _Opening {
  const _Opening({
    required this.indent,
    required this.attributes,
    required this.attributeTrailingWhitespace,
    required this.trailingWhitespace,
  });

  final String indent;
  final List<PollMarkupAttribute> attributes;
  final String attributeTrailingWhitespace;
  final String trailingWhitespace;
}

class _Closing {
  const _Closing(this.indent, this.trailingWhitespace);

  final String indent;
  final String trailingWhitespace;
}

_Opening? _parseOpening(String line) {
  final match = _openingPattern.firstMatch(line);
  if (match == null) return null;

  final inside = match.group(2)!;
  if (inside.isNotEmpty && !_leadingHorizontalSpacePattern.hasMatch(inside)) {
    return null;
  }
  final parsed = _parseAttributes(inside);
  if (parsed == null) return null;
  return _Opening(
    indent: match.group(1)!,
    attributes: parsed.attributes,
    attributeTrailingWhitespace: parsed.trailingWhitespace,
    trailingWhitespace: match.group(3)!,
  );
}

_Closing? _parseClosing(String line) {
  final match = _closingPattern.firstMatch(line);
  return match == null ? null : _Closing(match.group(1)!, match.group(2)!);
}

class _ParsedAttributes {
  const _ParsedAttributes(this.attributes, this.trailingWhitespace);

  final List<PollMarkupAttribute> attributes;
  final String trailingWhitespace;
}

_ParsedAttributes? _parseAttributes(String source) {
  final attributes = <PollMarkupAttribute>[];
  final seen = <String>{};
  var offset = 0;
  var trailingWhitespace = '';

  while (offset < source.length) {
    final start = offset;
    while (offset < source.length && _isHorizontalSpace(source[offset])) {
      offset++;
    }
    final leading = source.substring(start, offset);
    if (offset == source.length) {
      trailingWhitespace = leading;
      break;
    }
    if (leading.isEmpty) return null;

    final nameStart = offset;
    if (!_isAttributeNameStart(source[offset])) return null;
    offset++;
    while (offset < source.length && _isAttributeNamePart(source[offset])) {
      offset++;
    }
    final name = source.substring(nameStart, offset);

    final beforeEqualsStart = offset;
    while (offset < source.length && _isHorizontalSpace(source[offset])) {
      offset++;
    }
    final beforeEquals = source.substring(beforeEqualsStart, offset);
    if (offset == source.length || source[offset] != '=') return null;
    offset++;

    final afterEqualsStart = offset;
    while (offset < source.length && _isHorizontalSpace(source[offset])) {
      offset++;
    }
    final afterEquals = source.substring(afterEqualsStart, offset);
    if (offset == source.length) return null;

    String? quote;
    String value;
    final first = source[offset];
    if (first == '"' || first == "'") {
      quote = first;
      offset++;
      final valueStart = offset;
      while (offset < source.length && source[offset] != quote) {
        offset++;
      }
      if (offset == source.length) return null;
      value = source.substring(valueStart, offset);
      offset++;
      if (offset < source.length && !_isHorizontalSpace(source[offset])) {
        return null;
      }
    } else {
      final valueStart = offset;
      while (offset < source.length && !_isHorizontalSpace(source[offset])) {
        offset++;
      }
      value = source.substring(valueStart, offset);
      if (value.isEmpty || value.contains(']')) return null;
    }

    final normalized = name.toLowerCase();
    if (!seen.add(normalized)) return null;
    attributes.add(
      PollMarkupAttribute(
        name: name,
        value: value,
        raw: source.substring(start, offset),
        leadingWhitespace: leading,
        whitespaceBeforeEquals: beforeEquals,
        whitespaceAfterEquals: afterEquals,
        quote: quote,
      ),
    );
  }

  return _ParsedAttributes(attributes, trailingWhitespace);
}

String? _attributeValue(List<PollMarkupAttribute> attributes, String name) {
  final normalized = name.toLowerCase();
  for (final attribute in attributes) {
    if (attribute.normalizedName == normalized) return attribute.value;
  }
  return null;
}

bool _isHorizontalSpace(String character) =>
    character == ' ' || character == '\t';

bool _isAttributeNameStart(String character) {
  final unit = character.codeUnitAt(0);
  return unit == 0x5F || _isAsciiLetter(unit);
}

bool _isAttributeNamePart(String character) {
  final unit = character.codeUnitAt(0);
  return unit == 0x2D ||
      unit == 0x5F ||
      _isAsciiLetter(unit) ||
      (unit >= 0x30 && unit <= 0x39);
}

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

class _SourceLine {
  const _SourceLine({
    required this.start,
    required this.contentEnd,
    required this.text,
  });

  final int start;
  final int contentEnd;
  final String text;
}

List<_SourceLine> _linesOf(String source) {
  final lines = <_SourceLine>[];
  var start = 0;
  while (start < source.length) {
    var cursor = start;
    while (cursor < source.length && source.codeUnitAt(cursor) != 0x0A) {
      cursor++;
    }
    var contentEnd = cursor;
    if (contentEnd > start && source.codeUnitAt(contentEnd - 1) == 0x0D) {
      contentEnd--;
    }
    final end = cursor < source.length ? cursor + 1 : cursor;
    lines.add(
      _SourceLine(
        start: start,
        contentEnd: contentEnd,
        text: source.substring(start, contentEnd),
      ),
    );
    start = end;
  }
  return lines;
}

typedef _ListContext = ({int end, int indent, int? contentStart});

String? _relativeBbcodeLine(String text, int indent) {
  var column = 0;
  var offset = 0;
  while (offset < text.length) {
    final unit = text.codeUnitAt(offset);
    if (unit == 0x20) {
      column++;
    } else if (unit == 0x09) {
      column += 4 - column % 4;
    } else {
      break;
    }
    offset++;
  }
  return column < indent
      ? null
      : '${' ' * (column - indent)}${text.substring(offset)}';
}

({Map<int, int> code, Map<int, int> blocks}) _bbcodePairs(
  List<_SourceLine> lines, {
  List<_ListContext>? contexts,
  bool raw = false,
}) {
  final closers = <({int indent, _BbcodeBlock tag}), List<int>>{};
  final code = <int, int>{};
  final blocks = <int, int>{};
  for (var index = lines.length - 1; index >= 0; index--) {
    final text = lines[index].text;
    final normalized = raw ? text.trimLeft() : _relativeBbcodeLine(text, 0)!;
    var column = 0;
    while (column < normalized.length && normalized[column] == ' ') {
      column++;
    }
    final marker = normalized.substring(column);
    final opening = _bbcodeBlockOpening(marker);
    final closing = _bbcodeClosingPattern.firstMatch(marker);
    if (opening != null || closing != null) {
      final tag =
          opening ??
          _BbcodeBlock.values.byName(closing!.group(1)!.toLowerCase());
      final firstIndent = raw || column < 3 ? 0 : column - 3;
      final lastIndent = raw ? 0 : column;
      for (var indent = firstIndent; indent <= lastIndent; indent++) {
        final closed = closers.putIfAbsent((
          indent: indent,
          tag: tag,
        ), () => []);
        if (closing != null) {
          closed.add(index);
          continue;
        }
        if (closed.isEmpty) continue;
        final end = closed.removeLast();
        if (raw || (contexts?[index].indent ?? 0) == indent) {
          final ends = tag == _BbcodeBlock.code ? code : blocks;
          ends[index] = end;
        }
      }
    }
    final contentStart = contexts?[index].contentStart;
    if (contentStart == null) continue;
    final body = text.substring(contentStart);
    final firstLine = raw ? body.trimLeft() : _relativeBbcodeLine(body, 0)!;
    final firstOpening = _bbcodeBlockOpening(firstLine);
    if (firstOpening == null) continue;
    final closed =
        closers[(indent: raw ? 0 : contexts![index].indent, tag: firstOpening)];
    if (closed == null || closed.isEmpty) continue;
    final ends = firstOpening == _BbcodeBlock.code ? code : blocks;
    ends[index] = closed.last;
  }
  return (code: code, blocks: blocks);
}

List<bool> _excludedLineMap(String source, List<_SourceLine> lines) {
  final contexts = List<_ListContext>.filled(lines.length, (
    end: lines.length,
    indent: 0,
    contentStart: null,
  ));
  void collect(
    List<ComposerListItem> items,
    int Function(int) sourceOffset,
    int parentIndent,
    int firstLine,
  ) {
    var cursor = firstLine;
    for (final parsedItem in items) {
      final taskStart = parsedItem.taskMarkerStart;
      final item = taskStart == null
          ? parsedItem
          : ComposerListItem(
              document: parsedItem.document,
              start: parsedItem.start,
              end: parsedItem.end,
              marker: parsedItem.marker,
              indent: parsedItem.indent,
              contentIndent: parsedItem.contentIndent,
              contentStart: taskStart,
              firstLineEnd: parsedItem.firstLineEnd,
              closed: parsedItem.closed,
              referenceMarkers: parsedItem.referenceMarkers,
              number: parsedItem.number,
            );
      final sourceStart = sourceOffset(item.start);
      final sourceEnd = sourceOffset(item.end);
      while (cursor < lines.length && lines[cursor].contentEnd < sourceStart) {
        cursor++;
      }
      final start = cursor;
      while (cursor < lines.length && lines[cursor].start <= sourceEnd) {
        cursor++;
      }
      final indent = parentIndent + item.contentIndent;
      contexts.fillRange(start, cursor, (
        end: cursor,
        indent: indent,
        contentStart: null,
      ));
      if (start < cursor) {
        contexts[start] = (
          end: cursor,
          indent: indent,
          contentStart: sourceOffset(item.contentStart) - lines[start].start,
        );
      }
      collect(
        item.children,
        (offset) => sourceOffset(item.body.sourceOffset(offset)),
        indent,
        start,
      );
    }
  }

  collect(
    composerListItems(source.replaceAll('<!--', '....')),
    (offset) => offset,
    0,
    0,
  );
  var listSource = source;
  if (source.contains('<!--')) {
    final absolute = _bbcodePairs(lines).code;
    final raw = _bbcodePairs(lines, contexts: contexts, raw: true).code;
    final masked = StringBuffer();
    var codeLimit = -1;
    for (var index = 0; index < lines.length; index++) {
      for (final end in [absolute[index], raw[index]]) {
        if (end != null && end > codeLimit) codeLimit = end;
      }
      final end = index + 1 < lines.length
          ? lines[index + 1].start
          : source.length;
      final text = source.substring(lines[index].start, end);
      masked.write(index < codeLimit ? text.replaceAll('<!--', '....') : text);
    }
    listSource = masked.toString();
  }

  if (source.contains('<!--')) {
    contexts.fillRange(0, lines.length, (
      end: lines.length,
      indent: 0,
      contentStart: null,
    ));
    collect(composerListItems(listSource), (offset) => offset, 0, 0);
  }
  final pairs = _bbcodePairs(lines, contexts: contexts);
  final codeEnds = pairs.code;
  final blockEnds = pairs.blocks;

  final result = List<bool>.filled(lines.length, false);
  final activeBlockEnds = <int>[];
  for (var index = 0; index < lines.length; index++) {
    while (activeBlockEnds.isNotEmpty && index >= activeBlockEnds.last) {
      activeBlockEnds.removeLast();
    }
    final blockLimit = activeBlockEnds.isEmpty
        ? lines.length
        : activeBlockEnds.last;
    final limit = contexts[index].end < blockLimit
        ? contexts[index].end
        : blockLimit;
    final line = lines[index].text;
    final codeEnd = codeEnds[index];
    if (codeEnd != null && codeEnd < limit) {
      result.fillRange(index, codeEnd + 1, true);
      index = codeEnd;
      continue;
    }

    final contentStart = contexts[index].contentStart;
    final relative = contentStart == null
        ? _relativeBbcodeLine(line, contexts[index].indent)
        : _relativeBbcodeLine(line.substring(contentStart), 0);
    final listComment =
        relative != null && _commentOpeningPattern.hasMatch(relative);
    if (_commentOpeningPattern.hasMatch(line) || listComment) {
      final commentLimit = listComment ? limit : blockLimit;
      var end = index;
      while (end < commentLimit && !lines[end].text.contains('-->')) {
        end++;
      }
      if (end == commentLimit) {
        result.fillRange(index, lines.length, true);
        break;
      }
      result.fillRange(index, end + 1, true);
      index = end;
      continue;
    }

    final blockEnd = blockEnds[index];
    if (blockEnd != null && blockEnd < limit) {
      activeBlockEnds.add(blockEnd);
      continue;
    }

    final open = _fenceOpeningPattern.firstMatch(line);
    if (open == null) continue;
    final run = open.group(1)!;
    final close = RegExp(
      '^ {0,3}${RegExp.escape(run[0])}{${run.length},}[ \\t]*\$',
    );
    var end = index + 1;
    while (end < limit && !close.hasMatch(lines[end].text)) {
      end++;
    }
    if (end == limit) end--;
    result.fillRange(index, end + 1, true);
    index = end;
  }
  return result;
}
