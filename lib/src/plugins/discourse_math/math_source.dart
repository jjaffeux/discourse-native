import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:html/dom.dart' as dom;

import 'math_settings.dart';

DMathExpression? readMathElement(dom.Element element) {
  if (element.localName == 'span' && element.classes.contains('asciimath')) {
    return DMathExpression(element.text, input: DMathInput.ascii);
  }
  if ((element.localName == 'span' || element.localName == 'div') &&
      element.classes.contains('math')) {
    return DMathExpression(element.text, display: element.localName == 'div');
  }
  return null;
}

final class MathOccurrence {
  const MathOccurrence(
    this.start,
    this.end,
    this.original,
    this.expression, {
    required this.open,
    required this.close,
    this.prefix = '',
  });
  final int start, end;
  final String original, open, close, prefix;
  final DMathExpression expression;
  String replace(String body) {
    if (body == expression.source) return original;
    if (!expression.display) {
      return '$open${escapeMathDelimiter(body, open)}$close';
    }
    if (!original.contains('\n') && !body.contains('\n')) {
      return '$open$body$close';
    }
    final newline = original.contains('\r\n') ? '\r\n' : '\n';
    return '$open$newline${body.split(RegExp(r'\r?\n')).map((line) => '$prefix$line').join(newline)}$newline$prefix$close';
  }
}

bool _escaped(String source, int index) {
  var count = 0;
  for (var i = index - 1; i >= 0 && source.codeUnitAt(i) == 92; i--) {
    count++;
  }
  return count.isOdd;
}

final _punctuation = RegExp(
  r"[\p{P}\s!#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~]",
  unicode: true,
);
bool _boundary(String source, int offset, String delimiter) =>
    offset < 0 ||
    offset >= source.length ||
    (source[offset] != delimiter &&
        (_punctuation.hasMatch(source[offset]) || source[offset] == 'ฯ'));

/// Source ranges follow the vendored upstream delimiter rules. Containers the
/// native editor cannot make atomic safely remain source, while cooking still
/// uses the complete upstream Markdown parser.
List<MathOccurrence> scanMath(String source, MathSettings settings) {
  if (!settings.enabled || source.length > 65536) return const [];
  final code = markdownCodeRanges(source);
  final protected = <({int start, int end})>[
    for (final match in RegExp(
      r'^(?: {4}|\t).*$',
      multiLine: true,
    ).allMatches(source))
      (start: match.start, end: match.end),
    for (final match in RegExp(
      r'<([A-Za-z][A-Za-z0-9-]*)(?:\s[^>]*|)>[\s\S]*?</\1\s*>',
      caseSensitive: false,
    ).allMatches(source))
      (start: match.start, end: match.end),
    for (final match in RegExp(
      r'^ {0,3}<[A-Za-z][^>]*>[^\n]*(?:\n(?![ \t]*\r?\n)[^\n]*)*',
      multiLine: true,
    ).allMatches(source))
      (start: match.start, end: match.end),
    for (final match in RegExp(
      r'<!--[\s\S]*?(?:-->|$)|<[^>]*>|!?\[[^\]\n]*\]\([^\n]*?\)',
    ).allMatches(source))
      (start: match.start, end: match.end),
  ];
  bool blocked(int start, int end) =>
      code.overlaps(start, end) ||
      protected.any((r) => start < r.end && end > r.start);
  final result = <MathOccurrence>[];
  final lines = RegExp(
    r'[^\n]*(?:\n|$)',
  ).allMatches(source).where((m) => m.start < source.length).toList();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final raw = line.group(0)!.replaceFirst(RegExp(r'\r?\n$'), '');
    // Container controls already own quoted/list block layout. Their math
    // source stays intact rather than creating overlapping block projections.
    if (RegExp(r'^\s*(?:>|[-+*] |\d+[.)] )').hasMatch(raw)) continue;
    final trimmed = raw.trim();
    final open = trimmed.startsWith(r'$$')
        ? r'$$'
        : settings.latexDelimiters && trimmed.startsWith(r'\[')
        ? r'\['
        : null;
    if (open == null) continue;
    final close = open == r'$$' ? r'$$' : r'\]';
    final start = line.start + raw.indexOf(open);
    if (blocked(start, start + 1)) continue;
    if (trimmed.length > open.length + close.length &&
        trimmed.endsWith(close)) {
      final body = trimmed
          .substring(open.length, trimmed.length - close.length)
          .trim();
      if (body.isNotEmpty) {
        result.add(
          MathOccurrence(
            start,
            start + trimmed.length,
            trimmed,
            DMathExpression(body, display: true),
            open: open,
            close: close,
          ),
        );
      }
      continue;
    }
    if (trimmed != open) continue;
    var endLine = i + 1;
    while (endLine < lines.length && lines[endLine].group(0)!.trim() != close) {
      endLine++;
    }
    final closed = endLine < lines.length;
    final end = closed
        ? lines[endLine].start + lines[endLine].group(0)!.trimRight().length
        : source.length;
    var bodyEnd = closed ? lines[endLine].start : source.length;
    if (bodyEnd > line.end && source[bodyEnd - 1] == '\n') bodyEnd--;
    if (bodyEnd > line.end && source[bodyEnd - 1] == '\r') bodyEnd--;
    final body = source.substring(
      line.end,
      bodyEnd.clamp(line.end, source.length),
    );
    result.add(
      MathOccurrence(
        start,
        end,
        source.substring(start, end),
        DMathExpression(body, display: true),
        open: open,
        close: close,
      ),
    );
    i = endLine;
  }
  for (var i = 0; i < source.length; i++) {
    if (blocked(i, i + 1) ||
        result.any((r) => i >= r.start && i < r.end) ||
        _escaped(source, i)) {
      continue;
    }
    final delimiter = source[i];
    String open, close;
    DMathInput input = DMathInput.tex;
    if (settings.latexDelimiters && source.startsWith(r'\(', i)) {
      open = r'\(';
      close = r'\)';
    } else if (delimiter == r'$' ||
        delimiter == '%' && settings.supportsAscii) {
      open = close = delimiter;
      input = delimiter == '%' ? DMathInput.ascii : DMathInput.tex;
      if (!_boundary(source, i - 1, delimiter) ||
          source.startsWith(delimiter, i + 1)) {
        continue;
      }
    } else {
      continue;
    }
    var end = source.indexOf(close, i + open.length);
    while (end >= 0 && _escaped(source, end)) {
      end = source.indexOf(close, end + close.length);
    }
    if (end < 0) continue;
    if (open.length == 1 && !_boundary(source, end + 1, delimiter)) continue;
    final body = source.substring(i + open.length, end);
    if (body.contains('\n') || (open.length == 2 && body.isEmpty)) continue;
    final finish = end + close.length;
    result.add(
      MathOccurrence(
        i,
        finish,
        source.substring(i, finish),
        DMathExpression(body, input: input),
        open: open,
        close: close,
      ),
    );
    i = finish - 1;
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

String escapeMathDelimiter(String source, String delimiter) {
  if (delimiter.length != 1) return source;
  final result = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    if (source[i] == delimiter && !_escaped(source, i)) result.write(r'\');
    result.write(source[i]);
  }
  return result.toString();
}
