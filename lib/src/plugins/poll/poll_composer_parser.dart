import 'package:flutter/foundation.dart';

import '../../plugin_api/composer_syntax.dart';
import '../../shell/markdown_editing_controller.dart';

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

  int pollCaretAfter(PollComposerBlock block) {
    final occurrence = _pollOccurrence(block);
    if (occurrence != null) return syntaxCaretAfter(occurrence);
    var offset = block.end;
    if (offset >= text.length) return offset;
    if (text.codeUnitAt(offset) == 0x0D &&
        offset + 1 < text.length &&
        text.codeUnitAt(offset + 1) == 0x0A) {
      return offset + 2;
    }
    return text.codeUnitAt(offset) == 0x0A ? offset + 1 : offset;
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

  int get length => end - start;

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

  bool containsOffset(int offset, {bool includeEnd = false}) =>
      offset >= start && (includeEnd ? offset <= end : offset < end);
}

/// Projects only unambiguous, lossless poll blocks; complex or malformed forms
/// remain raw source.
List<PollComposerBlock> parsePollComposerBlocks(String source) {
  if (source.isEmpty) return const [];

  final lines = _linesOf(source);
  final inFence = _fenceMap(lines);
  final blocks = <PollComposerBlock>[];

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final opening = inFence[index] ? null : _parseOpening(line.text);
    if (opening == null) {
      index++;
      continue;
    }

    var depth = 1;
    var nested = false;
    _Closing? closing;
    var cursor = index + 1;
    for (; cursor < lines.length; cursor++) {
      if (inFence[cursor]) continue;
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
  final inFence = _fenceMap(lines);
  final names = <String>{};
  for (var index = 0; index < lines.length; index++) {
    if (inFence[index]) continue;
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
    required this.end,
    required this.text,
  });

  final int start;
  final int contentEnd;
  final int end;
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
        end: end,
        text: source.substring(start, contentEnd),
      ),
    );
    start = end;
  }
  return lines;
}

List<bool> _fenceMap(List<_SourceLine> lines) {
  final result = List<bool>.filled(lines.length, false);
  String? marker;
  var minimumLength = 0;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].text;
    if (marker != null) {
      result[index] = true;
      final close = RegExp(
        '^ {0,3}${RegExp.escape(marker)}{$minimumLength,}[ \\t]*\$',
      ).hasMatch(line);
      if (close) marker = null;
      continue;
    }

    final open = _fenceOpeningPattern.firstMatch(line);
    if (open == null) continue;
    final run = open.group(1)!;
    marker = run[0];
    minimumLength = run.length;
    result[index] = true;
  }
  return result;
}
