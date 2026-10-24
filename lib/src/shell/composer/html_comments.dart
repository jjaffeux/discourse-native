/// HTML comments remain literal source in the editor, but cannot introduce
/// interactive Markdown. Scan in source order so fences/backticks inside a
/// comment cannot hide its closing delimiter or change later code boundaries.
class ComposerHtmlComments extends ComposerLiteralContainers {
  ComposerHtmlComments(String source)
    : super._(
        source.contains('<!--')
            ? ComposerLiteralContainers(source)._ranges.where(
                (range) => range.kind == _LiteralContainerKind.htmlComment,
              )
            : const [],
      );
}

enum _LiteralContainerKind {
  htmlComment,
  bbcodeCode,
  indentedCode,
  nestedFence,
}

typedef _LiteralRange = ({
  int start,
  int end,
  _LiteralContainerKind kind,
  bool block,
});

/// Source-order ownership of comments and code whose bodies are literal.
class ComposerLiteralContainers {
  ComposerLiteralContainers._(Iterable<_LiteralRange> ranges) {
    _ranges.addAll(ranges);
  }

  ComposerLiteralContainers(String source) {
    final indents = <int>[];
    final codeClosers = _codeClose.allMatches(source).toList();
    final codeBlocks = <int, int?>{};
    if (!source.contains('<!--') &&
        codeClosers.isEmpty &&
        !_nestedContext.hasMatch(source)) {
      return;
    }
    String? fence;
    var fenceIndent = 0;
    var fenceStart = 0;
    var nestedFence = false;
    var inlineEnd = 0;
    var commentEnd = 0;
    var start = 0;
    var previousBlank = true;
    var indentedCode = false;
    while (start < source.length) {
      var end = source.indexOf('\n', start);
      if (end < 0) end = source.length;
      final line = source.substring(start, end);
      final indent = _indentWidth(line);
      if (start >= commentEnd && start >= inlineEnd && line.trim().isNotEmpty) {
        if (indent < fenceIndent && fence != null) {
          if (nestedFence) {
            _ranges.add((
              start: fenceStart,
              end: start,
              kind: _LiteralContainerKind.nestedFence,
              block: true,
            ));
          }
          fence = null;
        }
        while (indents.isNotEmpty && indent < indents.last) {
          indents.removeLast();
        }
      }
      var content = _indentCharacters(line, indents.lastOrNull ?? 0);
      final quoteStart = content;
      while (true) {
        final quote = _quote.matchAsPrefix(line, content);
        if (quote == null) break;
        content = quote.end;
      }
      final quoteDepth = '>'
          .allMatches(line.substring(quoteStart, content))
          .length;
      if (start >= commentEnd && start >= inlineEnd && fence == null) {
        final marker = _list.firstMatch(line.substring(content));
        if (marker != null) {
          final markerEnd = content + marker[1]!.length + marker[2]!.length;
          final beforeGap = _indentWidth(
            line.substring(0, markerEnd),
            all: true,
          );
          final afterGap = _indentWidth(
            line.substring(0, content + marker.end),
            all: true,
          );
          content = afterGap - beforeGap > 4
              ? markerEnd + 1
              : content + marker.end;
          indents.add(_indentWidth(line.substring(0, content), all: true));
        }
      }
      final relative = line.substring(content);
      final firstContent =
          start + content + relative.length - relative.trimLeft().length;
      final blank = line.trim().isEmpty;
      final wasBlank = previousBlank;
      previousBlank = blank;
      if (!blank && _indentWidth(relative) < 4) indentedCode = false;
      final delimiter = _fence.firstMatch(relative);
      if (start >= commentEnd && start >= inlineEnd) {
        if (fence != null) {
          if (delimiter != null &&
              delimiter[1]![0] == fence[0] &&
              delimiter[1]!.length >= fence.length &&
              delimiter[2]!.trim().isEmpty) {
            if (nestedFence) {
              _ranges.add((
                start: fenceStart,
                end: end,
                kind: _LiteralContainerKind.nestedFence,
                block: true,
              ));
            }
            fence = null;
          }
          start = end + 1;
          continue;
        }
        if (delimiter != null &&
            !(delimiter[1]!.startsWith('`') && delimiter[2]!.contains('`'))) {
          fence = delimiter[1];
          fenceIndent = indents.lastOrNull ?? 0;
          fenceStart = start;
          nestedFence = content > 0;
          start = end + 1;
          continue;
        }
        if (_indentWidth(relative) >= 4) {
          if (wasBlank || indentedCode || content > 0) {
            indentedCode = true;
            _ranges.add((
              start: start,
              end: end,
              kind: _LiteralContainerKind.indentedCode,
              block: true,
            ));
          }
          start = end + 1;
          continue;
        }
      }
      var at = start + content;
      if (at < commentEnd) at = commentEnd;
      if (at < inlineEnd) at = inlineEnd;
      while (at < end) {
        if (source[at] == '\\') {
          at += 2;
        } else if (source.startsWith('<!--', at)) {
          final close = source.indexOf('-->', at + 4);
          final block = at == firstContent;
          // Inline HTML must close within its paragraph. A list that
          // interrupts the paragraph leaves an unfinished opener literal.
          if (!block &&
              (close < 0 ||
                  _interruptsInline(
                    source,
                    end,
                    close,
                    indents.lastOrNull ?? 0,
                  ))) {
            at += 4;
            continue;
          }
          commentEnd = close < 0 ? source.length : close + 3;
          _ranges.add((
            start: at,
            end: commentEnd,
            kind: _LiteralContainerKind.htmlComment,
            block: block,
          ));
          at = commentEnd;
        } else if (source[at] == '[' && codeClosers.isNotEmpty) {
          final code = _bbcodeCodeAt(
            source,
            at,
            end,
            indents.lastOrNull ?? 0,
            at == firstContent,
            quoteDepth,
            codeBlocks,
            codeClosers,
          );
          if (code == null) {
            at++;
          } else {
            commentEnd = code.end;
            _ranges.add((
              start: at,
              end: code.end,
              kind: _LiteralContainerKind.bbcodeCode,
              block: code.block,
            ));
            at = code.end;
          }
        } else if (source[at] == '`') {
          final opening = _ticks.matchAsPrefix(source, at)!;
          final blank = _blank.firstMatch(source.substring(opening.end));
          final limit = blank == null
              ? source.length
              : opening.end + blank.start;
          final closing = _ticks
              .allMatches(source, opening.end)
              .takeWhile((match) => match.start < limit)
              .where((match) => match[0] == opening[0])
              .firstOrNull;
          inlineEnd =
              closing != null &&
                  !_interruptsInline(
                    source,
                    end,
                    closing.start,
                    indents.lastOrNull ?? 0,
                  )
              ? closing.end
              : opening.end;
          at = inlineEnd;
        } else {
          at++;
        }
      }
      start = end + 1;
    }
    if (fence != null && nestedFence) {
      _ranges.add((
        start: fenceStart,
        end: source.length,
        kind: _LiteralContainerKind.nestedFence,
        block: true,
      ));
    }
  }

