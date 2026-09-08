import 'package:flutter/material.dart';

enum ComposerMark {
  bold('**'),
  italic('*'),
  inlineCode('`');

  const ComposerMark(this.marker);

  final String marker;
}

TextEditingValue toggleMarkdownMark(TextEditingValue value, String marker) {
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);

  if (marker == '`' && !selection.isCollapsed) {
    return _toggleInlineCode(text, selection);
  }

  var start = selection.start;
  var end = selection.end;
  if ((marker == '**' || marker == '*') &&
      !(_endsWithMark(text.substring(0, start), marker) &&
          _startsWithMark(text.substring(end), marker))) {
    // Emphasis cannot open or close against whitespace. Keep it outside new
    // markers, while still allowing existing surrounding markers to unwrap.
    end = start + text.substring(start, end).trimRight().length;
    start = end - text.substring(start, end).trimLeft().length;
  }
  final selected = text.substring(start, end);
  final before = text.substring(0, start);
  final after = text.substring(end);

  if (_isWrapped(selected, marker)) {
    final inner = selected.substring(
      marker.length,
      selected.length - marker.length,
    );
    return TextEditingValue(
      text: '$before$inner$after',
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inner.length,
      ),
    );
  }

  if (_endsWithMark(before, marker) && _startsWithMark(after, marker)) {
    final trimmedBefore = before.substring(0, before.length - marker.length);
    return TextEditingValue(
      text: '$trimmedBefore$selected${after.substring(marker.length)}',
      selection: TextSelection(
        baseOffset: trimmedBefore.length,
        extentOffset: trimmedBefore.length + selected.length,
      ),
    );
  }

  final caret = start + marker.length;
  return TextEditingValue(
    text: '$before$marker$selected$marker$after',
    selection: selection.isCollapsed
        ? TextSelection.collapsed(offset: caret)
        : TextSelection(
            baseOffset: caret,
            extentOffset: caret + selected.length,
          ),
  );
}

final _backtickRuns = RegExp(r'`+');

TextEditingValue _toggleInlineCode(String text, TextSelection selection) {
  final start = selection.start;
  final end = selection.end;
  final selected = text.substring(start, end);

  // A generated span keeps its delimiter and any padding outside the
  // selection. Check that span first: selected ticks can be literal code.
  var before = start;
  if (before > 0 && text[before - 1] == ' ') before--;
  final openingEnd = before;
  while (before > 0 && text[before - 1] == '`') {
    before--;
  }
  var after = end;
  if (after < text.length && text[after] == ' ') after++;
  final closingStart = after;
  while (after < text.length && text[after] == '`') {
    after++;
  }
  if (before < openingEnd && after > closingStart) {
    final unwrapped = _unwrapInlineCode(text, selection, before, after);
    if (unwrapped != null) return unwrapped;
  }
  final unwrapped = _unwrapInlineCode(text, selection, start, end);
  if (unwrapped != null) return unwrapped;

  var width = 1;
  for (final run in _backtickRuns.allMatches(selected)) {
    if (run.end - run.start >= width) width = run.end - run.start + 1;
  }
  final delimiter = List.filled(width, '`').join();
  // Discourse's markdown-it strips a paired boundary space, even from
  // all-space content. Padding also separates literal boundary backticks.
  final pad =
      selected.startsWith('`') ||
      selected.endsWith('`') ||
      (selected.startsWith(' ') && selected.endsWith(' '));
  final marker = pad ? '$delimiter ' : delimiter;
  final closing = pad ? ' $delimiter' : delimiter;
  return TextEditingValue(
    text: text.replaceRange(start, end, '$marker$selected$closing'),
    selection: selection.copyWith(
      baseOffset: selection.baseOffset + marker.length,
      extentOffset: selection.extentOffset + marker.length,
    ),
  );
}

TextEditingValue? _unwrapInlineCode(
  String text,
  TextSelection selection,
  int start,
  int end,
) {
  final source = text.substring(start, end);
  final runs = _backtickRuns.allMatches(source).toList();
  if (runs.length < 2) return null;
  final opening = runs.first;
  final closing = runs.last;
  final width = opening.end - opening.start;
  if (opening.start != 0 ||
      closing.end != source.length ||
      closing.end - closing.start != width ||
      runs
          .skip(1)
          .take(runs.length - 2)
          .any((run) => run.end - run.start == width)) {
    return null;
  }

  var contentStart = start + width;
  var contentEnd = end - width;
  // This is markdown-it's boundary-space rule, including its minimum length.
  if (contentEnd - contentStart > 2 &&
      text[contentStart] == ' ' &&
      text[contentEnd - 1] == ' ') {
    contentStart++;
    contentEnd--;
  }
  final content = text.substring(contentStart, contentEnd);
  int offset(int position) =>
      start + (position - contentStart).clamp(0, content.length);
  return TextEditingValue(
    text: text.replaceRange(start, end, content),
    selection: selection.copyWith(
      baseOffset: offset(selection.baseOffset),
      extentOffset: offset(selection.extentOffset),
    ),
  );
}

bool _isWrapped(String text, String marker) {
  if (text.length < marker.length * 2) return false;
  if (!text.startsWith(marker) || !text.endsWith(marker)) return false;
  return !_continuesRun(text.substring(marker.length), marker);
}

bool _endsWithMark(String before, String marker) =>
    before.endsWith(marker) &&
    !_continuesRun(
      before
          .substring(0, before.length - marker.length)
          .split('')
          .reversed
          .join(),
      marker,
    );

bool _startsWithMark(String after, String marker) =>
    after.startsWith(marker) &&
    !_continuesRun(after.substring(marker.length), marker);

bool _continuesRun(String rest, String marker) =>
    marker.length == 1 && rest.startsWith(marker);
