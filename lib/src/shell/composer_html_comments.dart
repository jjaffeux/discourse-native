/// HTML comments remain literal source in the editor, but cannot introduce
/// interactive Markdown. Scan in source order so fences/backticks inside a
/// comment cannot hide its closing delimiter or change later code boundaries.
class ComposerHtmlComments {
  ComposerHtmlComments(String source) {
    if (!source.contains('<!--')) return;
    final indents = <int>[];
    String? fence;
    var fenceIndent = 0;
    var inlineEnd = 0;
    var commentEnd = 0;
    var start = 0;
    while (start < source.length) {
      var end = source.indexOf('\n', start);
      if (end < 0) end = source.length;
      final line = source.substring(start, end);
      final indent = _indentWidth(line);
      if (start >= commentEnd && start >= inlineEnd && line.trim().isNotEmpty) {
        if (indent < fenceIndent) fence = null;
        while (indents.isNotEmpty && indent < indents.last) {
          indents.removeLast();
        }
      }
      var content = _indentCharacters(line, indents.lastOrNull ?? 0);
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
      final delimiter = _fence.firstMatch(relative);
      if (start >= commentEnd && start >= inlineEnd) {
        if (fence != null) {
          if (delimiter != null &&
              delimiter[1]![0] == fence[0] &&
              delimiter[1]!.length >= fence.length &&
              delimiter[2]!.trim().isEmpty) {
            fence = null;
          }
          start = end + 1;
          continue;
        }
        if (delimiter != null) {
          fence = delimiter[1];
          fenceIndent = indents.lastOrNull ?? 0;
          start = end + 1;
          continue;
        }
        if (_indentWidth(relative) >= 4) {
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
          final block = line.substring(content, at - start).trim().isEmpty;
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
          _ranges.add((start: at, end: commentEnd));
          at = commentEnd;
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
  }

  final _ranges = <({int start, int end})>[];
  bool get isEmpty => _ranges.isEmpty;

  bool contains(int offset) =>
      _ranges.any((range) => range.start <= offset && offset < range.end);

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

bool _interruptsInline(String source, int end, int close, int indent) {
  var start = end + 1;
  while (start < close) {
    end = source.indexOf('\n', start);
    if (end < 0) end = source.length;
    final line = source.substring(start, end);
    final relative = line.substring(_indentCharacters(line, indent));
    if (_inlineBreak.hasMatch(relative)) return true;
    start = end + 1;
  }
  return false;
}
