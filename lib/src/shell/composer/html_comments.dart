import 'markdown_tokens.dart';

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
    var paragraph = false;
    var previousQuoteDepth = 0;
    var indentedCode = false;
    var tokenIndexEnd = 0;
    var tokenCandidates = <int, ComposerMarkdownTokenBoundary>{};
    final activeTokens = <ComposerMarkdownTokenBoundary>[];
    final images = ComposerMarkdownImageReader(source);
    final inlineLiterals = _InlineLiteralEnds(source);
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
      var listStart = false;
      if (start >= commentEnd && start >= inlineEnd && fence == null) {
        final marker = _paragraphBlock.hasMatch(line.substring(content))
            ? null
            : _list.firstMatch(line.substring(content));
        if (marker != null) {
          listStart = true;
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
      final blank = relative.trim().isEmpty;
      final continuesParagraph =
          paragraph && !listStart && quoteDepth == previousQuoteDepth;
      previousQuoteDepth = quoteDepth;
      paragraph =
          !blank &&
          !_paragraphBlock.hasMatch(relative) &&
          !(start < commentEnd && (_ranges.lastOrNull?.block ?? false));
      if (!blank && _indentWidth(relative) < 4) indentedCode = false;
      final delimiter = _fence.firstMatch(relative);
      if (start >= commentEnd && start >= inlineEnd) {
        if (fence != null) {
          paragraph = false;
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
          paragraph = false;
          fence = delimiter[1];
          fenceIndent = indents.lastOrNull ?? 0;
          fenceStart = start;
          nestedFence = content > 0;
          start = end + 1;
          continue;
        }
        if (_indentWidth(relative) >= 4 &&
            (!continuesParagraph || indentedCode)) {
          paragraph = false;
          indentedCode = true;
          _ranges.add((
            start: start,
            end: end,
            kind: _LiteralContainerKind.indentedCode,
            block: true,
          ));
          start = end + 1;
          continue;
        }
      }
      var at = start + content;
      if (at < commentEnd) at = commentEnd;
      if (at < inlineEnd) at = inlineEnd;
      while (at < end) {
        while (activeTokens.isNotEmpty && at >= activeTokens.last.tokenEnd) {
          activeTokens.removeLast();
        }
        if (activeTokens.isNotEmpty && at >= activeTokens.last.labelEnd) {
          inlineEnd = activeTokens.removeLast().tokenEnd;
          at = inlineEnd;
          continue;
        }
        if (source[at] == '[' || source.startsWith('![', at)) {
          if (at >= tokenIndexEnd) {
            tokenIndexEnd = _inlineParagraphEnd(
              source,
              end,
              indents.lastOrNull ?? 0,
            );
            tokenCandidates = composerMarkdownLinkCandidates(
              source,
              start: at,
              end: tokenIndexEnd,
              images: images,
              skipInline: (offset, limit) {
                if (source.startsWith('<!--', offset)) {
                  return inlineLiterals.commentEnd(
                    offset,
                    inlineLiterals.lineEnd(offset),
                    indents.lastOrNull ?? 0,
                    limit,
                  );
                }
                if (source[offset] == '`') {
                  return inlineLiterals.codeEnd(
                    offset,
                    inlineLiterals.lineEnd(offset),
                    indents.lastOrNull ?? 0,
                    limit,
                  );
                }
                return null;
              },
            );
          }
          final bracket = source[at] == '[' ? at : at + 1;
          final token = tokenCandidates[bracket];
          if (token != null &&
              (activeTokens.isEmpty ||
                  activeTokens.last.openerStart != token.openerStart)) {
            activeTokens.add(token);
          }
        }
        if (source[at] == '\\') {
          at += 2;
        } else if (source.startsWith('<!--', at)) {
          final block = at == firstContent && _indentWidth(relative) < 4;
          final closing = inlineLiterals.commentEnd(
            at,
            end,
            indents.lastOrNull ?? 0,
            source.length,
            block: block,
          );
          if (closing == null) {
            at += 4;
            continue;
          }
          commentEnd = closing;
          if (block) paragraph = false;
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
            at == firstContent && _indentWidth(relative) < 4,
            quoteDepth,
            codeBlocks,
            codeClosers,
            inlineLimit: activeTokens.lastOrNull?.labelEnd,
          );
          if (code == null) {
            at++;
          } else {
            commentEnd = code.end;
            if (code.block) paragraph = false;
            _ranges.add((
              start: at,
              end: code.end,
              kind: _LiteralContainerKind.bbcodeCode,
              block: code.block,
            ));
            at = code.end;
          }
        } else if (source[at] == '`') {
          inlineEnd = inlineLiterals.codeEnd(
            at,
            end,
            indents.lastOrNull ?? 0,
            activeTokens.lastOrNull?.labelEnd ?? source.length,
          );
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

final _paragraphBlock = RegExp(
  r'^ {0,3}(?:#{1,6}(?:[ \t]+|$)|(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})\r?$)',
);

final _tableDelimiter = RegExp(
  r'^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*\r?$',
);

bool _interruptsInline(String source, int end, int close, int indent) =>
    _inlineParagraphEnd(source, end, indent, close) < close;

class _InlineLiteralEnds {
  _InlineLiteralEnds(this.source) {
    for (final tick in _ticks.allMatches(source)) {
      (_tickRuns[tick[0]!] ??= []).add(tick);
    }
  }

  final String source;
  final _paragraphEnds = <(int, int, int), int>{};
  final _tickRuns = <String, List<RegExpMatch>>{};
  late final _comments = RegExp('-->').allMatches(source).toList();
  late final _blanks = _blank.allMatches(source).toList();
  late final _lines = RegExp(r'\n').allMatches(source).toList();

  int lineEnd(int offset) {
    final index = _delimiterIndex(_lines, offset);
    return index == _lines.length ? source.length : _lines[index].start;
  }

  int _paragraphEnd(int end, int indent) =>
      _inlineParagraphEnd(source, end, indent, null, _paragraphEnds);

  int? commentEnd(
    int start,
    int lineEnd,
    int indent,
    int limit, {
    bool block = false,
  }) {
    final index = _delimiterIndex(_comments, start + 4);
    if (index == _comments.length) return block ? source.length : null;
    final close = _comments[index];
    if (close.end > limit ||
        (!block && _paragraphEnd(lineEnd, indent) < close.start)) {
      return null;
    }
    return close.end;
  }

  int codeEnd(int start, int lineEnd, int indent, int limit) {
    final opening = _ticks.matchAsPrefix(source, start)!;
    final blankIndex = _delimiterIndex(_blanks, opening.end);
    if (blankIndex < _blanks.length && _blanks[blankIndex].start < limit) {
      limit = _blanks[blankIndex].start;
    }
    final runs = _tickRuns[opening[0]!] ?? const <RegExpMatch>[];
    final closeIndex = _delimiterIndex(runs, opening.end);
    if (closeIndex == runs.length) return opening.end;
    final closing = runs[closeIndex];
    return closing.end <= limit &&
            _paragraphEnd(lineEnd, indent) >= closing.start
        ? closing.end
        : opening.end;
  }
}

int _inlineParagraphEnd(
  String source,
  int end,
  int indent, [
  int? limit,
  Map<(int, int, int), int>? cache,
]) {
  limit ??= source.length;
  final openingStart = source.lastIndexOf('\n', end > 0 ? end - 1 : 0) + 1;
  final openingLine = source.substring(openingStart, end);
  var openingContent = _indentCharacters(openingLine, indent);
  var quoteDepth = 0;
  while (true) {
    final quote = _quote.matchAsPrefix(openingLine, openingContent);
    if (quote == null) break;
    openingContent = quote.end;
    quoteDepth++;
  }
  final cached = cache?[(end, indent, quoteDepth)];
  if (cached != null) return cached;
  final visited = cache == null ? null : <int>[end];
  int finish(int boundary) {
    if (cache != null) {
      for (final lineEnd in visited!) {
        cache[(lineEnd, indent, quoteDepth)] = boundary;
      }
    }
    return boundary;
  }

  var start = end + 1;
  while (start < limit) {
    end = source.indexOf('\n', start);
    if (end < 0) end = source.length;
    final line = source.substring(start, end);
    var lineContent = _indentCharacters(line, indent);
    for (var depth = 0; depth < quoteDepth; depth++) {
      final quote = _quote.matchAsPrefix(line, lineContent);
      if (quote == null) break;
      lineContent = quote.end;
    }
    final relative = line.substring(lineContent);
    if (_inlineBreak.hasMatch(relative)) return finish(start);
    final content = _indentCharacters(relative, _indentWidth(relative));
    if (_indentWidth(relative) < 4 &&
        _codeOpeningEnd(relative, content, relative.length) != null) {
      return finish(start);
    }
    final nextEnd = source.indexOf('\n', end < source.length ? end + 1 : end);
    final nextLine = source.substring(
      end < source.length ? end + 1 : end,
      nextEnd < 0 ? source.length : nextEnd,
    );
    if (relative.contains('|') && _tableDelimiter.hasMatch(nextLine)) {
      return finish(start);
    }
    final nextCached = cache?[(end, indent, quoteDepth)];
    if (nextCached != null) return finish(nextCached);
    visited?.add(end);
    start = end + 1;
  }
  return finish(limit);
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

int _delimiterIndex(List<RegExpMatch> closers, int offset) {
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
  List<RegExpMatch> codeClosers, {
  int? inlineLimit,
}) {
  final openingEnd = _codeOpeningEnd(
    source,
    at,
    inlineLimit != null && inlineLimit < lineEnd ? inlineLimit : lineEnd,
  );
  if (openingEnd == null) return null;
  final closeIndex = _delimiterIndex(codeClosers, openingEnd);
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
  if (inlineLimit != null && closing.end > inlineLimit) return null;
  final closeAt = closing.start;
  if (_interruptsInline(source, lineEnd, closeAt, indent)) return null;
  return (end: closing.end, block: false);
}