  final _ranges = <_LiteralRange>[];
  bool get isEmpty => _ranges.isEmpty;

  _LiteralRange? _rangeAfter(int offset) {
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_ranges[middle].end <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < _ranges.length ? _ranges[low] : null;
  }

  bool contains(int offset) {
    final range = _rangeAfter(offset);
    return range != null && range.start <= offset;
  }

  /// Table rows are split before inline syntax is cooked. Inline containers
  /// cannot claim the following cells or rows of an admitted table.
  bool containsBlock(int offset) {
    final range = _rangeAfter(offset);
    return range != null && range.block && range.start <= offset;
  }

  /// Only for syntax scanning. Original source and its offsets stay untouched.
  String mask(String source) {
    if (isEmpty) return source;
    final result = StringBuffer();
    var start = 0;
    for (final range in _ranges) {
      result.write(source.substring(start, range.start));
      result.write(
        source.substring(range.start, range.end).replaceAll(_nonNewline, ' '),
      );
      start = range.end;
    }
    result.write(source.substring(start));
    return result.toString();
  }
}

final _nestedContext = RegExp(
  r'^(?:[ \t]|>|[-+*][ \t]|\d{1,9}[.)][ \t])',
  multiLine: true,
);
final _quote = RegExp(r' {0,3}>[ \t]?');
final _list = RegExp(r'^( {0,3})([-+*]|\d{1,9}[.)])([ \t]+)');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _ticks = RegExp(r'`+');
final _blank = RegExp(r'\r?\n[ \t]*\r?\n');
final _nonNewline = RegExp(r'[^\r\n]');

int _indentWidth(String text, {bool all = false}) {
  var column = 0;
  for (final unit in text.codeUnits) {
    if (unit == 9) {
      column += 4 - column % 4;
    } else if (unit == 32 || all) {
      column++;
    } else {
      break;
    }
  }
  return column;
}

int _indentCharacters(String text, int width) {
  var column = 0;
  var count = 0;
  while (count < text.length && column < width) {
    final unit = text.codeUnitAt(count);
    if (unit != 32 && unit != 9) break;
    column += unit == 9 ? 4 - column % 4 : 1;
    count++;
  }
  return count;
}

// Markdown block starts interrupt inline comments just as they interrupt the
// paragraph containing them. Only an ordered list starting at 1 interrupts.
final _inlineBreak = RegExp(
  r'^(?:[ \t\r]*$| {0,3}(?:[-+*](?:[ \t]+|$)|1[.)](?:[ \t]+|$)|>|#{1,6}(?:[ \t]+|$)|`{3,}|~{3,}|<!--))',
);

final _tableDelimiter = RegExp(
  r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*\r?$',
);

bool _interruptsInline(String source, int end, int close, int indent) {
  var start = end + 1;
  while (start < close) {
    end = source.indexOf('\n', start);
    if (end < 0) end = source.length;
    final line = source.substring(start, end);
    final relative = line.substring(_indentCharacters(line, indent));
    if (_inlineBreak.hasMatch(relative)) return true;
    final content = _indentCharacters(relative, _indentWidth(relative));
    if (_indentWidth(relative) < 4 &&
        _codeOpeningEnd(relative, content, relative.length) != null) {
      return true;
    }
    final nextEnd = source.indexOf('\n', end + 1);
    final nextLine = source.substring(
      end < source.length ? end + 1 : end,
      nextEnd < 0 ? source.length : nextEnd,
    );
    if (relative.contains('|') && _tableDelimiter.hasMatch(nextLine)) {
      return true;
    }
    start = end + 1;
  }
  return false;
}

