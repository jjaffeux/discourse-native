import 'package:discourse_native/l10n/strings.dart';

import 'composer_html_comments.dart';
import 'composer_task_marker.dart';

/// A lossless view of a Markdown list item. Indentation belongs to the source;
/// the editor presents the item's body in its own content column.
class ComposerListItem {
  ComposerListItem({
    required this.document,
    required this.start,
    required this.end,
    required this.marker,
    required this.indent,
    required this.contentIndent,
    required this.contentStart,
    required this.firstLineEnd,
    this.taskMarker,
    this.taskMarkerStart,
    this.closed = true,
    this.referenceMarkers = const {},
    this.number,
  });

  final String document;
  final int start, end, indent, contentIndent, contentStart, firstLineEnd;
  final String marker;
  final String? taskMarker;
  final int? taskMarkerStart;
  final bool closed;
  final Set<String> referenceMarkers;

  /// The rendered ordinal, starting at the first marker in this list.
  /// Later source markers remain untouched, as they do in Markdown rendering.
  final int? number;
  String get label => isTask
      ? appL10n.toDo
      : number == null
      ? appL10n.bulletedList
      : appL10n.numberedList;
  String get nextPrefix => number == null
      ? itemPrefix
      : '${' ' * indent}${number! + 1}${marker[marker.length - 1]} ';
  bool get isTask => taskMarker != null;
  bool get checked => taskMarker == '[x]' || taskMarker == '[X]';
  String get source => document.substring(start, end);
  String get newline => document.contains('\r\n') ? '\r\n' : '\n';
  String get continuationPrefix => ' ' * contentIndent;
  String get itemPrefix =>
      document.substring(start, taskMarkerStart ?? contentStart);

  late final body = ComposerListBody(this);
  late final children = _composerListItems(
    body.text,
    referenceMarkers: referenceMarkers,
  );
}

/// Maps editable body offsets to the original source, including lazy
/// continuations, CRLF and the indentation hidden on each subsequent line.
class ComposerListBody {
  ComposerListBody(this.item) {
    final out = StringBuffer();
    var start = item.contentStart;
    var first = true;
    while (start <= item.end) {
      var end = item.document.indexOf('\n', start);
      if (end < 0 || end > item.end) end = item.end;
      final textEnd = end > start && item.document[end - 1] == '\r'
          ? end - 1
          : end;
      if (!first) {
        start += _indentCharacters(
          item.document.substring(start, textEnd),
          item.contentIndent,
        );
        out.write('\n');
      }
      _lines.add((local: out.length, source: start, length: textEnd - start));
      out.write(item.document.substring(start, textEnd));
      if (end == item.end) break;
      start = end + 1;
      first = false;
    }
    text = out.toString();
  }

  final ComposerListItem item;
  final _lines = <({int local, int source, int length})>[];
  late final String text;

  int sourceOffset(int offset) {
    offset = offset.clamp(0, text.length);
    final line = _lines.lastWhere((line) => line.local <= offset);
    return line.source + offset - line.local;
  }

  int localOffset(int sourceOffset) {
    final line = _lines.lastWhere(
      (line) => line.source <= sourceOffset,
      orElse: () => _lines.first,
    );
    return (line.local + (sourceOffset - line.source).clamp(0, line.length))
        .clamp(0, text.length);
  }

