import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'composer_images.dart';
import 'markdown_highlight.dart';

/// A Markdown pipe table, retaining each authored line and cell range.
/// Row zero is the header; the delimiter line is never a movable data row.
@immutable
class ComposerTableBlock {
  const ComposerTableBlock._(this.start, this.source, this._lines);

  final int start;
  final String source;
  final List<_TableLine> _lines;

  int get end => start + source.length;
  int get columnCount => _lines.first.cells.length;
  int get rowCount => _lines.length - 2;
  String get _newline => source.contains('\r\n') ? '\r\n' : '\n';
  _TableLine _row(int row) => _lines[row == 0 ? 0 : row + 1];

  String cell(int row, int column) =>
      _row(row).cells.elementAtOrNull(column)?.text ?? '';
  ({String before, String after}) cellPadding(int row, int column) =>
      _row(row).cells.elementAtOrNull(column)?.padding ??
      (before: ' ', after: ' ');

  /// Changes only the cell's content, preserving the rest of the source.
  String editCell(
    int row,
    int column,
    String value, {
    ({String before, String after})? padding,
  }) {
    RangeError.checkValueInInterval(column, 0, columnCount - 1, 'column');
    final line = _row(row);
    if (column >= line.cells.length) {
      if (value.isEmpty) return source;
      final cells = _paddedCells(line);
      final spacing = padding ?? (before: ' ', after: ' ');
      cells[column] = '${spacing.before}${_encodeCell(value)}${spacing.after}';
      return source.replaceRange(
        line.start - start,
        line.start - start + line.text.length,
        _renderLine(line, cells),
      );
    }
    final cell = line.cells[column];
    final spacing = padding ?? cell.padding;
    return source.replaceRange(
      line.start - start + cell.from,
      line.start - start + cell.from + cell.raw.length,
      '${spacing.before}${_encodeCell(value)}${spacing.after}',
    );
  }

  String insertRow(int index) {
    RangeError.checkValueInInterval(index, 0, rowCount, 'index');
    final lines = _lines.map((line) => line.text).toList();
    lines.insert(index + 2, '|${'  |' * columnCount}');
    return lines.join(_newline);
  }

  String moveRow(int from, int to) {
    RangeError.checkValueInInterval(from, 0, rowCount - 1, 'from');
    RangeError.checkValueInInterval(to, 0, rowCount - 1, 'to');
    final lines = _lines.map((line) => line.text).toList();
    lines.insert(to + 2, lines.removeAt(from + 2));
    return lines.join(_newline);
  }

  String removeRow(int index) {
    RangeError.checkValueInInterval(index, 0, rowCount - 1, 'index');
    final lines = _lines.map((line) => line.text).toList()..removeAt(index + 2);
    return lines.join(_newline);
  }

  String insertColumn(int index) {
    RangeError.checkValueInInterval(index, 0, columnCount, 'index');
    return _mapColumns((cells, delimiter) {
      cells.insert(index, delimiter ? ' --- ' : '  ');
    });
  }

  String moveColumn(int from, int to) {
    RangeError.checkValueInInterval(from, 0, columnCount - 1, 'from');
    RangeError.checkValueInInterval(to, 0, columnCount - 1, 'to');
    return _mapColumns((cells, _) => cells.insert(to, cells.removeAt(from)));
  }

  String removeColumn(int index) {
    if (columnCount == 1) return source;
    RangeError.checkValueInInterval(index, 0, columnCount - 1, 'index');
    return _mapColumns((cells, _) => cells.removeAt(index));
  }

  String _mapColumns(void Function(List<String>, bool) change) => [
    for (final (index, line) in _lines.indexed)
      (() {
        final cells = _paddedCells(line);
        change(cells, index == 1);
        return _renderLine(line, cells);
      })(),
  ].join(_newline);

  List<String> _paddedCells(_TableLine line) => [
    for (final cell in line.cells) cell.raw,
    for (var index = line.cells.length; index < columnCount; index++) '  ',
  ];

  String _renderLine(_TableLine line, List<String> cells) =>
      '${line.prefix}|${cells.join('|')}|${line.suffix}';
}

/// Body rows may omit trailing cells or contain additional source cells.
/// Missing cells are empty; surplus cells stay in source, as with cooked posts.
/// Code blocks, quoted/list tables and HTML tables retain their existing owner.
List<ComposerTableBlock> parseComposerTables(String source) {
  if (!source.contains('|')) return const [];
  final code = CodeRanges.of(
    scanMarkdown(source).where((run) => run.has(Md.codeBlock)).toList(),
  );
  final lines = <_TableLine?>[];
  var offset = 0;
  for (final text in source.split('\n')) {
    final line = text.endsWith('\r')
        ? text.substring(0, text.length - 1)
        : text;
    lines.add(_parseLine(line, offset));
    offset += text.length + 1;
  }
  final tables = <ComposerTableBlock>[];
  for (var index = 0; index + 1 < lines.length; index++) {
    final header = lines[index];
    final delimiter = lines[index + 1];
    if (header == null ||
        delimiter == null ||
        code.contains(header.start) ||
        code.contains(delimiter.start) ||
        header.cells.length != delimiter.cells.length ||
        !delimiter.cells.every((cell) => _delimiter.hasMatch(cell.text))) {
      continue;
    }
    final rows = [header, delimiter];
    var next = index + 2;
    while (next < lines.length) {
      final row = lines[next];
      if (row == null || code.contains(row.start)) break;
      final nextLine = lines.elementAtOrNull(next + 1);
      if (nextLine != null &&
          row.cells.length == nextLine.cells.length &&
          nextLine.cells.every((cell) => _delimiter.hasMatch(cell.text))) {
        break;
      }
      rows.add(row);
      next++;
    }
    final end = rows.last.start + rows.last.text.length;
    tables.add(
      ComposerTableBlock._(
        header.start,
        source.substring(header.start, end),
        List.unmodifiable(rows),
      ),
    );
    index = next - 1;
  }
  return List.unmodifiable(tables);
}