final _codeClose = RegExp(r'\[/code\]', caseSensitive: false);
const _bbcodeQuotes = ['""', "''", '«»', '“”', '””', '‘’', '„“', '‚’', '‹›'];

bool _bbcodeNameUnit(int unit) =>
    unit >= 0x30 && unit <= 0x39 ||
    unit >= 0x41 && unit <= 0x5a ||
    unit >= 0x61 && unit <= 0x7a ||
    unit == 0x5f ||
    unit == 0x2d;

int? _codeOpeningEnd(String source, int at, int end) {
  if (at + 5 > end || source.substring(at, at + 5).toLowerCase() != '[code') {
    return null;
  }
  var next = at + 5;
  if (next < end && _bbcodeNameUnit(source.codeUnitAt(next))) return null;
  while (next < end) {
    if (source[next] == '=') {
      next++;
      if (next >= end) return null;
      final valueStart = next;
      final quote = _bbcodeQuotes
          .where((pair) => pair[0] == source[next])
          .firstOrNull;
      if (quote != null) {
        final close = source.indexOf(quote[1], next + 1);
        if (close > next + 1 && close < end) next = close + 1;
      }
      if (next == valueStart) {
        while (next < end &&
            source[next] != ']' &&
            source[next].trim().isNotEmpty) {
          next++;
        }
      }
      if (next == valueStart) return null;
    }
    while (next < end && source[next].trim().isEmpty) {
      next++;
    }
    if (next >= end) return null;
    if (source[next] == ']') return next + 1;
    final keyStart = next;
    while (next < end && _bbcodeNameUnit(source.codeUnitAt(next))) {
      next++;
    }
    if (next == keyStart) return null;
  }
  return null;
}

int _codeCloseIndex(List<RegExpMatch> closers, int offset) {
  var low = 0;
  var high = closers.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (closers[middle].start < offset) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

({int end, bool block})? _bbcodeCodeAt(
  String source,
  int at,
  int lineEnd,
  int indent,
  bool startsLine,
  int quoteDepth,
  Map<int, int?> codeBlocks,
  List<RegExpMatch> codeClosers,
) {
  final openingEnd = _codeOpeningEnd(source, at, lineEnd);
  if (openingEnd == null) return null;
  final closeIndex = _codeCloseIndex(codeClosers, openingEnd);
  RegExpMatch? sameLine;
  if (startsLine) {
    for (
      var index = closeIndex;
      index < codeClosers.length && codeClosers[index].start < lineEnd;
      index++
    ) {
      sameLine = codeClosers[index];
    }
  }
  // The block rule accepts a same-line closer only at the exact line end.
  final contentEnd = lineEnd > 0 && source[lineEnd - 1] == '\r'
      ? lineEnd - 1
      : lineEnd;
  if (startsLine && sameLine != null && sameLine.end == contentEnd) {
    return (end: sameLine.end, block: true);
  }
  if (startsLine && source.substring(openingEnd, lineEnd).trim().isEmpty) {
    if (!codeBlocks.containsKey(at)) {
      final openers = [at];
      codeBlocks[at] = null;
      var start = lineEnd + 1;
      while (start < source.length) {
        var end = source.indexOf('\n', start);
        if (end < 0) end = source.length;
        final line = source.substring(start, end);
        final width = _indentWidth(line);
        if (line.trim().isNotEmpty && width < indent) break;
        if (width - indent < 4) {
          var content = _indentCharacters(line, width);
          var depth = 0;
          while (true) {
            final quote = _quote.matchAsPrefix(line, content);
            if (quote == null) break;
            content = quote.end;
            depth++;
          }
          if (depth < quoteDepth && line.trim().isNotEmpty) break;
          content += _indentCharacters(line.substring(content), indent);
          final tagAt = start + content;
          final closing = _codeClose.matchAsPrefix(source, tagAt);
          if (closing != null &&
              source.substring(closing.end, end).trim().isEmpty) {
            codeBlocks[openers.removeLast()] = closing.end;
            if (openers.isEmpty) break;
          } else {
            final nestedEnd = _codeOpeningEnd(source, tagAt, end);
            if (nestedEnd != null &&
                source.substring(nestedEnd, end).trim().isEmpty) {
              openers.add(tagAt);
              codeBlocks[tagAt] = null;
            }
          }
        }
        start = end + 1;
      }
    }
    final end = codeBlocks[at];
    if (end != null) return (end: end, block: true);
  }
  // The inline rule takes the first closer within the same paragraph.
  if (closeIndex == codeClosers.length) return null;
  final closing = codeClosers[closeIndex];
  final closeAt = closing.start;
  if (_interruptsInline(source, lineEnd, closeAt, indent)) return null;
  return (end: closing.end, block: false);
}