  /// Patch only the changed range. Unedited whitespace and Markdown survive
  /// exactly; newly inserted lines receive this list's continuation prefix.
  String replace(String after) {
    var from = 0;
    var oldEnd = text.length;
    var newEnd = after.length;
    while (from < oldEnd && from < newEnd && text[from] == after[from]) {
      from++;
    }
    while (oldEnd > from &&
        newEnd > from &&
        text[oldEnd - 1] == after[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final replacement = after
        .substring(from, newEnd)
        .replaceAll('\n', '${item.newline}${item.continuationPrefix}');
    var sourceStart = sourceOffset(from);
    var sourceEnd = sourceOffset(oldEnd);
    if (replacement.isEmpty &&
        from > 0 &&
        oldEnd > from &&
        oldEnd < text.length &&
        text[from - 1] == '\n' &&
        text[oldEnd - 1] == '\n') {
      // A shared leading newline can put a whole-line deletion after the
      // hidden indentation. Keep the untouched suffix line's own prefix,
      // rather than consuming it or inheriting the removed line's prefix.
      sourceStart = item.document.lastIndexOf('\n', sourceStart - 1) + 1;
      sourceEnd = item.document.lastIndexOf('\n', sourceEnd - 1) + 1;
    }
    return item.source.replaceRange(
      sourceStart - item.start,
      sourceEnd - item.start,
      replacement,
    );
  }
}

final _listMarker = RegExp(r'^( *)([-+*]|\d{1,9}[.)])([ \t]+|$)');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final _interrupt = RegExp(
  r'^(?: {0,3}(?:>|#{1,6}(?:\s|$)|<|\[[ xX]?\](?:\s|$)))',
);
final _rule = RegExp(
  r'^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$',
);
final _blockOpening = RegExp(
  r'^ {0,3}\[([a-zA-Z][\w-]*)(?:[= ][^\]]*)?\][ \t]*$',
);
final _blockClosing = RegExp(r'^ {0,3}\[/([a-zA-Z][\w-]*)\][ \t]*$');

/// Parses outer list items; each body's same parser supplies its nested items.
/// Fenced and indented code keep apparent task markers literal.
///
/// A BBCode block such as a poll bounds items as Discourse's block rule does:
/// its content is parsed only up to the closing tag, so an item inside it never
/// continues past that tag, and its opening tag ends a lazy continuation as it
/// ends a paragraph. Which tags a site registers is not known here, so any tag
/// on a line of its own counts once it is closed; an unclosed one may be a
/// reference link, and Discourse never closes a block at the end of a document.
List<ComposerListItem> composerListItems(
  String source, {
  Set<String> referenceMarkers = const {},
}) => _composerListItems(
  source,
  referenceMarkers: {
    ...referenceMarkers,
    ...composerTaskReferences(source, includeLinkLabels: true),
  },
);

List<ComposerListItem> _composerListItems(
  String source, {
  required Set<String> referenceMarkers,
  bool recognizeTasks = true,
}) {
  final comments = ComposerHtmlComments(source);
  final references = referenceMarkers;
  final lines = <({int start, int end, String text})>[];
  var start = 0;
  while (start < source.length) {
    var end = source.indexOf('\n', start);
    if (end < 0) end = source.length;
    final textEnd = end > start && source[end - 1] == '\r' ? end - 1 : end;
    lines.add((
      start: start,
      end: textEnd,
      text: source.substring(start, textEnd),
    ));
    start = end + 1;
  }
  final result = <ComposerListItem>[];
  final blocks = source.contains('[/')
      ? _blockClosingLines(lines)
      : const <int, int>{};
  // Closing lines of the blocks around the current line, innermost last.
  final closings = <int>[];
  String? outerFence;
  for (var i = 0; i < lines.length;) {
    if (i == closings.lastOrNull) {
      // A fence left open inside a block ends with it too.
      closings.removeLast();
      outerFence = null;
      i++;
      continue;
    }
    final line = lines[i];
    if (comments.contains(line.start + _indentCharacters(line.text, 4))) {
      i++;
      continue;
    }
    final fence = _fence.firstMatch(line.text);
    if (outerFence != null) {
      if (_closesFence(line.text, outerFence)) outerFence = null;
      i++;
      continue;
    }
    if (fence != null) {
      outerFence = fence[1];
      i++;
      continue;
    }
    final closing = blocks[i];
    if (closing != null && closing < (closings.lastOrNull ?? lines.length)) {
      closings.add(closing);
      i++;
      continue;
    }
    final marker = _listMarker.firstMatch(line.text);
    if (marker == null || marker[1]!.length > 3 || _rule.hasMatch(line.text)) {
      i++;
      continue;
    }
    final indent = marker[1]!.length;
    // More than four spaces after a marker begins an indented code block.
    final gap = marker[3]!;
    final markerEnd = indent + marker[2]!.length;
    final gapWidth = _indentWidth(gap, markerEnd);
    final contentIndent = markerEnd + (gapWidth > 4 ? 1 : gapWidth.clamp(1, 4));
    final contentCharacters = gapWidth > 4 ? markerEnd + 1 : marker.end;
    final remainder = line.text.substring(contentCharacters);
    var last = i;
    var next = i + 1;
    var blank = false;
    var paragraph = remainder.isNotEmpty;
    // Lazy lines belong to the innermost paragraph, even when they are not
    // indented into its list. Keep each nested content column until a block
    // boundary returns ownership to an ancestor.
    final continuationIndents = <int>[contentIndent];
    String? itemFence = _fence.firstMatch(remainder)?[1];
    // An enclosing block's closing tag ends its content as the end of the
    // document would.
    final limit = closings.lastOrNull ?? lines.length;
    while (next < limit) {
      final following = lines[next];
      if (following.text.trim().isEmpty) {
        if (next == limit - 1 &&
            _indentWidth(following.text) >= contentIndent) {
          last = next;
        }
        blank = true;
        paragraph = false;
        next++;
        continue;
      }
      final currentIndent = continuationIndents.last;
      final removed = _indentCharacters(following.text, currentIndent);
      final width = _indentWidth(following.text.substring(0, removed));
      final belongs = width >= currentIndent;
      final relative = following.text.substring(removed);
      if (!belongs) {
        final closing = blocks[next];
        if (itemFence != null ||
            blank ||
            !paragraph ||
            _listMarker.hasMatch(following.text) ||
            _interrupt.hasMatch(relative) ||
            _fence.hasMatch(relative) ||
            _rule.hasMatch(relative) ||
            (closing != null && closing < limit)) {
          if (continuationIndents.length > 1) {
            continuationIndents.removeLast();
            itemFence = null;
            paragraph = false;
            continue;
          }
          break;
        }
      } else if (itemFence != null) {
        if (_closesFence(relative, itemFence)) itemFence = null;
      } else if (!comments.contains(following.start + removed)) {
        final nested = _listMarker.firstMatch(relative);
        if (nested != null &&
            nested[1]!.length <= 3 &&
            !_rule.hasMatch(relative)) {
          final markerEnd =
              currentIndent + nested[1]!.length + nested[2]!.length;
          final gapWidth = _indentWidth(nested[3]!, markerEnd);
          continuationIndents.add(
            markerEnd + (gapWidth > 4 ? 1 : gapWidth.clamp(1, 4)),
          );
          final content = relative.substring(
            gapWidth > 4
                ? nested[1]!.length + nested[2]!.length + 1
                : nested.end,
          );
          itemFence = _fence.firstMatch(content)?[1];
          paragraph =
              content.isNotEmpty &&
              itemFence == null &&
              (composerTaskMarker(content) != null ||
                  !_interrupt.hasMatch(content)) &&
              !_rule.hasMatch(content) &&
              !content.startsWith('    ');
        } else {
          final opened = _fence.firstMatch(relative);
          if (opened != null) itemFence = opened[1];
          paragraph =
              opened == null &&
              !_listMarker.hasMatch(relative) &&
              !_interrupt.hasMatch(relative) &&
              !_rule.hasMatch(relative) &&
              !relative.startsWith('    ');
        }
      }
      blank = false;
      last = next++;
    }
    final task = composerTaskMarker(
      source,
      start: line.start + contentCharacters,
      end: lines[last].end,
      referenceMarkers: references,
    );
    final isTask = recognizeTasks && task != null;
    final previous = result.lastOrNull;
    final ordered = int.tryParse(
      marker[2]!.substring(0, marker[2]!.length - 1),
    );
    final continuesNumbering =
        ordered != null &&
        previous?.number != null &&
        previous!.marker.endsWith(marker[2]![marker[2]!.length - 1]) &&
        source.substring(previous.end, line.start).trim().isEmpty;
    result.add(
      ComposerListItem(
        document: source,
        start: line.start,
        end: lines[last].end,
        marker: marker[2]!,
        indent: indent,
        contentIndent: contentIndent,
        contentStart: isTask ? task.end : line.start + contentCharacters,
        firstLineEnd: line.end,
        taskMarker: isTask ? task[0]!.trim() : null,
        taskMarkerStart: isTask ? line.start + contentCharacters : null,
        closed: itemFence == null,
        referenceMarkers: references,
        number: continuesNumbering ? previous.number! + 1 : ordered,
      ),
    );
    i = last + 1;
  }
  return result;
}

/// The closing line of each BBCode block, keyed by its opening line. Tags on
/// lines of their own pair as Discourse's block rule pairs them: with the next
/// closing tag of the same name that is not taken by a nested opening tag,
/// whether or not a fence lies between them.
Map<int, int> _blockClosingLines(
  List<({int start, int end, String text})> lines,
) {
  final blocks = <int, int>{};
  final unclosed = <String, List<int>>{};
  for (var i = 0; i < lines.length; i++) {
    final text = lines[i].text;
    if (_blockOpening.firstMatch(text) case final opening?) {
      (unclosed[opening[1]!.toLowerCase()] ??= []).add(i);
    } else if (_blockClosing.firstMatch(text) case final closing?) {
      final opened = unclosed[closing[1]!.toLowerCase()];
      if (opened != null && opened.isNotEmpty) blocks[opened.removeLast()] = i;
    }
  }
  return blocks;
}

final _referenceDefinition = RegExp(r'^ {0,3}\[([^\[\]]+)\]:[ \t]*\S');
final _referenceHeading = RegExp(
  r'^ {0,3}(?:#{1,6}(?:[ \t]+|$)|(?:=+|-+)[ \t]*$)',
);

/// Reference labels are document-wide, but definitions belong to Markdown
/// blocks. Reuse list boundaries and their deindented bodies so a nested code
/// fence ends with its container and indented code stays literal at any depth.
Set<String> composerTaskReferences(
  String source, {
  bool includeLinkLabels = false,
}) {
  if (includeLinkLabels
      ? !source.contains(']:')
      : !source.contains('[x]:') && !source.contains('[X]:')) {
    return const {};
  }
  final references = <String>{};
  void collect(String text) {
    // Checklist markers are inline syntax. Keep them in the body during this
    // block pass: "- [ ] [x]: url" is a paragraph, not a definition.
    final items = _composerListItems(
      text,
      referenceMarkers: const {},
      recognizeTasks: false,
    ).iterator;
    var hasItem = items.moveNext();
    var offset = 0;
    var paragraph = false;
    String? fence;
    for (final line in text.split('\n')) {
      final start = offset;
      offset += line.length + 1;
      if (hasItem && start > items.current.end) hasItem = items.moveNext();
      if (hasItem && start >= items.current.start) {
        if (start == items.current.start) collect(items.current.body.text);
        paragraph = false;
        continue;
      }
      final content = line.endsWith('\r')
          ? line.substring(0, line.length - 1)
          : line;
      if (fence != null) {
        if (_closesFence(content, fence)) fence = null;
        continue;
      }
      final opening = _fence.firstMatch(content);
      if (opening != null) {
        fence = opening[1];
        paragraph = false;
        continue;
      }
      if (content.trim().isEmpty ||
          _rule.hasMatch(content) ||
          _referenceHeading.hasMatch(content)) {
        paragraph = false;
        continue;
      }
      if (!paragraph) {
        if (_indentWidth(content) >= 4) continue;
        final reference = _referenceDefinition.firstMatch(content);
        if (reference != null) {
          final label = composerTaskReferenceLabel(reference[1]!);
          if (label == '[x]' || (includeLinkLabels && label != '[]')) {
            references.add(label);
          }
          continue;
        }
      }
      paragraph = true;
    }
  }

  collect(source);
  return references;
}

/// Indentation for a new block inserted into the innermost list body at [offset].
String composerListContinuationAt(String source, int offset) {
  String find(String text, int local, int baseIndent) {
    for (final item in composerListItems(text)) {
      if (local < item.contentStart || local > item.end) continue;
      final indent = baseIndent + item.contentIndent;
      final nested = find(item.body.text, item.body.localOffset(local), indent);
      return nested.isEmpty ? ' ' * indent : nested;
    }
    return '';
  }

  return find(source, offset, 0);
}

bool _closesFence(String text, String marker) => RegExp(
  '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
).hasMatch(text);

int _indentWidth(String prefix, [int initialColumn = 0]) {
  var column = initialColumn;
  for (final char in prefix.codeUnits) {
    if (char == 32) {
      column++;
    } else if (char == 9) {
      column += 4 - column % 4;
    } else {
      break;
    }
  }
  return column - initialColumn;
}

int _indentCharacters(String text, int width) {
  var column = 0;
  var characters = 0;
  while (characters < text.length && column < width) {
    final char = text.codeUnitAt(characters);
    if (char != 32 && char != 9) break;
    column += char == 9 ? 4 - column % 4 : 1;
    characters++;
  }
  return characters;
}