final _delimiter = RegExp(r'^:?-+:?$');

_TableLine? _parseLine(String line, int start) {
  if (line.startsWith('    ') || line.startsWith('\t')) return null;
  final trimmed = line.trim();
  if (trimmed.startsWith('>') ||
      RegExp(r'^(?:[-+*]|\d+[.)])\s').hasMatch(trimmed)) {
    return null;
  }
  final images = parseComposerImages(line);
  final pipes = <int>[];
  var slashes = 0;
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '|' &&
        slashes.isEven &&
        !images.any((image) => index >= image.start && index < image.end)) {
      pipes.add(index);
    }
    slashes = char == '\\' ? slashes + 1 : 0;
  }
  if (pipes.isEmpty) return null;
  final leading = line.substring(0, pipes.first).trim().isEmpty;
  final trailing = line.substring(pipes.last + 1).trim().isEmpty;
  final boundaries = [if (!leading) -1, ...pipes, if (!trailing) line.length];
  if (boundaries.length < 2) return null;
  return _TableLine(
    start,
    line,
    leading ? line.substring(0, pipes.first) : '',
    trailing ? line.substring(pipes.last + 1) : '',
    [
      for (var index = 0; index + 1 < boundaries.length; index++)
        _TableCell(line, boundaries[index] + 1, boundaries[index + 1]),
    ],
  );
}

class _TableLine {
  const _TableLine(this.start, this.text, this.prefix, this.suffix, this.cells);
  final int start;
  final String text;
  final String prefix;
  final String suffix;
  final List<_TableCell> cells;
}

class _TableCell {
  _TableCell(String line, this.from, int to) : raw = line.substring(from, to) {
    text = raw.trim();
    // Empty cells have no content boundary. Split their padding so that
    // filling a conventional `|  |` cell produces `| value |`.
    start =
        from +
        (text.isEmpty ? raw.length ~/ 2 : raw.length - raw.trimLeft().length);
    end = text.isEmpty ? start : from + raw.trimRight().length;
  }

  final String raw;
  final int from;
  late final String text;
  late final int start;
  late final int end;

  ({String before, String after}) get padding => (
    before: raw.substring(0, start - from),
    after: raw.substring(end - from),
  );
}

String _encodeCell(String value) {
  final output = StringBuffer();
  var slashes = 0;
  for (final char in value.replaceAll(RegExp(r'\r\n?|\n'), '<br>').split('')) {
    if (char == '|' && slashes.isEven) output.write('\\');
    output.write(char);
    slashes = char == '\\' ? slashes + 1 : 0;
  }
  // An odd trailing slash must not escape the table's closing separator.
  if (slashes.isOdd) output.write('\\');
  return output.toString();
}

/// Native text selection can cross the atom, but cannot partially edit it.
class ComposerTableInputFormatter extends TextInputFormatter {
  const ComposerTableInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) return newValue;
    var start = 0;
    var end = oldValue.text.length;
    var newEnd = newValue.text.length;
    final selection = oldValue.selection;
    if (selection.isValid &&
        !selection.isCollapsed &&
        newValue.text.startsWith(oldValue.text.substring(0, selection.start)) &&
        newValue.text.endsWith(oldValue.text.substring(selection.end))) {
      start = selection.start;
      end = selection.end;
    } else {
      while (start < end &&
          start < newEnd &&
          oldValue.text[start] == newValue.text[start]) {
        start++;
      }
      while (end > start &&
          newEnd > start &&
          oldValue.text[end - 1] == newValue.text[newEnd - 1]) {
        end--;
        newEnd--;
      }
    }
    for (final table in parseComposerTables(oldValue.text)) {
      if (oldValue.isComposingRangeValid &&
          !oldValue.composing.isCollapsed &&
          oldValue.composing.start < table.end &&
          oldValue.composing.end > table.start) {
        continue;
      }
      if (start == end) {
        if (start > table.start && start < table.end) return oldValue;
      } else if (start < table.end &&
          end > table.start &&
          (start > table.start || end < table.end)) {
        // EditableText replays its recorded history through input formatters.
        // A complete table revision with a caret outside the block is valid;
        // a platform edit into hidden source or a broken table is not.
        final delta = newValue.text.length - oldValue.text.length;
        final replacement = parseComposerTables(newValue.text)
            .where(
              (next) =>
                  next.start == table.start && next.end == table.end + delta,
            )
            .firstOrNull;
        bool outside(TextEditingValue value, int start, int end) =>
            value.selection.isValid &&
            value.selection.isCollapsed &&
            (value.selection.extentOffset <= start ||
                value.selection.extentOffset >= end);
        if (replacement != null &&
            outside(oldValue, table.start, table.end) &&
            outside(newValue, replacement.start, replacement.end)) {
          continue;
        }
        return oldValue;
      }
    }
    return newValue;
  }
}
