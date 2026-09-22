import 'markdown_highlight.dart';

/// A checklist line keeps its original Markdown as the editable source.
class ComposerTodo {
  const ComposerTodo({
    required this.start,
    required this.markerStart,
    required this.contentStart,
    required this.end,
    required this.checked,
  });

  final int start;
  final int markerStart;
  final int contentStart;
  final int end;
  final bool checked;
}

final _todoPrefix = RegExp(
  r'^( {0,3}(?:[-+*][ \t]+)?)(\[[ xX]?\])(?:[ \t]+|(?=\r?$))',
  multiLine: true,
);

List<ComposerTodo> composerTodos(String source, {CodeRanges? codeRanges}) {
  final matches = _todoPrefix.allMatches(source).toList();
  if (matches.isEmpty) return const [];
  final code = codeRanges ?? CodeRanges.of(scanMarkdown(source));
  final references = RegExp(
    r'^ {0,3}\[([ xX]?)\]:[ \t]*\S',
    multiLine: true,
  ).allMatches(source).map((match) => '[${match[1]!.toLowerCase()}]').toSet();
  return [
    for (final match in matches)
      if (!code.overlaps(match.start, match.end) &&
          !references.contains(match[2]!.toLowerCase()))
        ComposerTodo(
          start: match.start,
          markerStart: match.start + match[1]!.length,
          contentStart: match.end,
          end: _lineEnd(source, match.end),
          checked: match[2]!.toLowerCase() == '[x]',
        ),
  ];
}

int _lineEnd(String source, int start) {
  final newline = source.indexOf('\n', start);
  final end = newline < 0 ? source.length : newline;
  return end > start && source[end - 1] == '\r' ? end - 1 : end;
}
