import 'package:flutter/services.dart';

/// Physical text rows with offsets into the unchanged UTF-16 source.
class CodeSource {
  factory CodeSource(String text) {
    final ranges = lineRanges(text).toList();
    return CodeSource._(
      text,
      List.unmodifiable([
        for (final range in ranges) text.substring(range.start, range.end),
      ]),
      List.unmodifiable([for (final range in ranges) range.start]),
    );
  }

  const CodeSource._(this.text, this.lines, this.starts);

  static final _breaks = RegExp(r'\r\n|[\n\u000b\u000c\u2028\u2029]');

  static Iterable<TextRange> lineRanges(String text) sync* {
    var start = 0;
    for (final match in _breaks.allMatches(text)) {
      yield TextRange(start: start, end: match.start);
      start = match.end;
    }
    yield TextRange(start: start, end: text.length);
  }

  final String text;
  final List<String> lines;
  final List<int> starts;

  int lineAt(int offset) {
    var low = 0;
    var high = starts.length;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int endOf(int line) => starts[line] + lines[line].length;
}
