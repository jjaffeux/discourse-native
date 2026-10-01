import 'composer_list_source.dart';
import 'composer_task_marker.dart';
import 'markdown_highlight.dart';

/// A checklist line keeps its original Markdown as the editable source.
class ComposerTodo {
  const ComposerTodo({
    required this.start,
    required this.markerStart,
    required this.contentStart,
    required this.end,
    required this.checked,
    this.itemEnd,
    this.continuationIndent,
    this.parentStart,
  });

  final int start;
  final int markerStart;
  final int contentStart;
  final int end;
  final bool checked;
  final int? itemEnd;
  final String? continuationIndent;
  final int? parentStart;
  bool get isListItem => continuationIndent != null;
}

final _todoPrefix = RegExp(r'^( {0,3})(\[[ xX]?\])[ \t]*', multiLine: true);

List<ComposerTodo> composerTodos(
  String source, {
  CodeRanges? codeRanges,
  Set<String> referenceMarkers = const {},
}) {
  final matches = _todoPrefix.allMatches(source).toList();
  final lists = composerListItems(source, referenceMarkers: referenceMarkers);
  final structured = <ComposerTodo>[];
  void visit(ComposerListItem item, int Function(int) map, int? parentStart) {
    final mappedStart = map(item.start);
    final start = mappedStart == 0
        ? 0
        : source.lastIndexOf('\n', mappedStart - 1) + 1;
    if (item.isTask) {
      final marker = map(item.taskMarkerStart!);
      structured.add(
        ComposerTodo(
          start: start,
          markerStart: marker,
          contentStart: map(item.contentStart),
          end: map(item.firstLineEnd),
          checked: item.checked,
          itemEnd: map(item.end),
          continuationIndent: ' ' * (marker - start),
          parentStart: parentStart,
        ),
      );
    }
    for (final child in item.children) {
      visit(child, (offset) => map(item.body.sourceOffset(offset)), start);
    }
  }

  for (final item in lists) {
    visit(item, (offset) => offset, null);
  }
  if (matches.isEmpty) return structured;
  final code = codeRanges ?? markdownCodeRanges(source);
  final references = {
    ...referenceMarkers,
    ...composerTaskReferences(source, includeLinkLabels: true),
  };
  return [
    ...structured,
    for (final match in matches)
      if (!code.overlaps(match.start, match.end) &&
          !lists.any(
            (item) => match.start >= item.start && match.start < item.end,
          ) &&
          composerTaskMarker(
                source,
                start: match.start + match[1]!.length,
                referenceMarkers: references,
              ) !=
              null)
        ComposerTodo(
          start: match.start,
          markerStart: match.start + match[1]!.length,
          contentStart: match.end,
          end: _lineEnd(source, match.end),
          checked: match[2]!.toLowerCase() == '[x]',
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
}

int _lineEnd(String source, int start) {
  final newline = source.indexOf('\n', start);
  final end = newline < 0 ? source.length : newline;
  return end > start && source[end - 1] == '\r' ? end - 1 : end;
}
